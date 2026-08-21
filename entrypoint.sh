#!/bin/bash
# =============================================================================
#  Multi Database - Universal Container Entrypoint
#  By PotenFYR Studios (https://github.com/PotenFYR-Studios/Database-Eggs)
#
#  Responsibilities:
#    1. Load persisted configuration (.multi-db.conf and .db_credentials).
#    2. Cross-panel variable normalization (Pterodactyl, Pelican, Feather, Wisp, Jexactyl, etc.).
#    3. Automatic cryptographic generation of ultra-strong passwords & secrets.
#    4. Dynamic performance auto-tuning & security policy enforcement.
#    5. Terminal banner & live connection info display with masked debug logging.
#    6. Dispatch to universal launcher (run.sh).
# =============================================================================

set -uo pipefail

# --- Colors -----------------------------------------------------------------
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

export PATH="${SERVER_DIR}/bin:${SERVER_DIR}/scripts:/usr/local/bin:${PATH}"

# Source performance and version helpers if present
[ -f "${SERVER_DIR}/scripts/performance-tuning.sh" ] && source "${SERVER_DIR}/scripts/performance-tuning.sh"
[ -f /usr/local/bin/performance-tuning.sh ] && source /usr/local/bin/performance-tuning.sh
[ -f "${SERVER_DIR}/scripts/password-gen.sh" ] && source "${SERVER_DIR}/scripts/password-gen.sh"
[ -f /usr/local/bin/password-gen.sh ] && source /usr/local/bin/password-gen.sh

# Default Timezone
TZ=${TZ:-UTC}
export TZ

# Cross-panel variable normalization
SERVER_PORT="${SERVER_PORT:-${PORT:-${ALLOCATION_PORT:-${SERVER_PORT_0:-3306}}}}"
export SERVER_PORT
SERVER_MEMORY="${SERVER_MEMORY:-${MEMORY:-${MEM_SIZE:-${P_SERVER_MEMORY:-1024}}}}"
export SERVER_MEMORY
SERVER_IP="${SERVER_IP:-${IP:-${P_SERVER_IP:-0.0.0.0}}}"
export SERVER_IP

INTERNAL_IP=$(ip route get 1 2>/dev/null | awk '{print $(NF-2);exit}' || echo "${SERVER_IP}")
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
            PERFORMANCE_TUNING SECURITY_HARDENING; do
    apply_persisted "${_key}" "${CONF_FILE}"
    apply_persisted "${_key}" "${CRED_FILE}"
done
unset _key

# Database type resolution
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
        head -c 128 /dev/urandom | tr -dc 'A-Za-z0-9._~-' | head -c "${len}"
    fi
}

# Auto-generate DB_ROOT_PASSWORD & DB_PASSWORD if empty or set to auto
if [ "${AUTO_GENERATE_CREDENTIALS}" = "1" ]; then
    if [ -z "${DB_ROOT_PASSWORD:-}" ] || [ "${DB_ROOT_PASSWORD}" = "auto" ] || [ "${DB_ROOT_PASSWORD}" = "generate" ]; then
        DB_ROOT_PASSWORD=$(gen_rand 32 urlsafe)
        export DB_ROOT_PASSWORD
    fi

    if [ -z "${DB_PASSWORD:-}" ] || [ "${DB_PASSWORD}" = "auto" ] || [ "${DB_PASSWORD}" = "generate" ]; then
        DB_PASSWORD=$(gen_rand 32 urlsafe)
        export DB_PASSWORD
    fi

    # Persist credentials with strict file permissions (chmod 600)
    {
        printf '# Auto-Generated Database Credentials (DO NOT SHARE)\n'
        printf 'DB_ROOT_PASSWORD=%s\n' "${DB_ROOT_PASSWORD}"
        printf 'DB_PASSWORD=%s\n' "${DB_PASSWORD}"
        printf 'DB_USER=%s\n' "${DB_USER:-dbuser}"
        printf 'DB_NAME=%s\n' "${DB_NAME:-database}"
        printf 'PROJECT_TYPE=%s\n' "${PROJECT_TYPE}"
        printf 'DB_VERSION=%s\n' "${DB_VERSION}"
        printf 'GENERATED_AT=%s\n' "$(date -u +'%Y-%m-%d %H:%M:%S UTC')"
    } > "${CRED_FILE}"
    chmod 600 "${CRED_FILE}" 2>/dev/null || true

    # Formatted credentials overview
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
    } > "${SERVER_DIR}/credentials.txt"
    chmod 600 "${SERVER_DIR}/credentials.txt" 2>/dev/null || true

    # .env format for application integration
    if [ ! -f "${SERVER_DIR}/.env" ]; then
        {
            printf 'DB_CONNECTION=%s\n' "${PROJECT_TYPE}"
            printf 'DB_HOST=127.0.0.1\n'
            printf 'DB_PORT=%s\n' "${SERVER_PORT}"
            printf 'DB_DATABASE=%s\n' "${DB_NAME:-database}"
            printf 'DB_USERNAME=%s\n' "${DB_USER:-dbuser}"
            printf 'DB_PASSWORD="%s"\n' "${DB_PASSWORD}"
            printf 'DB_ROOT_PASSWORD="%s"\n' "${DB_ROOT_PASSWORD}"
        } > "${SERVER_DIR}/.env"
        chmod 600 "${SERVER_DIR}/.env" 2>/dev/null || true
    fi
