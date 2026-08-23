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

export C_RESET C_BOLD C_CYAN C_GREEN C_YELLOW C_RED C_MAGENTA C_BLUE C_DIM

PANEL_NAME="${PANEL_NAME:-${P_SERVER_UUID:+pterodactyl}}"
PANEL_NAME="${PANEL_NAME:-panel}"

log()   { printf "${C_CYAN}${C_BOLD}container@${PANEL_NAME}~${C_RESET} ${C_BOLD}%s${C_RESET}\n" "$*"; }
ok()    { printf "${C_CYAN}${C_BOLD}container@${PANEL_NAME}~${C_RESET} ${C_GREEN}${C_BOLD}[ok]${C_RESET} %s\n" "$*"; }
warn()  { printf "${C_CYAN}${C_BOLD}container@${PANEL_NAME}~${C_RESET} ${C_YELLOW}${C_BOLD}[warn]${C_RESET} %s\n" "$*"; }
error() { printf "${C_CYAN}${C_BOLD}container@${PANEL_NAME}~${C_RESET} ${C_RED}${C_BOLD}[error]${C_RESET} %s\n" "$*" >&2; }
fail()  {
    printf "\n${C_CYAN}${C_BOLD}container@${PANEL_NAME}~${C_RESET} ${C_RED}${C_BOLD}[fatal error]${C_RESET} %s\n\n" "$*" >&2
    write_crash_report "$*" "${LINENO:-0}" "${BASH_COMMAND:-?}"
    # Pause briefly so user can see the error in the panel console before container exits
    sleep 8
    exit 1
}

