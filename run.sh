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
export C_RESET C_BOLD C_CYAN C_GREEN C_YELLOW C_RED C_MAGENTA C_DIM

# -----------------------------------------------------------------------------
# Central Diagnostics Library (unified logging, traces, crash safety)
# -----------------------------------------------------------------------------
PF_COMPONENT="launcher"
PF_FAIL_SLEEP=5
_LIB_CANDIDATES=(
    "$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/scripts/lib-diagnostics.sh"
    "/usr/local/bin/lib-diagnostics.sh"
    "/tmp/.database-runtime/lib-diagnostics.sh"
    "${SERVER_DIR:-}/scripts/lib-diagnostics.sh"
    "./lib-diagnostics.sh"
)
_pf_lib_loaded=0
for _lib in "${_LIB_CANDIDATES[@]}"; do
    if [ -f "${_lib}" ]; then
        # shellcheck source=/dev/null
        source "${_lib}" && _pf_lib_loaded=1 && break
    fi
done
unset _lib _LIB_CANDIDATES

if [ "${_pf_lib_loaded}" != "1" ]; then
    # Absolute last-resort fallback so the launcher is never speechless
    log()   { printf '[launcher] %s\n' "$*"; }
    ok()    { printf '[launcher][ok] %s\n' "$*"; }
    warn()  { printf '[launcher][warn] %s\n' "$*" >&2; }
    error() { printf '[launcher][error] %s\n' "$*" >&2; }
    fail()  { printf '[launcher][FATAL] %s\n' "$*" >&2; sleep 8; exit 1; }
fi

PANEL_NAME="${PANEL_NAME:-${P_SERVER_UUID:+pterodactyl}}"
PANEL_NAME="${PANEL_NAME:-panel}"
export PANEL_NAME

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

