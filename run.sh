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
fail()  { printf "${C_CYAN}${C_BOLD}container@${PANEL_NAME}~${C_RESET} ${C_RED}${C_BOLD}[error]${C_RESET} %s\n" "$*"; exit 1; }

if [ -d /home/container ]; then
    cd /home/container 2>/dev/null || true
elif [ -d /mnt/server ]; then
    cd /mnt/server 2>/dev/null || true
else
    cd "$(pwd)" 2>/dev/null || true
fi
SERVER_DIR="$(pwd)"

export PATH="/usr/lib/postgresql/16/bin:/usr/lib/postgresql/15/bin:/usr/lib/postgresql/14/bin:${SERVER_DIR}/bin:/tmp/.database-runtime:/usr/local/bin:${PATH}"

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

# Source all modular initialization handlers & performance tuning safely from image or isolated runtime
for script in /usr/local/bin/db-init-*.sh /usr/local/bin/performance-*.sh /tmp/.database-runtime/db-init-*.sh /tmp/.database-runtime/performance-*.sh "${SERVER_DIR}/scripts"/db-init-*.sh; do
    [ -f "${script}" ] && source "${script}" 2>/dev/null || true
done

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

# --- Connection Summary Helper ----------------------------------------------
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
    printf "${C_GREEN}${C_BOLD}│${C_RESET}  ${C_BOLD}%-16s${C_RESET} : %-38s ${C_GREEN}${C_BOLD}│${C_RESET}\n" "User Password" "${DB_PASSWORD:-[none]}"
    printf "${C_GREEN}${C_BOLD}│${C_RESET}  ${C_BOLD}%-16s${C_RESET} : %-38s ${C_GREEN}${C_BOLD}│${C_RESET}\n" "Root Password" "${DB_ROOT_PASSWORD:-[none]}"
    printf "${C_GREEN}${C_BOLD}│${C_RESET}  ${C_BOLD}%-16s${C_RESET} : %-38s ${C_GREEN}${C_BOLD}│${C_RESET}\n" "Environment" "Saved in .env & credentials.txt"
    printf "${C_GREEN}${C_BOLD}└─────────────────────────────────────────────────────────────┘${C_RESET}\n"

    printf "\n ${C_BOLD}${C_YELLOW}Quick Connection Examples:${C_RESET}\n"
    case "${PROJECT_TYPE}" in
        mariadb|mysql)
            printf "   ${C_BOLD}CLI :${C_RESET} ${C_CYAN}mysql -h %s -P %s -u %s -p'%s' %s${C_RESET}\n" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-3306}" "${DB_USER:-root}" "${DB_PASSWORD:-${DB_ROOT_PASSWORD:-}}" "${DB_NAME:-database}"
            printf "   ${C_BOLD}URI :${C_RESET} ${C_CYAN}mysql://%s:%s@%s:%s/%s${C_RESET}\n" "${DB_USER:-root}" "${DB_PASSWORD:-${DB_ROOT_PASSWORD:-}}" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-3306}" "${DB_NAME:-database}"
            ;;
        postgresql|postgres)
            printf "   ${C_BOLD}CLI :${C_RESET} ${C_CYAN}psql \"postgresql://%s:%s@%s:%s/%s\"${C_RESET}\n" "${DB_USER:-postgres}" "${DB_PASSWORD:-${DB_ROOT_PASSWORD:-}}" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-5432}" "${DB_NAME:-postgres}"
            printf "   ${C_BOLD}URI :${C_RESET} ${C_CYAN}postgresql://%s:%s@%s:%s/%s?sslmode=disable${C_RESET}\n" "${DB_USER:-postgres}" "${DB_PASSWORD:-${DB_ROOT_PASSWORD:-}}" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-5432}" "${DB_NAME:-postgres}"
            ;;
        redis|valkey|keydb|dragonfly)
            printf "   ${C_BOLD}CLI :${C_RESET} ${C_CYAN}redis-cli -h %s -p %s -a '%s'${C_RESET}\n" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-6379}" "${DB_PASSWORD:-${DB_ROOT_PASSWORD:-}}"
            printf "   ${C_BOLD}URI :${C_RESET} ${C_CYAN}redis://:%s@%s:%s${C_RESET}\n" "${DB_PASSWORD:-${DB_ROOT_PASSWORD:-}}" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-6379}"
            ;;
        memcached)
            printf "   ${C_BOLD}CLI :${C_RESET} ${C_CYAN}telnet %s %s${C_RESET}\n" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-11211}"
            printf "   ${C_BOLD}URI :${C_RESET} ${C_CYAN}memcached://%s:%s${C_RESET}\n" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-11211}"
            ;;
        mongodb|ferretdb)
            printf "   ${C_BOLD}CLI :${C_RESET} ${C_CYAN}mongosh \"mongodb://%s:%s@%s:%s/%s?authSource=admin\"${C_RESET}\n" "${DB_USER:-root}" "${DB_PASSWORD:-${DB_ROOT_PASSWORD:-}}" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-27017}" "${DB_NAME:-database}"
            ;;
        surrealdb)
            printf "   ${C_BOLD}CLI :${C_RESET} ${C_CYAN}surreal sql --endpoint http://%s:%s --user %s --pass '%s'${C_RESET}\n" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-8000}" "${DB_USER:-root}" "${DB_PASSWORD:-${DB_ROOT_PASSWORD:-}}"
            printf "   ${C_BOLD}HTTP:${C_RESET} ${C_CYAN}http://%s:%s/rpc${C_RESET}\n" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-8000}"
            ;;
        meilisearch)
            printf "   ${C_BOLD}HTTP:${C_RESET} ${C_CYAN}http://%s:%s${C_RESET} (Bearer: %s)\n" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-7700}" "${DB_ROOT_PASSWORD:-${DB_PASSWORD:-}}"
            ;;
        typesense)
            printf "   ${C_BOLD}HTTP:${C_RESET} ${C_CYAN}http://%s:%s${C_RESET} (X-TYPESENSE-API-KEY: %s)\n" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-8108}" "${DB_ROOT_PASSWORD:-${DB_PASSWORD:-}}"
            ;;
        pocketbase)
            printf "   ${C_BOLD}Admin UI:${C_RESET} ${C_CYAN}http://%s:%s/_/${C_RESET}\n" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-8090}"
            ;;
        minio)
            printf "   ${C_BOLD}S3 API  :${C_RESET} ${C_CYAN}http://%s:%s${C_RESET}\n" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-9000}"
            printf "   ${C_BOLD}Console :${C_RESET} ${C_CYAN}http://%s:%s${C_RESET}\n" "${INTERNAL_IP:-127.0.0.1}" "${CONSOLE_PORT:-$((SERVER_PORT + 1))}"
            ;;
        qdrant)
            printf "   ${C_BOLD}REST API:${C_RESET} ${C_CYAN}http://%s:%s${C_RESET}\n" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-6333}"
            printf "   ${C_BOLD}Web UI  :${C_RESET} ${C_CYAN}http://%s:%s/dashboard${C_RESET}\n" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-6333}"
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
    meilisearch|typesense|qdrant)
        init_search_family
        print_connection_guide
        start_search_family
        ;;
    pocketbase|minio|influxdb|clickhouse|victoriametrics|couchdb|neo4j)
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

        local run_cmd="${CUSTOM_COMMAND:-${CUSTOM_STARTUP_CMD:-}}"
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
