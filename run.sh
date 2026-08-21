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

export PATH="${SERVER_DIR}/bin:${SERVER_DIR}/scripts:/usr/local/bin:${PATH}"

# Source all modular initialization handlers & performance tuning safely
for script in "${SERVER_DIR}/scripts"/db-init-*.sh "${SERVER_DIR}/scripts"/performance-*.sh /usr/local/bin/db-init-*.sh /usr/local/bin/performance-*.sh; do
    [ -f "${script}" ] && source "${script}" 2>/dev/null || true
done

PROJECT_TYPE=$(echo "${DB_TYPE:-${DATABASE_TYPE:-mariadb}}" | tr '[:upper:]' '[:lower:]')
DB_VERSION="${DB_VERSION:-latest}"

# Dynamic version installer check (if specific version requested and not locally cached)
if [ -x "${SERVER_DIR}/scripts/install-db-version.sh" ] && [ "${DB_VERSION}" != "latest" ] && [ "${DB_VERSION}" != "default" ]; then
    log "Checking version binary for ${PROJECT_TYPE} (v${DB_VERSION})..."
    "${SERVER_DIR}/scripts/install-db-version.sh" "${PROJECT_TYPE}" "${DB_VERSION}" "${SERVER_DIR}/bin" >/dev/null 2>&1 || true
fi

# --- Connection Summary Helper ----------------------------------------------
print_connection_guide() {
    printf "\n${C_BOLD}${C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n"
    printf " ${C_BOLD}${C_GREEN}✓  DATABASE READY - SECURE CONNECTION DETAILS${C_RESET}\n"
    printf "${C_BOLD}${C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n"
    printf " ${C_BOLD}%-16s:${C_RESET} %s (v%s)\n" "Engine" "${PROJECT_TYPE^^}" "${DB_VERSION}"
    printf " ${C_BOLD}%-16s:${C_RESET} %s\n" "Host (Internal)" "${INTERNAL_IP:-127.0.0.1}"
    printf " ${C_BOLD}%-16s:${C_RESET} %s\n" "Port" "${SERVER_PORT:-3306}"
    printf " ${C_BOLD}%-16s:${C_RESET} %s\n" "Database" "${DB_NAME:-database}"
    printf " ${C_BOLD}%-16s:${C_RESET} %s\n" "Username" "${DB_USER:-dbuser}"
    printf " ${C_BOLD}%-16s:${C_RESET} %s\n" "User Password" "${DB_PASSWORD:-[none]}"
    printf " ${C_BOLD}%-16s:${C_RESET} %s\n" "Root Password" "${DB_ROOT_PASSWORD:-[none]}"

    printf "\n ${C_BOLD}${C_YELLOW}Quick Connection Examples:${C_RESET}\n"
    case "${PROJECT_TYPE}" in
        mariadb|mysql)
            printf "   CLI : ${C_CYAN}mysql -h %s -P %s -u %s -p'%s' %s${C_RESET}\n" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-3306}" "${DB_USER:-root}" "${DB_PASSWORD:-${DB_ROOT_PASSWORD:-}}" "${DB_NAME:-database}"
            printf "   URI : ${C_CYAN}mysql://%s:%s@%s:%s/%s${C_RESET}\n" "${DB_USER:-root}" "${DB_PASSWORD:-${DB_ROOT_PASSWORD:-}}" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-3306}" "${DB_NAME:-database}"
            ;;
        postgresql|postgres)
            printf "   CLI : ${C_CYAN}psql \"postgresql://%s:%s@%s:%s/%s\"${C_RESET}\n" "${DB_USER:-postgres}" "${DB_PASSWORD:-${DB_ROOT_PASSWORD:-}}" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-5432}" "${DB_NAME:-postgres}"
            printf "   URI : ${C_CYAN}postgresql://%s:%s@%s:%s/%s?sslmode=disable${C_RESET}\n" "${DB_USER:-postgres}" "${DB_PASSWORD:-${DB_ROOT_PASSWORD:-}}" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-5432}" "${DB_NAME:-postgres}"
            ;;
        redis|valkey|keydb|dragonfly)
            printf "   CLI : ${C_CYAN}redis-cli -h %s -p %s -a '%s'${C_RESET}\n" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-6379}" "${DB_PASSWORD:-${DB_ROOT_PASSWORD:-}}"
            printf "   URI : ${C_CYAN}redis://:%s@%s:%s${C_RESET}\n" "${DB_PASSWORD:-${DB_ROOT_PASSWORD:-}}" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-6379}"
            ;;
        mongodb|ferretdb)
            printf "   CLI : ${C_CYAN}mongosh \"mongodb://%s:%s@%s:%s/%s?authSource=admin\"${C_RESET}\n" "${DB_USER:-root}" "${DB_PASSWORD:-${DB_ROOT_PASSWORD:-}}" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-27017}" "${DB_NAME:-database}"
            ;;
        surrealdb)
            printf "   CLI : ${C_CYAN}surreal sql --endpoint http://%s:%s --user %s --pass '%s'${C_RESET}\n" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-8000}" "${DB_USER:-root}" "${DB_PASSWORD:-${DB_ROOT_PASSWORD:-}}"
            printf "   HTTP: ${C_CYAN}http://%s:%s/rpc${C_RESET}\n" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-8000}"
            ;;
        meilisearch)
            printf "   HTTP: ${C_CYAN}http://%s:%s${C_RESET} (Bearer: %s)\n" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-7700}" "${DB_ROOT_PASSWORD:-${DB_PASSWORD:-}}"
            ;;
        typesense)
            printf "   HTTP: ${C_CYAN}http://%s:%s${C_RESET} (X-TYPESENSE-API-KEY: %s)\n" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-8108}" "${DB_ROOT_PASSWORD:-${DB_PASSWORD:-}}"
            ;;
        pocketbase)
            printf "   Admin UI: ${C_CYAN}http://%s:%s/_/${C_RESET}\n" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-8090}"
            ;;
        minio)
            printf "   S3 API  : ${C_CYAN}http://%s:%s${C_RESET}\n" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-9000}"
            printf "   Console : ${C_CYAN}http://%s:%s${C_RESET}\n" "${INTERNAL_IP:-127.0.0.1}" "${CONSOLE_PORT:-$((SERVER_PORT + 1))}"
            ;;
        qdrant)
            printf "   REST API: ${C_CYAN}http://%s:%s${C_RESET}\n" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-6333}"
            printf "   Web UI  : ${C_CYAN}http://%s:%s/dashboard${C_RESET}\n" "${INTERNAL_IP:-127.0.0.1}" "${SERVER_PORT:-6333}"
            ;;
    esac
    printf "${C_BOLD}${C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n\n"
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
        if [ -n "${CUSTOM_COMMAND:-}" ]; then
            log "Executing custom command: ${CUSTOM_COMMAND}"
            exec ${CUSTOM_COMMAND}
        else
            fail "CUSTOM_COMMAND is empty. Provide a valid command to run."
        fi
        ;;
    *)
        fail "Unsupported database engine: '${PROJECT_TYPE}'"
        ;;
esac
