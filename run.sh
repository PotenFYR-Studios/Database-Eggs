#!/bin/bash
# =============================================================================
#  Multi Database - Universal Server Launcher
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
C_DIM='\033[2m'

PANEL_NAME="${PANEL_NAME:-${P_SERVER_UUID:+pterodactyl}}"
PANEL_NAME="${PANEL_NAME:-panel}"

log()   { printf "${C_CYAN}${C_BOLD}container@${PANEL_NAME}~${C_RESET} ${C_BOLD}%s${C_RESET}\n" "$*"; }
ok()    { printf "${C_CYAN}${C_BOLD}container@${PANEL_NAME}~${C_RESET} ${C_GREEN}${C_BOLD}[ok]${C_RESET} %s\n" "$*"; }
warn()  { printf "${C_CYAN}${C_BOLD}container@${PANEL_NAME}~${C_RESET} ${C_YELLOW}${C_BOLD}[warn]${C_RESET} %s\n" "$*"; }
error() { printf "${C_CYAN}${C_BOLD}container@${PANEL_NAME}~${C_RESET} ${C_RED}${C_BOLD}[error]${C_RESET} %s\n" "$*" >&2; }
fail()  {
    printf "\n${C_CYAN}${C_BOLD}container@${PANEL_NAME}~${C_RESET} ${C_RED}${C_BOLD}[fatal error]${C_RESET} %s\n\n" "$*" >&2
    mkdir -p "${SERVER_DIR:-.}/logs" 2>/dev/null || true
    printf '[%s] FATAL: %s\n' "$(date -u +'%Y-%m-%d %H:%M:%S UTC')" "$*" >> "${SERVER_DIR:-.}/logs/startup_error.log" 2>/dev/null || true
    sleep 8
    exit 1
}

