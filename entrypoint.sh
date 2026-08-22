#!/bin/bash
# =============================================================================
#  Multi Database - Universal Container Entrypoint
#  By PotenFYR Studios (https://github.com/PotenFYR-Studios/Database-Eggs)
# =============================================================================

# Colors
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_CYAN='\033[36m'
C_GREEN='\033[32m'
C_YELLOW='\033[33m'
C_RED='\033[31m'
C_MAGENTA='\033[35m'
C_BLUE='\033[34m'
C_DIM='\033[2m'

PANEL_NAME="${PANEL_NAME:-${P_SERVER_UUID:+pterodactyl}}"
PANEL_NAME="${PANEL_NAME:-panel}"

log()   { printf "${C_CYAN}${C_BOLD}container@${PANEL_NAME}~${C_RESET} ${C_BOLD}%s${C_RESET}\n" "$*"; }
ok()    { printf "${C_CYAN}${C_BOLD}container@${PANEL_NAME}~${C_RESET} ${C_GREEN}${C_BOLD}[ok]${C_RESET} %s\n" "$*"; }
warn()  { printf "${C_CYAN}${C_BOLD}container@${PANEL_NAME}~${C_RESET} ${C_YELLOW}${C_BOLD}[warn]${C_RESET} %s\n" "$*"; }
error() { printf "${C_CYAN}${C_BOLD}container@${PANEL_NAME}~${C_RESET} ${C_RED}${C_BOLD}[error]${C_RESET} %s\n" "$*"; }

# Universal working directory detection
if [ -d /home/container ]; then
    cd /home/container 2>/dev/null || true
elif [ -d /mnt/server ]; then
    cd /mnt/server 2>/dev/null || true
else
    cd "$(pwd)" 2>/dev/null || true
fi
SERVER_DIR="$(pwd)"

# Create clean user directory tree
mkdir -p "${SERVER_DIR}/data" "${SERVER_DIR}/config" "${SERVER_DIR}/logs" "${SERVER_DIR}/bin"

# Backward-Compatibility & Cleanup:
# Remove obsolete root scripts copied by previous egg versions so old servers run cleanly on latest image scripts
if [ -f "${SERVER_DIR}/run.sh" ] && [ -f /usr/local/bin/run.sh ]; then
    rm -f "${SERVER_DIR}/run.sh" 2>/dev/null || true
fi
if [ -f "${SERVER_DIR}/entrypoint.sh" ] && [ -f /entrypoint.sh ]; then
    rm -f "${SERVER_DIR}/entrypoint.sh" 2>/dev/null || true
fi
if [ -d "${SERVER_DIR}/scripts" ] && [ -f /usr/local/bin/password-gen.sh ]; then
    rm -rf "${SERVER_DIR}/scripts" 2>/dev/null || true
fi