# Host kernel tunables (overcommit, somaxconn, THP) - best-effort, root-aware
if command -v apply_host_tunables >/dev/null 2>&1; then
    apply_host_tunables
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

    # ALWAYS honor DB_VERSION - including 'latest'/'default'. Previously these
    # keywords SKIPPED provisioning entirely, silently serving the distro's
    # ancient pre-baked binary (e.g. Redis 6.0.16) instead of the newest
    # upstream release. install-db-version.sh resolves latest dynamically and
    # is idempotent, so existing correct installs cost one cheap feed lookup.
    if [ -n "${installer_bin}" ]; then
        log "Resolving ${engine} version request (v${DB_VERSION:-latest})..."
        if ! "${installer_bin}" "${engine}" "${DB_VERSION:-latest}" "${SERVER_DIR}/bin"; then
            warn "Version provisioning failed for ${engine} - falling back to best-available binaries."
        fi
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
        export DATA_DIR="${DATA_DIR}"; export ACTIVE_DATA_DIR="${ACTIVE_DATA_DIR:-${DATA_DIR}}"
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

    # Legacy = anything at data/ root that is NOT a hidden marker or a known
    # engine instance folder. Classic flat-format markers count too.
    legacy_data_present() {
        local e
        while IFS= read -r e; do
            [ -z "${e}" ] && continue
            case "${e}" in
                .*|postgresql|mariadb|mysql|mongodb|redis|valkey|keydb|dragonfly|memcached|\
cassandra|aerospike|cockroachdb|tidb|yugabytedb|meilisearch|qdrant|typesense|\
pocketbase|minio|influxdb|clickhouse|victoriametrics|surrealdb|neo4j|dgraph|\
garage|seaweedfs|questdb|elasticsearch|opensearch|solr|manticoresearch|milvus|\
weaviate|quickwit|arangodb|orientdb|ravendb|etcd|nats|immudb|dolt|sqld|\
ferretdb|rethinkdb|custom)
                    continue ;;
                *)
                    return 0 ;;   # unknown entry => genuine legacy content
            esac
        done < <(ls -A "${root}" 2>/dev/null)
        [ -e "${root}/PG_VERSION" ] || [ -d "${root}/mysql" ] \
            || [ -f "${root}/WiredTiger" ] || [ -f "${root}/dump.rdb" ] \
            || [ -d "${root}/pb_data" ] && return 0
        return 1
    }

    mkdir -p "${target}"

    if [ -f "${stamp}" ]; then
        # Known instance -> reuse silently
        export DATA_DIR="${target}"; export ACTIVE_DATA_DIR="${target}"
        return 0
    fi

    if ! legacy_data_present; then
        printf 'engine=%s series=%s created=%s\n' "${pt}" "${series}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${stamp}"
        export DATA_DIR="${target}"; export ACTIVE_DATA_DIR="${target}"
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
                export DATA_DIR="${root}"; export ACTIVE_DATA_DIR="${root}"
                data_notice "DATA INSTANCE ADOPTED" \
                    "Existing PostgreSQL ${legacy_major} data reused as-is." \
                    "Instance path: ./data (future v${series} clusters share it)."
                return 0
            fi
            # Breaking major switch -> brand new isolated instance, old data untouched
            printf 'engine=%s series=%s created=%s\n' "${pt}" "${series}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${stamp}"
            export DATA_DIR="${target}"; export ACTIVE_DATA_DIR="${target}"
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
            export DATA_DIR="${target}"; export ACTIVE_DATA_DIR="${target}"
            data_notice "VERSION SWITCH - NEW DATA INSTANCE" \
                "Fresh ${pt} v${series} instance: ./data/${pt}/${series}" \
                "Legacy files in ./data are PRESERVED (not deleted)." \
                "Verify migrations, then remove ./data manually if unwanted."
            return 0
            ;;
        *)
            # Self-contained formats (redis RDB, pocketbase, minio, qdrant...) adopt safely
            printf 'engine=%s series=%s adopted=legacy\n' "${pt}" "${series}" > "${root}/.potenfyr-instance"
            export DATA_DIR="${root}"; export ACTIVE_DATA_DIR="${root}"
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
    [ "${req}" = "stable" ] && return 0
    local bin_name="" actual=""
    case "${PROJECT_TYPE}" in
        postgresql)
            local pb; pb=$(find_pg_bin "postgres" 2>/dev/null) && actual=$("${pb}" --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1)
            ;;
        mariadb)
            local mb="${SERVER_DIR}/opt/mariadb/bin/mariadbd"
            [ -x "${mb}" ] || mb="$(command -v mariadbd 2>/dev/null || true)"
            [ -n "${mb}" ] && actual=$("${mb}" --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1)
            ;;
        mysql)
            mb="${SERVER_DIR}/opt/mysql/bin/mysqld"
            [ -x "${mb}" ] || mb="$(command -v mysqld 2>/dev/null || true)"
            [ -n "${mb}" ] && actual=$("${mb}" --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1)
            ;;
        mongodb)
            local mo="${SERVER_DIR}/bin/mongod"; [ -x "${mo}" ] || mo="$(command -v mongod 2>/dev/null || true)"
            [ -n "${mo}" ] && actual=$("${mo}" --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1)
            ;;
        redis)     command -v redis-server >/dev/null 2>&1 && actual=$(redis-server --version | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1) ;;
        valkey)
            local vk="${SERVER_DIR}/bin/valkey-server"; [ -x "${vk}" ] || vk="$(command -v valkey-server 2>/dev/null || true)"
            [ -n "${vk}" ] && actual=$("${vk}" --version | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1)
            ;;
        dragonfly) [ -x "${SERVER_DIR}/bin/dragonfly" ] && actual=$("${SERVER_DIR}/bin/dragonfly" --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1) ;;
        *) return 0 ;;
    esac

    if [ -z "${actual}" ]; then
        warn "Could not verify installed ${PROJECT_TYPE} version against requested '${req}'."
        return 0
    fi

    export EFFECTIVE_DB_VERSION="${actual}"
    local req_major="${req%%.*}" act_major="${actual%%.*}"
    # Installer runs as a subshell: substitution decisions reach us via marker
    # files, never environment variables.
    if [ -f "${SERVER_DIR}/bin/.versions/${PROJECT_TYPE}-system-fallback" ]; then
        warn "Running container-provided ${PROJECT_TYPE} ${actual}: the pinned version '${req}' could not be provisioned in this environment (see logs/installer.log)."
        warn "Exact-version service resumes automatically once provisioning becomes possible (build tools, root, or reachable upstream)."
        return 0
    fi
    if [ "${PROJECT_TYPE}" = "mysql" ] \
       && [ "${CDN_FALLBACK_SYSTEM:-0}" = "1" ] \
       && [ -f "${SERVER_DIR}/bin/.versions/mysql-cdn-fallback" ]; then
        warn "Running container-provided ${PROJECT_TYPE} ${actual} because cdn.mysql.com was unreachable (CDN_FALLBACK_SYSTEM=1)."
        warn "Requested '${req}' will be honored automatically once Oracle's CDN is reachable again."
        return 0
    fi
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

# ---------------------------------------------------------------------------
# Central Process Supervisor & Console Stop Listener
# ---------------------------------------------------------------------------
DAEMON_PID=""
STOP_HANDLER=""
STDIN_READER_PID=""
_SHUTDOWN_IN_PROGRESS=0