# Diagnostic Error Trap
print_crash_diagnostics() {
    local exit_code=$1
    local line_no=$2
    local last_cmd="$3"

    if [ ${exit_code} -ne 0 ] && [ ${exit_code} -ne 130 ] && [ ${exit_code} -ne 143 ]; then
        printf "\n${C_RED}${C_BOLD}┌─────────────────────────────────────────────────────────────┐${C_RESET}\n" >&2
        printf "${C_RED}${C_BOLD}│  ✗ CRITICAL DATABASE CRASH DIAGNOSTIC REPORT                │${C_RESET}\n" >&2
        printf "${C_RED}${C_BOLD}├─────────────────────────────────────────────────────────────┤${C_RESET}\n" >&2
        printf "${C_RED}${C_BOLD}│${C_RESET}  ${C_BOLD}%-18s${C_RESET} : %-36s ${C_RED}${C_BOLD}│${C_RESET}\n" "Exit Code" "${exit_code}" >&2
        printf "${C_RED}${C_BOLD}│${C_RESET}  ${C_BOLD}%-18s${C_RESET} : %-36s ${C_RED}${C_BOLD}│${C_RESET}\n" "Database Engine" "${PROJECT_TYPE^^} (v${DB_VERSION})" >&2
        printf "${C_RED}${C_BOLD}│${C_RESET}  ${C_BOLD}%-18s${C_RESET} : %-36s ${C_RED}${C_BOLD}│${C_RESET}\n" "Source Line" "run.sh:L${line_no}" >&2
        printf "${C_RED}${C_BOLD}│${C_RESET}  ${C_BOLD}%-18s${C_RESET} : %-36s ${C_RED}${C_BOLD}│${C_RESET}\n" "Failed Command" "${last_cmd:0:36}" >&2
        printf "${C_RED}${C_BOLD}│${C_RESET}  ${C_BOLD}%-18s${C_RESET} : %-36s ${C_RED}${C_BOLD}│${C_RESET}\n" "Memory Limit" "${SERVER_MEMORY:-?} MB" >&2
        printf "${C_RED}${C_BOLD}│${C_RESET}  ${C_BOLD}%-18s${C_RESET} : %-36s ${C_RED}${C_BOLD}│${C_RESET}\n" "Allocated Port" "${SERVER_PORT:-?}" >&2
        printf "${C_RED}${C_BOLD}│${C_RESET}  ${C_BOLD}%-18s${C_RESET} : %-36s ${C_RED}${C_BOLD}│${C_RESET}\n" "Diagnostic Log" "logs/startup_error.log" >&2
        printf "${C_RED}${C_BOLD}└─────────────────────────────────────────────────────────────┘${C_RESET}\n\n" >&2

        mkdir -p "${SERVER_DIR:-.}/logs" 2>/dev/null || true
        {
            printf '=== CRASH DIAGNOSTICS (%s) ===\n' "$(date -u +'%Y-%m-%d %H:%M:%S UTC')"
            printf 'Exit Code: %s\nLine: %s\nCommand: %s\n' "${exit_code}" "${line_no}" "${last_cmd}"
            printf 'Engine: %s (v%s)\nPort: %s\nMemory: %s MB\n' "${PROJECT_TYPE}" "${DB_VERSION}" "${SERVER_PORT:-?}" "${SERVER_MEMORY:-?}"
            printf 'Disk Space:\n%s\n' "$(df -h "${SERVER_DIR}" 2>/dev/null || true)"
            printf 'Recent Logs:\n'
            for lf in "${SERVER_DIR}/logs"/*.log; do
                if [ -f "${lf}" ]; then
                    printf '--- %s ---\n' "$(basename "${lf}")"
                    tail -n 20 "${lf}" 2>/dev/null || true
                fi
            done
            printf '=======================================\n'
        } >> "${SERVER_DIR:-.}/logs/startup_error.log" 2>/dev/null || true

        # 5-second console grace period for panel stream synchronization
        sleep 5
    fi
}
trap 'print_crash_diagnostics $? $LINENO "${BASH_COMMAND}"' ERR

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

if [ -d /home/container ]; then
    cd /home/container 2>/dev/null || true
elif [ -d /mnt/server ]; then
    cd /mnt/server 2>/dev/null || true
else
    cd "$(pwd)" 2>/dev/null || true
fi
SERVER_DIR="$(pwd)"

# Build isolated workspace environment
build_isolated_environment() {
    local data_dir="${DATA_DIR:-${SERVER_DIR}/data}"
    local conf_dir="${SERVER_DIR}/config"
    local log_dir="${SERVER_DIR}/logs"
    local run_dir="${SERVER_DIR}/run"
    local bin_dir="${SERVER_DIR}/bin"
    local runtimes_dir="${SERVER_DIR}/.runtimes"

    mkdir -p "${data_dir}" "${conf_dir}" "${log_dir}" "${run_dir}" "${bin_dir}" "${runtimes_dir}"
    chmod 755 "${SERVER_DIR}" "${conf_dir}" "${log_dir}" "${bin_dir}" "${runtimes_dir}" 2>/dev/null || true
    chmod 700 "${data_dir}" "${run_dir}" 2>/dev/null || true
}
build_isolated_environment

export PATH="/usr/lib/postgresql/16/bin:/usr/lib/postgresql/15/bin:/usr/lib/postgresql/14/bin:${SERVER_DIR}/bin:${SERVER_DIR}/.runtimes/bin:/tmp/.database-runtime:/usr/local/bin:${PATH}"

# Source .env if available to load active credentials and parameters
if [ -f "${SERVER_DIR}/.env" ]; then
    set -a
    # shellcheck source=/dev/null
    source "${SERVER_DIR}/.env" 2>/dev/null || true
    set +a
fi

# Export credentials into process environment for shell & CLI tools
export PGPASSWORD="${DB_PASSWORD:-${DB_ROOT_PASSWORD:-}}"
export MYSQL_PWD="${DB_PASSWORD:-${DB_ROOT_PASSWORD:-}}"
export REDISCLI_AUTH="${DB_PASSWORD:-${DB_ROOT_PASSWORD:-}}"
export MONGO_PWD="${DB_PASSWORD:-${DB_ROOT_PASSWORD:-}}"
export SURREAL_PASS="${DB_PASSWORD:-${DB_ROOT_PASSWORD:-}}"

# Source all modular initialization handlers, performance tuning, and companion loader
for script in /usr/local/bin/companion-loader.sh /usr/local/bin/db-init-*.sh /usr/local/bin/performance-*.sh \
              /tmp/.database-runtime/companion-loader.sh /tmp/.database-runtime/db-init-*.sh /tmp/.database-runtime/performance-*.sh \
              "${SERVER_DIR}/scripts"/companion-loader.sh "${SERVER_DIR}/scripts"/db-init-*.sh; do
    [ -f "${script}" ] && source "${script}" 2>/dev/null || true
done

# Dynamic companion injection (Python, Node.js, Litestream, Rclone, AWS CLI, Database CLIs)
if command -v load_companions >/dev/null 2>&1; then
    load_companions
fi

PROJECT_TYPE=$(echo "${DB_TYPE:-${DATABASE_TYPE:-mariadb}}" | tr '[:upper:]' '[:lower:]')
DB_VERSION="${DB_VERSION:-latest}"

# Dynamic version installer check (or missing standalone engine binary download)
ensure_engine_binary() {
    local engine="$1"
    local bin_needed=""
    case "${engine}" in
        pocketbase) bin_needed="pocketbase" ;;
        surrealdb) bin_needed="surreal" ;;
        meilisearch) bin_needed="meilisearch" ;;
        qdrant) bin_needed="qdrant" ;;
        minio) bin_needed="minio" ;;
        clickhouse) bin_needed="clickhouse" ;;
        typesense) bin_needed="typesense-server" ;;
        victoriametrics) bin_needed="victoriametrics" ;;
        ferretdb) bin_needed="ferretdb" ;;
    esac

    local installer_bin=""
    if [ -x /usr/local/bin/install-db-version.sh ]; then
        installer_bin="/usr/local/bin/install-db-version.sh"
    elif [ -x /tmp/.database-runtime/install-db-version.sh ]; then
        installer_bin="/tmp/.database-runtime/install-db-version.sh"
    elif [ -x "${SERVER_DIR}/scripts/install-db-version.sh" ]; then
        installer_bin="${SERVER_DIR}/scripts/install-db-version.sh"
    fi

    if [ -n "${bin_needed}" ]; then
        if ! command -v "${bin_needed}" >/dev/null 2>&1 && [ ! -x "${SERVER_DIR}/bin/${bin_needed}" ]; then
            log "Binary '${bin_needed}' not detected in system. Auto-installing on container..."
            if [ -n "${installer_bin}" ]; then
                "${installer_bin}" "${engine}" "${DB_VERSION:-latest}" "${SERVER_DIR}/bin" || true
            fi
        fi
    fi

    if [ -n "${installer_bin}" ] && [ "${DB_VERSION}" != "latest" ] && [ "${DB_VERSION}" != "default" ]; then
        log "Checking requested version for ${engine} (v${DB_VERSION})..."
        "${installer_bin}" "${engine}" "${DB_VERSION}" "${SERVER_DIR}/bin" || true
    fi
}

ensure_engine_binary "${PROJECT_TYPE}"

# ---------------------------------------------------------------------------
# Data Instance Manager (Non-Destructive Engine/Version Switching)
# ---------------------------------------------------------------------------
# Every engine+series gets an isolated instance folder under data/.
# - Same-series restarts reuse the identical instance (zero friction).
# - Breaking version switches NEVER touch old data: a fresh instance is
#   created and the console clearly states where previous data is preserved.
# - Explicit DATA_DIR overrides bypass this manager entirely (power users).
# ---------------------------------------------------------------------------
data_notice() { # data_notice <title> <line1> [line2] ...
    local title="$1"; shift
    local _yel="${C_YELLOW:-\033[33m}" _bold="${C_BOLD:-\033[1m}" _rst="${C_RESET:-\033[0m}"
    printf "\n${_yel}${_bold}┌─────────────────────────────────────────────────────────────┐${_rst}\n" >&2
    printf "${_yel}${_bold}│  ⚠ %-56s│${_rst}\n" "${title}" >&2
    printf "${_yel}${_bold}├─────────────────────────────────────────────────────────────┤${_rst}\n" >&2
    local l
    for l in "$@"; do
        printf "${_yel}${_bold}│${_rst}  %-58s ${_yel}${_bold}│${_rst}\n" "${l:0:57}" >&2
    done
    printf "${_yel}${_bold}└─────────────────────────────────────────────────────────────┘${_rst}\n\n" >&2
}

prepare_data_instance() {
    # Respect explicit user-provided DATA_DIR without modification
    if [ -n "${DATA_DIR:-}" ]; then
        export ACTIVE_DATA_DIR="${DATA_DIR}"
        return 0
    fi

    local root="${SERVER_DIR}/data"
    local pt="${PROJECT_TYPE}"
    local series="default"

    case "${pt}" in
        postgresql)                     series="${DB_VERSION%%.*}" ;;
        mariadb|mysql|mongodb)          series="${DB_VERSION%%.*}" ;;
        cassandra|aerospike|cockroachdb) series="${DB_VERSION%%.*}" ;;
        tidb|yugabytedb)                series="${DB_VERSION%%.*}" ;;
        redis|valkey|keydb|dragonfly)   series="${DB_VERSION%%.*}" ;;
        *)                              series="default" ;;
    esac
    [[ "${series}" =~ ^[0-9]+$ ]] || [[ "${series}" =~ ^[0-9]+\.[0-9]+$ ]] || series="default"

    local target="${root}/${pt}/${series}"
    local stamp="${target}/.potenfyr-instance"

    legacy_data_present() {
        [ -e "${root}/PG_VERSION" ] || [ -d "${root}/mysql" ] \
            || [ -f "${root}/WiredTiger" ] || [ -f "${root}/dump.rdb" ] \
            || [ -d "${root}/pb_data" ] || [ -n "$(ls -A "${root}" 2>/dev/null | grep -vE '^(\.potenfyr|'$(
                printf '%s' "postgresql|mariadb|mysql|mongodb|redis|valkey|keydb|dragonfly|memcached|cassandra|aerospike|cockroachdb|tidb|yugabytedb"
            )')$')" ]
    }

    mkdir -p "${target}"

    if [ -f "${stamp}" ]; then
        # Known instance -> reuse silently
        export ACTIVE_DATA_DIR="${target}"
        return 0
    fi

    if ! legacy_data_present; then
        printf 'engine=%s series=%s created=%s\n' "${pt}" "${series}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${stamp}"
        export ACTIVE_DATA_DIR="${target}"
        return 0
    fi

    # Legacy flat ./data content exists and was never migrated.
    case "${pt}" in
        postgresql)
            local legacy_major
            legacy_major=$(cat "${root}/PG_VERSION" 2>/dev/null | tr -d '[:space:]')
            if [ -n "${legacy_major}" ] && [ "${legacy_major}" = "${series}" ]; then
                # Non-breaking: adopt existing cluster as the official instance
                printf 'engine=%s series=%s adopted=legacy\n' "${pt}" "${series}" > "${root}/.potenfyr-instance"
                export ACTIVE_DATA_DIR="${root}"
                data_notice "DATA INSTANCE ADOPTED" \
                    "Existing PostgreSQL ${legacy_major} data reused as-is." \
                    "Instance path: ./data (future v${series} clusters share it)."
                return 0
            fi
            # Breaking major switch -> brand new isolated instance, old data untouched
            printf 'engine=%s series=%s created=%s\n' "${pt}" "${series}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${stamp}"
            export ACTIVE_DATA_DIR="${target}"
            data_notice "VERSION SWITCH - NEW DATA INSTANCE" \
                "Requested PostgreSQL v${series}; old cluster is v${legacy_major:-unknown}." \
                "A FRESH instance was created at: ./data/postgresql/${series}" \
                "Previous data PRESERVED at: ./data  (delete manually when ready)." \
                "To keep serving old data instead: set DB_VERSION=${legacy_major:-<old>}."
            return 0
            ;;
        mariadb|mysql|mongodb|cassandra|aerospike|cockroachdb)
            # Cross-major unsafe formats -> never mix; isolate new instance
            printf 'engine=%s series=%s created=%s\n' "${pt}" "${series}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${stamp}"
            export ACTIVE_DATA_DIR="${target}"
            data_notice "VERSION SWITCH - NEW DATA INSTANCE" \
                "Fresh ${pt} v${series} instance: ./data/${pt}/${series}" \
                "Legacy files in ./data are PRESERVED (not deleted)." \
                "Verify migrations, then remove ./data manually if unwanted."
            return 0
            ;;
        *)
            # Self-contained formats (redis RDB, pocketbase, minio, qdrant...) adopt safely
            printf 'engine=%s series=%s adopted=legacy\n' "${pt}" "${series}" > "${root}/.potenfyr-instance"
            export ACTIVE_DATA_DIR="${root}"
            data_notice "DATA INSTANCE ADOPTED" \
                "Existing ${pt} data in ./data continues to be used." \
                "Future instances live under: ./data/${pt}/<version>"
            return 0
            ;;
    esac
}
prepare_data_instance

# ---------------------------------------------------------------------------
# Strict Version Verification (no silent downgrades, ever)
# ---------------------------------------------------------------------------
verify_running_version() {
    local req="${DB_VERSION:-latest}"
    [ "${req}" = "latest" ] && return 0
    local bin_name="" actual=""
    case "${PROJECT_TYPE}" in
        postgresql)
            local pb; pb=$(find_pg_bin "postgres" 2>/dev/null) && actual=$("${pb}" --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1)
            ;;
        mariadb)  command -v mariadbd >/dev/null 2>&1 && actual=$(mariadbd --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1) ;;
        mysql)
            local mb="${SERVER_DIR}/opt/mysql/bin/mysqld"
            [ -x "${mb}" ] || mb="$(command -v mysqld 2>/dev/null || true)"
            [ -n "${mb}" ] && actual=$("${mb}" --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1)
            ;;
        mongodb)
            local mo="${SERVER_DIR}/bin/mongod"; [ -x "${mo}" ] || mo="$(command -v mongod 2>/dev/null || true)"
            [ -n "${mo}" ] && actual=$("${mo}" --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1)
            ;;
        redis)     command -v redis-server >/dev/null 2>&1 && actual=$(redis-server --version | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1) ;;
        valkey)    command -v valkey-server >/dev/null 2>&1 && actual=$(valkey-server --version | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1) ;;
        dragonfly) [ -x "${SERVER_DIR}/bin/dragonfly" ] && actual=$("${SERVER_DIR}/bin/dragonfly" --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1) ;;
        *) return 0 ;;
    esac

    if [ -z "${actual}" ]; then
        warn "Could not verify installed ${PROJECT_TYPE} version against requested '${req}'."
        return 0
    fi

    export EFFECTIVE_DB_VERSION="${actual}"
    local req_major="${req%%.*}" act_major="${actual%%.*}"
    if [ "${req_major}" != "${act_major}" ]; then
        if [ "${STRICT_VERSION:-1}" = "1" ]; then
            error "Version contract violated: requested ${PROJECT_TYPE} '${req}' but available binary is '${actual}'."
            error "The server refuses to silently run a different version than requested."
            error "Options: fix network/installer (logs/installer.log), set STRICT_VERSION=0 to allow fallback,"
            error "or adjust DB_VERSION to match reality."
            fail "Strict version verification failed (${req} != ${actual})."
        else
            warn "Running ${PROJECT_TYPE} ${actual} although '${req}' was requested (STRICT_VERSION=0)."
        fi
    else
        log "Verified engine version: ${actual} (requested ${req})"
    fi
}
verify_running_version

# --- Connection Summary Helper (Strictly Masked - No Cleartext Passwords in Logs)
print_connection_guide() {
    printf "\n"
    printf "${C_GREEN}${C_BOLD}┌─────────────────────────────────────────────────────────────┐${C_RESET}\n"
    printf "${C_GREEN}${C_BOLD}│${C_RESET}  ${C_GREEN}${C_BOLD}✓  DATABASE READY - SECURE CONNECTION DETAILS${C_RESET}             ${C_GREEN}${C_BOLD}│${C_RESET}\n"
    printf "${C_GREEN}${C_BOLD}├─────────────────────────────────────────────────────────────┤${C_RESET}\n"
    printf "${C_GREEN}${C_BOLD}│${C_RESET}  ${C_BOLD}%-16s${C_RESET} : %-38s ${C_GREEN}${C_BOLD}│${C_RESET}\n" "Engine" "${PROJECT_TYPE^^} (v${DB_VERSION})"
    printf "${C_GREEN}${C_BOLD}│${C_RESET}  ${C_BOLD}%-16s${C_RESET} : %-38s ${C_GREEN}${C_BOLD}│${C_RESET}\n" "Host (Internal)" "${INTERNAL_IP:-127.0.0.1}"
    printf "${C_GREEN}${C_BOLD}│${C_RESET}  ${C_BOLD}%-16s${C_RESET} : %-38s ${C_GREEN}${C_BOLD}│${C_RESET}\n" "Port" "${SERVER_PORT:-3306}"
    printf "${C_GREEN}${C_BOLD}│${C_RESET}  ${C_BOLD}%-16s${C_RESET} : %-38s ${C_GREEN}${C_BOLD}│${C_RESET}\n" "Database" "${DB_NAME:-database}"
    printf "${C_GREEN}${C_BOLD}│${C_RESET}  ${C_BOLD}%-16s${C_RESET} : %-38s ${C_GREEN}${C_BOLD}│${C_RESET}\n" "Username" "${DB_USER:-dbuser}"
    printf "${C_GREEN}${C_BOLD}│${C_RESET}  ${C_BOLD}%-16s${C_RESET} : %-38s ${C_GREEN}${C_BOLD}│${C_RESET}\n" "User Password" "•••••••••••• [Protected]"
    printf "${C_GREEN}${C_BOLD}│${C_RESET}  ${C_BOLD}%-16s${C_RESET} : %-38s ${C_GREEN}${C_BOLD}│${C_RESET}\n" "Root Password" "•••••••••••• [Protected]"
    printf "${C_GREEN}${C_BOLD}│${C_RESET}  ${C_BOLD}%-16s${C_RESET} : %-38s ${C_GREEN}${C_BOLD}│${C_RESET}\n" "Credentials" "$([ -f "${SERVER_DIR}/.env" ] && echo "Saved in .env & Startup Environment" || echo "Active in Startup Environment")"
    printf "${C_GREEN}${C_BOLD}└─────────────────────────────────────────────────────────────┘${C_RESET}\n"

    printf "\n ${C_BOLD}${C_YELLOW}Quick Connection Examples (Zero-Leak Security):${C_RESET}\n"
    case "${PROJECT_TYPE}" in
        mariadb|mysql)
            printf "   ${C_BOLD}CLI (Pre-Auth) :${C_RESET} ${C_CYAN}db-cli${C_RESET}\n"
            printf "   ${C_BOLD}CLI (Manual)   :${C_RESET} ${C_CYAN}mysql -h %s -P %s -u %s -p %s${C_RESET}\n" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-3306}" "${DB_USER:-root}" "${DB_NAME:-database}"
            printf "   ${C_BOLD}URI            :${C_RESET} ${C_CYAN}mysql://%s:<PASSWORD_IN_.ENV>@%s:%s/%s${C_RESET}\n" "${DB_USER:-root}" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-3306}" "${DB_NAME:-database}"
            ;;
        postgresql|postgres)
            printf "   ${C_BOLD}CLI (Pre-Auth) :${C_RESET} ${C_CYAN}db-cli${C_RESET}\n"
            printf "   ${C_BOLD}CLI (Manual)   :${C_RESET} ${C_CYAN}psql -h %s -p %s -U %s -d %s${C_RESET}\n" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-5432}" "${DB_USER:-postgres}" "${DB_NAME:-postgres}"
            printf "   ${C_BOLD}URI            :${C_RESET} ${C_CYAN}postgresql://%s:<PASSWORD_IN_.ENV>@%s:%s/%s?sslmode=disable${C_RESET}\n" "${DB_USER:-postgres}" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-5432}" "${DB_NAME:-postgres}"
            ;;
        redis|valkey|keydb|dragonfly)
            printf "   ${C_BOLD}CLI (Pre-Auth) :${C_RESET} ${C_CYAN}db-cli${C_RESET}\n"
            printf "   ${C_BOLD}CLI (Manual)   :${C_RESET} ${C_CYAN}redis-cli -h %s -p %s -a \"<PASSWORD_IN_.ENV>\"${C_RESET}\n" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-6379}"
            printf "   ${C_BOLD}URI            :${C_RESET} ${C_CYAN}redis://:<PASSWORD_IN_.ENV>@%s:%s${C_RESET}\n" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-6379}"
            ;;
        memcached)
            printf "   ${C_BOLD}CLI            :${C_RESET} ${C_CYAN}telnet %s %s${C_RESET}\n" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-11211}"
            printf "   ${C_BOLD}URI            :${C_RESET} ${C_CYAN}memcached://%s:%s${C_RESET}\n" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-11211}"
            ;;
        mongodb|ferretdb)
            printf "   ${C_BOLD}CLI (Pre-Auth) :${C_RESET} ${C_CYAN}db-cli${C_RESET}\n"
            printf "   ${C_BOLD}URI            :${C_RESET} ${C_CYAN}mongodb://%s:<PASSWORD_IN_.ENV>@%s:%s/%s?authSource=admin${C_RESET}\n" "${DB_USER:-root}" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-27017}" "${DB_NAME:-database}"
            ;;
        surrealdb)
            printf "   ${C_BOLD}CLI (Pre-Auth) :${C_RESET} ${C_CYAN}db-cli${C_RESET}\n"
            printf "   ${C_BOLD}HTTP           :${C_RESET} ${C_CYAN}http://%s:%s/rpc${C_RESET}\n" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-8000}"
            ;;
        meilisearch)
            printf "   ${C_BOLD}HTTP Endpoint  :${C_RESET} ${C_CYAN}http://%s:%s${C_RESET} (Bearer token in .env)\n" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-7700}"
            ;;
        typesense)
            printf "   ${C_BOLD}HTTP Endpoint  :${C_RESET} ${C_CYAN}http://%s:%s${C_RESET} (X-TYPESENSE-API-KEY in .env)\n" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-8108}"
            ;;
        pocketbase)
            printf "   ${C_BOLD}Admin UI       :${C_RESET} ${C_CYAN}http://%s:%s/_/${C_RESET}\n" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-8090}"
            ;;
        minio)
            printf "   ${C_BOLD}S3 API         :${C_RESET} ${C_CYAN}http://%s:%s${C_RESET}\n" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-9000}"
            if [ -n "${CONSOLE_PORT:-}" ]; then
                printf "   ${C_BOLD}Console        :${C_RESET} ${C_CYAN}http://%s:%s${C_RESET}\n" "${INTERNAL_IP:-127.0.0.1}" "${CONSOLE_PORT}"
            else
                printf "   ${C_BOLD}Console        :${C_RESET} loopback-only (set CONSOLE_PORT to expose)\n"
            fi
            ;;
        qdrant)
            printf "   ${C_BOLD}REST API       :${C_RESET} ${C_CYAN}http://%s:%s${C_RESET}\n" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-6333}"
            printf "   ${C_BOLD}Web UI         :${C_RESET} ${C_CYAN}http://%s:%s/dashboard${C_RESET}\n" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-6333}"
            ;;
    esac
    printf "\n"
}

# --- Engine Dispatcher ------------------------------------------------------
case "${PROJECT_TYPE}" in
    mariadb|mysql)
        init_mariadb_mysql
        print_connection_guide
        start_mariadb_mysql
        ;;
    postgresql|postgres)
        init_postgres
        print_connection_guide
        start_postgres
        ;;
    redis|valkey|keydb|dragonfly|memcached)
        init_redis_family
        print_connection_guide
        start_redis_family
        ;;
    mongodb|ferretdb)
        init_mongo_family
        print_connection_guide
        start_mongo_family
        ;;
    surrealdb|rethinkdb)
        init_surreal_family
        print_connection_guide
        start_surreal_family
        ;;
    cockroachdb|cockroach|tidb|dolt|sqld|libsql|etcd|nats|immudb|dgraph|arangodb|orientdb|ravendb|cassandra|aerospike|yugabytedb|yugabyte)
        init_extra_engine
        print_connection_guide
        start_extra_engine
        ;;
    meilisearch|typesense|qdrant|elasticsearch|opensearch|solr|manticoresearch|manticore|milvus|weaviate|quickwit)
        init_search_family
        print_connection_guide
        start_search_family
        ;;
    pocketbase|minio|influxdb|clickhouse|victoriametrics|couchdb|neo4j|questdb|seaweedfs|weed|garage)
        init_storage_family
        print_connection_guide
        start_storage_family
        ;;
    custom)
        print_connection_guide
        mkdir -p "${SERVER_DIR}/bin" "${SERVER_DIR}/data" "${SERVER_DIR}/logs" "${SERVER_DIR}/config"

        if [ -n "${CUSTOM_PRE_RUN_SCRIPT:-}" ]; then
            log "Executing pre-run custom script..."
            eval "${CUSTOM_PRE_RUN_SCRIPT}"
        fi

        if [ -n "${CUSTOM_DOWNLOAD_URL:-}" ] && [ ! -f "${SERVER_DIR}/bin/${CUSTOM_BINARY_NAME:-app}" ]; then
            log "Downloading custom binary from ${CUSTOM_DOWNLOAD_URL}..."
            "${SERVER_DIR}/scripts/install-db-version.sh" "custom" "${CUSTOM_DOWNLOAD_URL}" "${SERVER_DIR}/bin" || true
        fi

        run_cmd="${CUSTOM_COMMAND:-${CUSTOM_STARTUP_CMD:-}}"
        if [ -z "${run_cmd}" ]; then
            if [ -n "${CUSTOM_BINARY_NAME:-}" ] && [ -x "${SERVER_DIR}/bin/${CUSTOM_BINARY_NAME}" ]; then
                run_cmd="${SERVER_DIR}/bin/${CUSTOM_BINARY_NAME} ${CUSTOM_ARGS:-}"
            elif [ -x "${SERVER_DIR}/bin/server" ]; then
                run_cmd="${SERVER_DIR}/bin/server ${CUSTOM_ARGS:-}"
            elif [ -x "${SERVER_DIR}/server" ]; then
                run_cmd="${SERVER_DIR}/server ${CUSTOM_ARGS:-}"
            fi
        fi

        if [ -n "${run_cmd}" ]; then
            log "Starting Custom Engine: ${run_cmd}"
            exec ${run_cmd}
        else
            fail "CUSTOM_COMMAND or CUSTOM_BINARY_NAME is empty. Provide a valid command or binary to run."
        fi
        ;;
    *)
        fail "Unsupported database engine: '${PROJECT_TYPE}'"
        ;;
esac