# -----------------------------------------------------------------------------
# Deep Crash Diagnostics (sanitized stack trace + environment snapshot)
# -----------------------------------------------------------------------------
write_crash_report() {
    local reason="$1" line_no="${2:-0}" last_cmd="${3:-?}"
    mkdir -p "${SERVER_DIR:-.}/logs" 2>/dev/null || true
    local report="${SERVER_DIR:-.}/logs/startup_error.log"
    {
        printf '\n=== CRASH REPORT (%s) ===\n' "$(date -u +'%Y-%m-%d %H:%M:%S UTC')"
        printf 'Panel       : %s (%s)\n' "${PANEL_NAME:-unknown}" "${PANEL_TYPE:-unknown}"
        printf 'Reason      : %s\n' "$reason"
        printf 'Exit Line   : entrypoint.sh:L%s\n' "${line_no}"
        printf 'Last Command: %s\n' "$(printf '%s' "${last_cmd}" | sed -E 's/(PASSWORD|PASSWD|SECRET|TOKEN|KEY)([A-Z_]*=)[^ ]+/\1\2<masked>/gI')"
        printf 'Engine      : %s (requested v%s)\n' "${PROJECT_TYPE:-${DB_TYPE:-?}}" "${DB_VERSION:-latest}"
        printf 'Port/Mem    : %s / %s MB\n' "${SERVER_PORT:-?}" "${SERVER_MEMORY:-?}"
        printf 'UID:GID     : %s:%s | Arch: %s\n' "$(id -u 2>/dev/null || echo ?)" "$(id -g 2>/dev/null || echo ?)" "$(uname -m)"
        printf 'Disk Free   : %s\n' "$(df -h "${SERVER_DIR:-.}" 2>/dev/null | awk 'NR==2{print $4}')"
        printf 'Stack:\n'
        local i=1
        while [ ${i} -lt ${#FUNCNAME[@]} ] 2>/dev/null; do
            printf '  #%d %s (called from line %s)\n' "$((i-1))" "${FUNCNAME[${i}]:-main}" "${BASH_LINENO[$((i-1))]:-?}" 2>/dev/null || break
            i=$((i+1))
        done
        printf 'Environment (sanitized):\n'
        env | sort | grep -viE 'PASSWORD|PASSWD|SECRET|TOKEN|_KEY|CREDENTIAL' | sed 's/^/  /' 2>/dev/null || true
        printf 'Recent engine logs:\n'
        for lf in "${SERVER_DIR:-.}/logs"/*.log; do
            [ -f "${lf}" ] && { printf -- '--- %s ---\n' "$(basename "${lf}")"; tail -n 15 "${lf}" 2>/dev/null; }
        done
        printf '==============================\n'
    } >> "${report}" 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# Universal Panel Detection (Pterodactyl, Pelican, Feather, Wisp, Convoy,
# Cytopanel, Arcadia, Kubernetes/OpenShift, plain Docker, anything else)
# -----------------------------------------------------------------------------
detect_panel() {
    PANEL_TYPE="standalone"
    PANEL_NAME="panel"

    if [ -n "${PANEL_TYPE_OVERRIDE:-}" ]; then
        PANEL_TYPE="${PANEL_TYPE_OVERRIDE}"
    elif [ -n "${P_SERVER_UUID:-}" ] || [ -n "${P_SERVER_LOCATION:-}" ]; then
        PANEL_TYPE="pelican"          # Wings v2 environment variables
    elif [ -n "${KUBERNETES_SERVICE_HOST:-}" ]; then
        if [ -n "${OPENSHIFT_BUILD_NAME:-}" ]; then
            PANEL_TYPE="openshift"
        else
            PANEL_TYPE="kubernetes"
        fi
    elif [ -n "${WISP_SERVER_UUID:-}" ] || [ -d "/.wisp" ]; then
        PANEL_TYPE="wisp"
    elif [ -n "${CONVOY_SERVER_UUID:-}" ]; then
        PANEL_TYPE="convoy"
    elif [ -d /mnt/server ] && [ ! -d /home/container ]; then
        PANEL_TYPE="pterodactyl"      # classic wings mount layout
    elif [ -d /home/container ]; then
        PANEL_TYPE="wings-family"     # Pterodactyl/Pelican/Feather/Cytopanel compatible daemon
    fi

    PANEL_NAME="${PANEL_NAME_ENV:-}"
    [ -z "${PANEL_NAME}" ] && [ "${PANEL_TYPE}" = "pelican" ] && PANEL_NAME="pelican"
    [ -z "${PANEL_NAME}" ] && [ -n "${P_SERVER_UUID:-}" ] && PANEL_NAME="pterodactyl"
    [ -z "${PANEL_NAME}" ] && PANEL_NAME="${PANEL_TYPE}"
    export PANEL_TYPE PANEL_NAME
}
detect_panel

# Diagnostic Error Trap
error_trap() {
    local exit_code=$?
    local line_no=$1
    local last_cmd="${BASH_COMMAND}"
    if [ ${exit_code} -ne 0 ] && [ ${exit_code} -ne 130 ] && [ ${exit_code} -ne 143 ]; then
        printf "\n${C_RED}${C_BOLD}┌─────────────────────────────────────────────────────────────┐${C_RESET}\n" >&2
        printf "${C_RED}${C_BOLD}│  ✗ STARTUP PROCESS CRASH DETECTED                           │${C_RESET}\n" >&2
        printf "${C_RED}${C_BOLD}├─────────────────────────────────────────────────────────────┤${C_RESET}\n" >&2
        printf "${C_RED}${C_BOLD}│${C_RESET}  ${C_BOLD}%-18s${C_RESET} : %-36s ${C_RED}${C_BOLD}│${C_RESET}\n" "Exit Code" "${exit_code}" >&2
        printf "${C_RED}${C_BOLD}│${C_RESET}  ${C_BOLD}%-18s${C_RESET} : %-36s ${C_RED}${C_BOLD}│${C_RESET}\n" "Source Line" "entrypoint.sh:L${line_no}" >&2
        printf "${C_RED}${C_BOLD}│${C_RESET}  ${C_BOLD}%-18s${C_RESET} : %-36s ${C_RED}${C_BOLD}│${C_RESET}\n" "Failed Command" "${last_cmd:0:36}" >&2
        printf "${C_RED}${C_BOLD}│${C_RESET}  ${C_BOLD}%-18s${C_RESET} : %-36s ${C_RED}${C_BOLD}│${C_RESET}\n" "Diagnostic Log" "logs/startup_error.log" >&2
        printf "${C_RED}${C_BOLD}└─────────────────────────────────────────────────────────────┘${C_RESET}\n\n" >&2

        mkdir -p "${SERVER_DIR:-.}/logs" 2>/dev/null || true
        {
            printf '=== STARTUP CRASH REPORT (%s) ===\n' "$(date -u +'%Y-%m-%d %H:%M:%S UTC')"
            printf 'Exit Code: %s\n' "${exit_code}"
            printf 'Script Line: %s\n' "${line_no}"
            printf 'Command: %s\n' "${last_cmd}"
            printf 'Working Directory: %s\n' "${SERVER_DIR:-$(pwd)}"
            printf 'Container User: %s (UID: %s, GID: %s)\n' "$(whoami 2>/dev/null || echo '?')" "$(id -u 2>/dev/null || echo '?')" "$(id -g 2>/dev/null || echo '?')"
            printf 'Allocated Port: %s\n' "${SERVER_PORT:-?}"
            printf 'Allocated Memory: %s MB\n' "${SERVER_MEMORY:-?}"
            printf 'Database Engine: %s (v%s)\n' "${DATABASE_TYPE:-${DB_TYPE:-mariadb}}" "${DB_VERSION:-latest}"
            printf '==================================================\n'
        } >> "${SERVER_DIR:-.}/logs/startup_error.log" 2>/dev/null || true
        sleep 6
    fi
}
trap 'error_trap $LINENO' ERR

# Universal UID/GID Mapping (Resolves 'initdb: could not look up effective user ID <UID>: user does not exist')
CURRENT_UID=$(id -u 2>/dev/null || echo "988")
CURRENT_GID=$(id -g 2>/dev/null || echo "988")
if ! whoami >/dev/null 2>&1 || ! getent passwd "${CURRENT_UID}" >/dev/null 2>&1; then
    if [ -w /etc/passwd ]; then
        echo "container:x:${CURRENT_UID}:${CURRENT_GID}:container user:${HOME:-/home/container}:/bin/bash" >> /etc/passwd 2>/dev/null || true
    fi
fi
if ! getent group "${CURRENT_GID}" >/dev/null 2>&1; then
    if [ -w /etc/group ]; then
        echo "container:x:${CURRENT_GID}:" >> /etc/group 2>/dev/null || true
    fi
fi

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
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL --retry 3 "${REPO_BASE}/run.sh" -o "${RUNTIME_DIR}/run.sh" 2>/dev/null || true
            for h in companion-loader.sh password-gen.sh performance-tuning.sh install-db-version.sh db-init-mariadb.sh db-init-postgres.sh db-init-redis.sh db-init-mongo.sh db-init-surreal.sh db-init-search.sh db-init-storage.sh db-init-extra.sh; do
                curl -fsSL --retry 2 "${REPO_BASE}/scripts/${h}" -o "${RUNTIME_DIR}/${h}" 2>/dev/null || true
            done
        elif command -v wget >/dev/null 2>&1; then
            wget -qO "${RUNTIME_DIR}/run.sh" "${REPO_BASE}/run.sh" 2>/dev/null || true
            for h in companion-loader.sh password-gen.sh performance-tuning.sh install-db-version.sh db-init-mariadb.sh db-init-postgres.sh db-init-redis.sh db-init-mongo.sh db-init-surreal.sh db-init-search.sh db-init-storage.sh db-init-extra.sh; do
                wget -qO "${RUNTIME_DIR}/${h}" "${REPO_BASE}/scripts/${h}" 2>/dev/null || true
            done
        fi
        chmod +x "${RUNTIME_DIR}"/*.sh 2>/dev/null || true
    fi
fi

if [ ! -f "${RUNTIME_DIR}/run.sh" ] && [ ! -f /usr/local/bin/run.sh ] && [ ! -f "${SERVER_DIR}/run.custom.sh" ]; then
    error "Runtime launcher (run.sh) could not be located or downloaded."
    error "Troubleshooting steps:"
    error "1. Ensure your server uses the official image: ghcr.io/potenfyr-studios/database-eggs:latest"
    error "2. Ensure the server node has outbound internet access to githubusercontent.com"
    fail "Fatal: Runtime launcher unavailable."
fi

export PATH="/usr/lib/postgresql/18/bin:/usr/lib/postgresql/17/bin:/usr/lib/postgresql/16/bin:/usr/lib/postgresql/15/bin:${SERVER_DIR}/bin:${RUNTIME_DIR}:/usr/local/bin:${PATH}"

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

# Customizable bind address (security: bind to INTERNAL_IP in shared infra)
BIND_ADDRESS="${BIND_ADDRESS:-${LISTEN_HOST:-0.0.0.0}}"
export BIND_ADDRESS

# Security profile: strict (default) enables hardened defaults everywhere
SECURITY_LEVEL="${SECURITY_LEVEL:-strict}"
export SECURITY_LEVEL

INTERNAL_IP=$(ip route get 1 2>/dev/null | awk '{print $(NF-2);exit}' 2>/dev/null || echo "${SERVER_IP}")
export INTERNAL_IP

# --- Persisted Settings & Credentials (.env only) -----------------------------
ENV_FILE="${SERVER_DIR}/.env"

# Clean up any legacy plain-text credential files so sensitive info is strictly in .env
rm -f "${SERVER_DIR}/credentials.txt" "${SERVER_DIR}/.db_credentials" "${SERVER_DIR}/.multi-db.conf" 2>/dev/null || true

read_env_val() {
    local key="$1"
    [ -f "${ENV_FILE}" ] || return 1
    local val
    val=$(grep -E "^${key}=" "${ENV_FILE}" 2>/dev/null | tail -n1 | cut -d= -f2-)
    [ -n "${val}" ] || return 1
    # Strip quotes and whitespace
    printf '%s' "${val}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//"
}

apply_persisted() {
    local key="$1"
    local val
    val=$(read_env_val "${key}") || return 0
    # If the current environment variable is unset, empty, or "auto"/"generate", load persisted value
    if [ -z "${!key-}" ] || [ "${!key}" = "auto" ] || [ "${!key}" = "generate" ]; then
        printf -v "${key}" '%s' "${val}"
        export "${key}"
    fi
}

for _key in DATABASE_TYPE DB_TYPE DB_VERSION DB_NAME DB_USER DB_PASSWORD DB_ROOT_PASSWORD \
            AUTO_GENERATE_CREDENTIALS EXTRA_ARGS DATA_DIR KEEP_BACKUP \
            PERFORMANCE_TUNING SECURITY_HARDENING CUSTOM_DOWNLOAD_URL CUSTOM_BINARY_NAME CUSTOM_COMMAND; do
    apply_persisted "${_key}"
done
unset _key

# Also map common .env variations (DB_DATABASE, DB_USERNAME)
if [ -z "${DB_NAME:-}" ]; then
    DB_NAME=$(read_env_val "DB_DATABASE") || true
fi
if [ -z "${DB_USER:-}" ]; then
    DB_USER=$(read_env_val "DB_USERNAME") || true
fi

DB_TYPE="${DATABASE_TYPE:-${DB_TYPE:-mariadb}}"
PROJECT_TYPE=$(echo "${DB_TYPE}" | tr '[:upper:]' '[:lower:]')
DB_VERSION="${DB_VERSION:-latest}"
export PROJECT_TYPE DB_VERSION

SAVE_TO_ENV="${SAVE_TO_ENV:-${SAVE_ENV:-1}}"

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

# Auto-generate credentials if empty, auto, or generate (otherwise use user-provided password)
if [ "${AUTO_GENERATE_CREDENTIALS}" = "1" ]; then
    if [ -z "${DB_ROOT_PASSWORD:-}" ] || [ "${DB_ROOT_PASSWORD}" = "auto" ] || [ "${DB_ROOT_PASSWORD}" = "generate" ]; then
        DB_ROOT_PASSWORD=$(gen_rand 32 urlsafe)
    fi
    if [ -z "${DB_PASSWORD:-}" ] || [ "${DB_PASSWORD}" = "auto" ] || [ "${DB_PASSWORD}" = "generate" ]; then
        DB_PASSWORD=$(gen_rand 32 urlsafe)
    fi
fi

DB_USER="${DB_USER:-dbuser}"
DB_NAME="${DB_NAME:-database}"
export DB_ROOT_PASSWORD DB_PASSWORD DB_USER DB_NAME

# Export latest active credentials into process environment for startup command, subshells & CLI tools
export PGPASSWORD="${DB_PASSWORD:-${DB_ROOT_PASSWORD}}"
export MYSQL_PWD="${DB_PASSWORD:-${DB_ROOT_PASSWORD}}"
export REDISCLI_AUTH="${DB_PASSWORD:-${DB_ROOT_PASSWORD}}"
export MONGO_PWD="${DB_PASSWORD:-${DB_ROOT_PASSWORD}}"
export SURREAL_PASS="${DB_PASSWORD:-${DB_ROOT_PASSWORD}}"

# Save and synchronize sensitive credentials into .env if enabled (Optional: SAVE_TO_ENV=1)
if [ "${SAVE_TO_ENV}" = "1" ] || [ "${SAVE_TO_ENV}" = "true" ] || [ "${SAVE_TO_ENV}" = "yes" ]; then
    {
        printf '# Database Configuration & Credentials (Synced by PotenFYR Runtime)\n'
        printf 'DB_CONNECTION=%s\n' "${PROJECT_TYPE}"
        printf 'DB_HOST=127.0.0.1\n'
        printf 'DB_PORT=%s\n' "${SERVER_PORT}"
        printf 'DB_DATABASE=%s\n' "${DB_NAME}"
        printf 'DB_USERNAME=%s\n' "${DB_USER}"
        printf 'DB_PASSWORD="%s"\n' "${DB_PASSWORD}"
        printf 'DB_ROOT_PASSWORD="%s"\n' "${DB_ROOT_PASSWORD}"
        printf 'DB_VERSION=%s\n' "${DB_VERSION}"
    } > "${ENV_FILE}" 2>/dev/null || true
    chmod 600 "${ENV_FILE}" 2>/dev/null || true
fi

# Generate user environment shortcuts for terminal CLI usage (.profile and .bashrc)
{
    printf 'export PATH="/usr/lib/postgresql/16/bin:/usr/lib/postgresql/15/bin:/usr/lib/postgresql/14/bin:%s/bin:%s:/usr/local/bin:${PATH}"\n' "${SERVER_DIR}" "${RUNTIME_DIR}"
    printf '[ -f "%s/.env" ] && set -a && source "%s/.env" 2>/dev/null && set +a\n' "${SERVER_DIR}" "${SERVER_DIR}"
    printf 'export DB_PASSWORD="%s"\n' "${DB_PASSWORD}"
    printf 'export DB_ROOT_PASSWORD="%s"\n' "${DB_ROOT_PASSWORD}"
    printf 'export PGPASSWORD="%s"\n' "${DB_PASSWORD:-${DB_ROOT_PASSWORD}}"
    printf 'export MYSQL_PWD="%s"\n' "${DB_PASSWORD:-${DB_ROOT_PASSWORD}}"
    printf 'export REDISCLI_AUTH="%s"\n' "${DB_PASSWORD:-${DB_ROOT_PASSWORD}}"
    printf 'export MONGO_PWD="%s"\n' "${DB_PASSWORD:-${DB_ROOT_PASSWORD}}"
    printf 'export SURREAL_PASS="%s"\n' "${DB_PASSWORD:-${DB_ROOT_PASSWORD}}"

    case "${PROJECT_TYPE}" in
        mariadb|mysql)
            printf 'alias db-cli="mysql -h 127.0.0.1 -P %s -u %s -p\"%s\" %s"\n' "${SERVER_PORT}" "${DB_USER:-root}" "${DB_PASSWORD:-${DB_ROOT_PASSWORD}}" "${DB_NAME}"
            ;;
        postgresql|postgres)
            printf 'alias db-cli="psql -h 127.0.0.1 -p %s -U %s -d %s"\n' "${SERVER_PORT}" "${DB_USER:-postgres}" "${DB_NAME:-postgres}"
            ;;
        redis|valkey|keydb|dragonfly)
            printf 'alias db-cli="redis-cli -h 127.0.0.1 -p %s -a \"%s\""\n' "${SERVER_PORT}" "${DB_PASSWORD:-${DB_ROOT_PASSWORD}}"
            ;;
        mongodb|ferretdb)
            printf 'alias db-cli="mongosh \"mongodb://%s:%s@127.0.0.1:%s/%s?authSource=admin\""\n' "${DB_USER:-root}" "${DB_PASSWORD:-${DB_ROOT_PASSWORD}}" "${SERVER_PORT}" "${DB_NAME}"
            ;;
        surrealdb)
            printf 'alias db-cli="surreal sql --endpoint http://127.0.0.1:%s --user %s --pass \"%s\""\n' "${SERVER_PORT}" "${DB_USER:-root}" "${DB_PASSWORD:-${DB_ROOT_PASSWORD}}"
            ;;
    esac
} > "${SERVER_DIR}/.profile" 2>/dev/null || true
cp -f "${SERVER_DIR}/.profile" "${SERVER_DIR}/.bashrc" 2>/dev/null || true
chmod 600 "${SERVER_DIR}/.profile" "${SERVER_DIR}/.bashrc" 2>/dev/null || true

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
printf "${C_CYAN}${C_BOLD}│${C_RESET}  ${C_BOLD}%-18s${C_RESET} : ${C_CYAN}%-36s${C_RESET}  ${C_CYAN}${C_BOLD}│${C_RESET}\n" "Listen Address" "${BIND_ADDRESS:-0.0.0.0}:${SERVER_PORT}"
printf "${C_CYAN}${C_BOLD}│${C_RESET}  ${C_BOLD}%-18s${C_RESET} : ${C_MAGENTA}%-36s${C_RESET}  ${C_CYAN}${C_BOLD}│${C_RESET}\n" "Allocated Memory" "${SERVER_MEMORY} MB"
printf "${C_CYAN}${C_BOLD}│${C_RESET}  ${C_BOLD}%-18s${C_RESET} : ${C_BLUE}%-36s${C_RESET}  ${C_CYAN}${C_BOLD}│${C_RESET}\n" "Database / Schema" "${DB_NAME:-default}"
printf "${C_CYAN}${C_BOLD}│${C_RESET}  ${C_BOLD}%-18s${C_RESET} : ${C_DIM}%-36s${C_RESET}  ${C_CYAN}${C_BOLD}│${C_RESET}\n" "Detected Panel" "${PANEL_TYPE:-standalone}"
printf "${C_CYAN}${C_BOLD}│${C_RESET}  ${C_BOLD}%-18s${C_RESET} : ${C_YELLOW}%-36s${C_RESET}  ${C_CYAN}${C_BOLD}│${C_RESET}\n" "Security Mode" "Strict Cryptographic / SCRAM / Auth"
printf "${C_CYAN}${C_BOLD}└─────────────────────────────────────────────────────────────┘${C_RESET}\n\n"

log "Executing startup launcher..."

# Execute run.custom.sh if user explicitly provided one, otherwise execute canonical image launcher
if [ -f "${SERVER_DIR}/run.custom.sh" ]; then
    log "Custom launcher detected (run.custom.sh). Executing..."
    chmod +x "${SERVER_DIR}/run.custom.sh" 2>/dev/null || true
    exec "${SERVER_DIR}/run.custom.sh"
elif [ -f "${RUNTIME_DIR}/run.sh" ]; then
    chmod +x "${RUNTIME_DIR}/run.sh" 2>/dev/null || true
    exec "${RUNTIME_DIR}/run.sh"
elif [ -f /usr/local/bin/run.sh ]; then
    exec /usr/local/bin/run.sh
else
    fail "Runtime launcher not found."
fi