_do_graceful_shutdown() {
    local sig="${1:-SIGTERM}"
    if [ "${_SHUTDOWN_IN_PROGRESS}" = "1" ]; then
        return 0
    fi
    _SHUTDOWN_IN_PROGRESS=1

    printf "\n"
    log "Shutdown event (${sig}) received. Gracefully stopping ${PROJECT_TYPE^^}..."

    # Terminate background stdin listener immediately
    if [ -n "${STDIN_READER_PID:-}" ] && kill -0 "${STDIN_READER_PID}" 2>/dev/null; then
        kill -9 "${STDIN_READER_PID}" 2>/dev/null || true
        wait "${STDIN_READER_PID}" 2>/dev/null || true
    fi

    # Invoke engine-specific stop hook if provided
    if [ -n "${STOP_HANDLER:-}" ] && declare -f "${STOP_HANDLER}" >/dev/null 2>&1; then
        "${STOP_HANDLER}" "${DAEMON_PID}" || true
    elif [ -n "${DAEMON_PID:-}" ] && kill -0 "${DAEMON_PID}" 2>/dev/null; then
        kill -TERM "${DAEMON_PID}" 2>/dev/null || true
    fi

    # Grace period waiting for daemon to exit cleanly (up to 15 seconds)
    local wait_count=0
    local max_wait=15
    if [ -n "${DAEMON_PID:-}" ]; then
        while kill -0 "${DAEMON_PID}" 2>/dev/null && [ "${wait_count}" -lt "${max_wait}" ]; do
            sleep 1
            wait_count=$((wait_count + 1))
        done

        if kill -0 "${DAEMON_PID}" 2>/dev/null; then
            warn "${PROJECT_TYPE^^} (PID ${DAEMON_PID}) did not terminate within ${max_wait}s. Forcing shutdown..."
            kill -9 "${DAEMON_PID}" 2>/dev/null || true
            wait "${DAEMON_PID}" 2>/dev/null || true
        fi
    fi

    ok "${PROJECT_TYPE^^} server stopped cleanly."
}

_on_trap_signal() {
    local sig="$1"
    _do_graceful_shutdown "${sig}"
    exit 0
}

supervise_daemon() {
    local daemon_pid="$1"
    local stop_handler="${2:-}"
    DAEMON_PID="${daemon_pid}"
    STOP_HANDLER="${stop_handler}"
    export DAEMON_PID STOP_HANDLER

    # Trap termination signals for graceful container lifecycle
    trap '_on_trap_signal SIGTERM' SIGTERM
    trap '_on_trap_signal SIGINT' SIGINT
    trap '_on_trap_signal SIGHUP' SIGHUP
    trap '_on_trap_signal SIGQUIT' SIGQUIT

    # Subshell-safe self PID: $$ is the PARENT's pid inside ( ) subshells,
    # which would make the console-stop handler kill the wrong process.
    # BASH_SUBSHELL > 0 means we are a subshell -> resolve via /proc/self.
    local sup_pid=$$
    if [ "${BASH_SUBSHELL:-0}" -gt 0 ] && [ -r /proc/self/stat ]; then
        sup_pid=$(cut -d' ' -f1 /proc/self/stat 2>/dev/null || printf '%s' "$$")
    fi

    # Start background stdin listener to handle panel console commands and control characters
    if [ -t 0 ] || [ -p /dev/stdin ] || [ -e /dev/stdin ]; then
        (
            while IFS= read -r line || [ -n "${line}" ]; do
                clean_cmd=$(printf '%s' "${line}" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
                case "${clean_cmd}" in
                    $'\x03'|$'\x04'|^C|^c|^D|^d|stop|STOP|exit|EXIT|quit|QUIT|shutdown|SHUTDOWN|restart|RESTART|"stop server"|"restart server"|"end")
                        log "Console stop command received ('${clean_cmd}'). Initiating shutdown..."
                        kill -TERM "${sup_pid}" 2>/dev/null || true
                        break
                        ;;
                    "")
                        ;;
                    *)
                        log "Console command '${clean_cmd}' received. (To stop the database, use 'stop' or the Panel Stop button)."
                        ;;
                esac
            done
        ) &
        STDIN_READER_PID=$!
    fi

    # Wait for the managed daemon process
    local exit_code=0
    wait "${daemon_pid}" 2>/dev/null
    exit_code=$?

    if [ "${_SHUTDOWN_IN_PROGRESS}" = "0" ]; then
        if [ "${exit_code}" -gt 128 ]; then
            _do_graceful_shutdown "SIGNAL"
            exit_code=0
        elif [ "${exit_code}" -ne 0 ]; then
            warn "${PROJECT_TYPE^^} daemon exited with code ${exit_code}."
        fi
    fi

    # Clean up stdin reader subshell
    if [ -n "${STDIN_READER_PID:-}" ] && kill -0 "${STDIN_READER_PID}" 2>/dev/null; then
        kill -9 "${STDIN_READER_PID}" 2>/dev/null || true
        wait "${STDIN_READER_PID}" 2>/dev/null || true
    fi

    exit "${exit_code}"
}
export -f supervise_daemon _do_graceful_shutdown _on_trap_signal

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
            ${run_cmd} < /dev/null &
            daemon_pid=$!
            supervise_daemon "${daemon_pid}"
        else
            fail "CUSTOM_COMMAND or CUSTOM_BINARY_NAME is empty. Provide a valid command or binary to run."
        fi
        ;;
    *)
        fail "Unsupported database engine: '${PROJECT_TYPE}'"
        ;;
esac