fi

# Masked Debug Log Helper
if [ "${DEBUG:-0}" = "1" ]; then
    warn "DEBUG mode active. Resolved environment (secrets securely masked):"
    env | grep -E '^(DATABASE_|DB_|SERVER_|MEM_|CPU_|TUNED_|TZ|INTERNAL_IP)' | while read -r line; do
        k="${line%%=*}"
        v="${line#*=}"
        if [[ "${k}" =~ (PASS|SECRET|KEY|TOKEN) ]]; then
            echo "${k}=******"
        else
            echo "${k}=${v}"
        fi
    done | sort
fi

# --- ASCII Banner -----------------------------------------------------------
printf "${C_CYAN}${C_BOLD}"
cat << 'EOF'
  ____        _        _                    _____                  
 |  _ \  __ _| |_ __ _| |__   __ _ ___  ___| ____|__ _  __ _ ___ 
 | | | |/ _` | __/ _` | '_ \ / _` / __|/ _ \  _| / _` |/ _` / __|
 | |_| | (_| | || (_| | |_) | (_| \__ \  __/ |__| (_| | (_| \__ \
 |____/ \__,_|\__\__,_|_.__/ \__,_|___/\___|_____\__, |\__, |___/
                                                 |___/ |___/     
EOF
printf "${C_RESET}"
printf "${C_YELLOW}${C_BOLD}   :: PotenFYR Studios Universal Database Platform ::${C_RESET}\n\n"

printf "${C_BOLD} ┌─────────────────────────────────────────────────────────────┐${C_RESET}\n"
printf "${C_BOLD} │ %-18s: ${C_GREEN}%-38s${C_RESET}${C_BOLD} │${C_RESET}\n" "Database Engine" "${PROJECT_TYPE^^} (v${DB_VERSION})"
printf "${C_BOLD} │ %-18s: ${C_CYAN}%-38s${C_RESET}${C_BOLD} │${C_RESET}\n" "Listen Address" "0.0.0.0:${SERVER_PORT}"
printf "${C_BOLD} │ %-18s: ${C_MAGENTA}%-38s${C_RESET}${C_BOLD} │${C_RESET}\n" "Allocated Memory" "${SERVER_MEMORY} MB"
printf "${C_BOLD} │ %-18s: ${C_BLUE}%-38s${C_RESET}${C_BOLD} │${C_RESET}\n" "Database / Schema" "${DB_NAME:-default}"
printf "${C_BOLD} │ %-18s: ${C_YELLOW}%-38s${C_RESET}${C_BOLD} │${C_RESET}\n" "Security Mode" "Strict Cryptographic / SCRAM / Auth"
printf "${C_BOLD} └─────────────────────────────────────────────────────────────┘${C_RESET}\n\n"

log "Executing startup launcher..."

# Execute run.sh or custom launcher
if [ -f "${SERVER_DIR}/run.custom.sh" ]; then
    log "Custom launcher detected (run.custom.sh). Executing..."
    chmod +x "${SERVER_DIR}/run.custom.sh"
    exec "${SERVER_DIR}/run.custom.sh" "$@"
elif [ -f "${SERVER_DIR}/run.sh" ]; then
    chmod +x "${SERVER_DIR}/run.sh"
    exec "${SERVER_DIR}/run.sh" "$@"
elif [ -f /usr/local/bin/run.sh ]; then
    exec /usr/local/bin/run.sh "$@"
else
    STARTUP="${STARTUP:-bash run.sh}"
    STARTUP_EVAL=$(eval echo $(echo "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g'))
    exec ${STARTUP_EVAL}
fi