# Fallback bootstrap for generic images (only when not running the official pre-baked image)
RUNTIME_DIR="/usr/local/bin"
if [ ! -f "${RUNTIME_DIR}/run.sh" ]; then
    RUNTIME_DIR="/tmp/.database-runtime"
    mkdir -p "${RUNTIME_DIR}"
    if [ ! -f "${RUNTIME_DIR}/run.sh" ]; then
        log "Bootstrapping runtime components into isolated runtime space..."
        REPO_BASE="https://raw.githubusercontent.com/PotenFYR-Studios/Database-Eggs/main"
        curl -fsSL --retry 3 "${REPO_BASE}/run.sh" -o "${RUNTIME_DIR}/run.sh" 2>/dev/null || true
        for h in password-gen.sh performance-tuning.sh install-db-version.sh db-init-mariadb.sh db-init-postgres.sh db-init-redis.sh db-init-mongo.sh db-init-surreal.sh db-init-search.sh db-init-storage.sh; do
            curl -fsSL --retry 2 "${REPO_BASE}/scripts/${h}" -o "${RUNTIME_DIR}/${h}" 2>/dev/null || true
        done
        chmod +x "${RUNTIME_DIR}"/*.sh 2>/dev/null || true
    fi
fi

export PATH="/usr/lib/postgresql/16/bin:/usr/lib/postgresql/15/bin:/usr/lib/postgresql/14/bin:${SERVER_DIR}/bin:${RUNTIME_DIR}:/usr/local/bin:${PATH}"

# Source performance and helper scripts safely
[ -f "${RUNTIME_DIR}/performance-tuning.sh" ] && source "${RUNTIME_DIR}/performance-tuning.sh" 2>/dev/null || true
[ -f "${RUNTIME_DIR}/password-gen.sh" ] && source "${RUNTIME_DIR}/password-gen.sh" 2>/dev/null || true

# Default Timezone
TZ="${TZ:-UTC}"
export TZ

# Cross-panel variable normalization
SERVER_PORT="${SERVER_PORT:-${PORT:-${ALLOCATION_PORT:-${SERVER_PORT_0:-3306}}}}"
export SERVER_PORT
SERVER_MEMORY="${SERVER_MEMORY:-${MEMORY:-${MEM_SIZE:-${P_SERVER_MEMORY:-1024}}}}"
export SERVER_MEMORY
SERVER_IP="${SERVER_IP:-${IP:-${P_SERVER_IP:-0.0.0.0}}}"
export SERVER_IP

INTERNAL_IP=$(ip route get 1 2>/dev/null | awk '{print $(NF-2);exit}' 2>/dev/null || echo "${SERVER_IP}")
export INTERNAL_IP

# --- Persisted Settings & Credentials ----------------------------------------
CONF_FILE="${SERVER_DIR}/.multi-db.conf"
CRED_FILE="${SERVER_DIR}/.db_credentials"

read_conf_val() {
    local file="$1" key="$2"
    [ -f "${file}" ] || return 1
    local val
    val=$(grep -E "^${key}=" "${file}" 2>/dev/null | tail -n1 | cut -d= -f2-)
    [ -n "${val}" ] || return 1
    printf '%s' "${val}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

apply_persisted() {
    local key="$1" file="${2:-${CONF_FILE}}" val
    val=$(read_conf_val "${file}" "${key}") || return 0
    if [ -z "${!key-}" ]; then
        printf -v "${key}" '%s' "${val}"
        export "${key}"
    fi
}

for _key in DATABASE_TYPE DB_TYPE DB_VERSION DB_NAME DB_USER DB_PASSWORD DB_ROOT_PASSWORD \
            AUTO_GENERATE_CREDENTIALS EXTRA_ARGS DATA_DIR KEEP_BACKUP \
            PERFORMANCE_TUNING SECURITY_HARDENING CUSTOM_DOWNLOAD_URL CUSTOM_BINARY_NAME CUSTOM_COMMAND; do
    apply_persisted "${_key}" "${CONF_FILE}"
    apply_persisted "${_key}" "${CRED_FILE}"
done
unset _key

DB_TYPE="${DATABASE_TYPE:-${DB_TYPE:-mariadb}}"
PROJECT_TYPE=$(echo "${DB_TYPE}" | tr '[:upper:]' '[:lower:]')
DB_VERSION="${DB_VERSION:-latest}"
export PROJECT_TYPE DB_VERSION

AUTO_GENERATE_CREDENTIALS="${AUTO_GENERATE_CREDENTIALS:-1}"

# --- Strong Random Password & Secret Generation -------------------------------
gen_rand() {
    local len="${1:-32}" mode="${2:-urlsafe}"
    if command -v generate_secret >/dev/null 2>&1; then
        generate_secret "${len}" "${mode}"
    elif command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 96 | tr -dc 'A-Za-z0-9._~-' | head -c "${len}"
    else
        head -c 128 /dev/urandom 2>/dev/null | tr -dc 'A-Za-z0-9._~-' | head -c "${len}" || echo "SecuredSecret_$(date +%s)_PotenFYR"
    fi
}

# Auto-generate credentials if empty or auto
if [ "${AUTO_GENERATE_CREDENTIALS}" = "1" ]; then
    if [ -z "${DB_ROOT_PASSWORD:-}" ] || [ "${DB_ROOT_PASSWORD}" = "auto" ] || [ "${DB_ROOT_PASSWORD}" = "generate" ]; then
        DB_ROOT_PASSWORD=$(gen_rand 32 urlsafe)
        export DB_ROOT_PASSWORD
    fi

    if [ -z "${DB_PASSWORD:-}" ] || [ "${DB_PASSWORD}" = "auto" ] || [ "${DB_PASSWORD}" = "generate" ]; then
        DB_PASSWORD=$(gen_rand 32 urlsafe)
        export DB_PASSWORD
    fi

    {
        printf '# Auto-Generated Database Credentials (DO NOT SHARE)\n'
        printf 'DB_ROOT_PASSWORD=%s\n' "${DB_ROOT_PASSWORD}"
        printf 'DB_PASSWORD=%s\n' "${DB_PASSWORD}"
        printf 'DB_USER=%s\n' "${DB_USER:-dbuser}"
        printf 'DB_NAME=%s\n' "${DB_NAME:-database}"
        printf 'PROJECT_TYPE=%s\n' "${PROJECT_TYPE}"
        printf 'DB_VERSION=%s\n' "${DB_VERSION}"
        printf 'GENERATED_AT=%s\n' "$(date -u +'%Y-%m-%d %H:%M:%S UTC')"
    } > "${CRED_FILE}" 2>/dev/null || true
    chmod 600 "${CRED_FILE}" 2>/dev/null || true

    {
        printf '=====================================================\n'
        printf '       POTENFYR STUDIOS - DATABASE CREDENTIALS       \n'
        printf '=====================================================\n'
        printf 'Engine:        %s (v%s)\n' "${PROJECT_TYPE}" "${DB_VERSION}"
        printf 'Host (Local):  127.0.0.1\n'
        printf 'Host (Docker): %s\n' "${INTERNAL_IP}"
        printf 'Port:          %s\n' "${SERVER_PORT}"
        printf 'Database Name: %s\n' "${DB_NAME:-database}"
        printf 'User:          %s\n' "${DB_USER:-dbuser}"
        printf 'User Password: %s\n' "${DB_PASSWORD}"
        printf 'Root/Admin:    root / admin / postgres\n'
        printf 'Root Password: %s\n' "${DB_ROOT_PASSWORD}"
        printf '=====================================================\n'
    } > "${SERVER_DIR}/credentials.txt" 2>/dev/null || true
    chmod 600 "${SERVER_DIR}/credentials.txt" 2>/dev/null || true

    if [ ! -f "${SERVER_DIR}/.env" ]; then
        {
            printf 'DB_CONNECTION=%s\n' "${PROJECT_TYPE}"
            printf 'DB_HOST=127.0.0.1\n'
            printf 'DB_PORT=%s\n' "${SERVER_PORT}"
            printf 'DB_DATABASE=%s\n' "${DB_NAME:-database}"
            printf 'DB_USERNAME=%s\n' "${DB_USER:-dbuser}"
            printf 'DB_PASSWORD="%s"\n' "${DB_PASSWORD}"
            printf 'DB_ROOT_PASSWORD="%s"\n' "${DB_ROOT_PASSWORD}"
        } > "${SERVER_DIR}/.env" 2>/dev/null || true
        chmod 600 "${SERVER_DIR}/.env" 2>/dev/null || true
    fi

    # Generate user environment shortcuts for easy terminal CLI usage
    {
        printf 'export PATH="/usr/lib/postgresql/16/bin:/usr/lib/postgresql/15/bin:/usr/lib/postgresql/14/bin:%s/bin:%s:/usr/local/bin:${PATH}"\n' "${SERVER_DIR}" "${RUNTIME_DIR}"
        printf 'export DB_CONNECTION="%s"\n' "${PROJECT_TYPE}"
        printf 'export DB_HOST="127.0.0.1"\n'
        printf 'export DB_PORT="%s"\n' "${SERVER_PORT}"
        printf 'export DB_DATABASE="%s"\n' "${DB_NAME:-database}"
        printf 'export DB_USERNAME="%s"\n' "${DB_USER:-dbuser}"
        printf 'export DB_PASSWORD="%s"\n' "${DB_PASSWORD}"
        printf 'export DB_ROOT_PASSWORD="%s"\n' "${DB_ROOT_PASSWORD}"
        printf 'export PGPASSWORD="%s"\n' "${DB_PASSWORD:-${DB_ROOT_PASSWORD}}"
        printf 'export MYSQL_PWD="%s"\n' "${DB_PASSWORD:-${DB_ROOT_PASSWORD}}"
        printf 'export REDISCLI_AUTH="%s"\n' "${DB_PASSWORD:-${DB_ROOT_PASSWORD}}"

        case "${PROJECT_TYPE}" in
            mariadb|mysql)
                printf 'alias db-cli="mysql -h 127.0.0.1 -P %s -u %s -p\"%s\" %s"\n' "${SERVER_PORT}" "${DB_USER:-root}" "${DB_PASSWORD:-${DB_ROOT_PASSWORD}}" "${DB_NAME:-database}"
                ;;
            postgresql|postgres)
                printf 'alias db-cli="psql -h 127.0.0.1 -p %s -U %s -d %s"\n' "${SERVER_PORT}" "${DB_USER:-postgres}" "${DB_NAME:-postgres}"
                ;;
            redis|valkey|keydb|dragonfly)
                printf 'alias db-cli="redis-cli -h 127.0.0.1 -p %s -a \"%s\""\n' "${SERVER_PORT}" "${DB_PASSWORD:-${DB_ROOT_PASSWORD}}"
                ;;
            mongodb|ferretdb)
                printf 'alias db-cli="mongosh \"mongodb://%s:%s@127.0.0.1:%s/%s?authSource=admin\""\n' "${DB_USER:-root}" "${DB_PASSWORD:-${DB_ROOT_PASSWORD}}" "${SERVER_PORT}" "${DB_NAME:-database}"
                ;;
            surrealdb)
                printf 'alias db-cli="surreal sql --endpoint http://127.0.0.1:%s --user %s --pass \"%s\""\n' "${SERVER_PORT}" "${DB_USER:-root}" "${DB_PASSWORD:-${DB_ROOT_PASSWORD}}"
                ;;
        esac
    } > "${SERVER_DIR}/.profile" 2>/dev/null || true
    cp -f "${SERVER_DIR}/.profile" "${SERVER_DIR}/.bashrc" 2>/dev/null || true
    chmod 600 "${SERVER_DIR}/.profile" "${SERVER_DIR}/.bashrc" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Startup banner (Compact Slant font, clean ANSI gradient)
# ---------------------------------------------------------------------------
printf "\n"
printf "${C_CYAN}${C_BOLD}   __  ___      ____  _       ____  ____     ${C_RESET}\n"
printf "${C_CYAN}${C_BOLD}  /  |/  /_  __/ / /_(_)     / __ \\/ __ )    ${C_RESET}\n"
printf "${C_BLUE}${C_BOLD} / /|_/ / / / / / __/ /_____/ / / / __  |    ${C_RESET}\n"
printf "${C_BLUE}${C_BOLD}/ /  / / /_/ / / /_/ /_____/ /_/ / /_/ /     ${C_RESET}\n"
printf "${C_MAGENTA}${C_BOLD}/_/  /_/\\__,_/_/\\__/_/     /_____/_____/      ${C_RESET}\n"
printf "${C_YELLOW}${C_BOLD}  » Universal Multi-Database Server Runtime${C_RESET}\n"
printf "${C_DIM}    By PotenFYR Studios • support@potenfyr.in${C_RESET}\n\n"

# Runtime Environment Card
printf "${C_CYAN}${C_BOLD}┌─────────────────────────────────────────────────────────────┐${C_RESET}\n"
printf "${C_CYAN}${C_BOLD}│${C_RESET}  ${C_BOLD}%-18s${C_RESET} : ${C_GREEN}%-36s${C_RESET}  ${C_CYAN}${C_BOLD}│${C_RESET}\n" "Database Engine" "${PROJECT_TYPE^^} (v${DB_VERSION})"
printf "${C_CYAN}${C_BOLD}│${C_RESET}  ${C_BOLD}%-18s${C_RESET} : ${C_CYAN}%-36s${C_RESET}  ${C_CYAN}${C_BOLD}│${C_RESET}\n" "Listen Address" "0.0.0.0:${SERVER_PORT}"
printf "${C_CYAN}${C_BOLD}│${C_RESET}  ${C_BOLD}%-18s${C_RESET} : ${C_MAGENTA}%-36s${C_RESET}  ${C_CYAN}${C_BOLD}│${C_RESET}\n" "Allocated Memory" "${SERVER_MEMORY} MB"
printf "${C_CYAN}${C_BOLD}│${C_RESET}  ${C_BOLD}%-18s${C_RESET} : ${C_BLUE}%-36s${C_RESET}  ${C_CYAN}${C_BOLD}│${C_RESET}\n" "Database / Schema" "${DB_NAME:-default}"
printf "${C_CYAN}${C_BOLD}│${C_RESET}  ${C_BOLD}%-18s${C_RESET} : ${C_YELLOW}%-36s${C_RESET}  ${C_CYAN}${C_BOLD}│${C_RESET}\n" "Security Mode" "Strict Cryptographic / SCRAM / Auth"
printf "${C_CYAN}${C_BOLD}└─────────────────────────────────────────────────────────────┘${C_RESET}\n\n"

log "Executing startup launcher..."

# Execute run.custom.sh if user explicitly provided one, otherwise execute canonical image launcher
if [ -f "${SERVER_DIR}/run.custom.sh" ]; then
    log "Custom launcher detected (run.custom.sh). Executing..."
    chmod +x "${SERVER_DIR}/run.custom.sh"
    exec "${SERVER_DIR}/run.custom.sh"
elif [ -f "${RUNTIME_DIR}/run.sh" ]; then
    chmod +x "${RUNTIME_DIR}/run.sh"
    exec "${RUNTIME_DIR}/run.sh"
elif [ -f /usr/local/bin/run.sh ]; then
    exec /usr/local/bin/run.sh
else
    fail "Runtime launcher not found."
fi
