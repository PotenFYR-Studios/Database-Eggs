#!/usr/bin/env bash
# =============================================================================
#  PotenFYR Studios - PostgreSQL Engine Handler
#  Includes Automatic Performance Tuning and Production Security Hardening
# =============================================================================

set -euo pipefail

init_postgres() {
    local data_dir="${DATA_DIR:-${SERVER_DIR}/data}"
    local conf_dir="${SERVER_DIR}/config"
    local socket_dir="${SERVER_DIR}/socket"
    mkdir -p "${data_dir}" "${conf_dir}" "${socket_dir}" "${SERVER_DIR}/logs"
    chmod 700 "${data_dir}" "${socket_dir}" 2>/dev/null || true

    # Run performance auto-tuning
    if command -v tune_postgresql >/dev/null 2>&1; then
        tune_postgresql
    else
        export TUNED_PG_SHARED_BUFFERS="128MB"
        export TUNED_PG_EFFECTIVE_CACHE="512MB"
        export TUNED_PG_MAINT_WORK_MEM="64MB"
        export TUNED_PG_WORK_MEM="4MB"
        export TUNED_PG_MAX_CONNECTIONS="100"
        export TUNED_PG_WORKERS="2"
    fi

    local first_run=0
    if [ ! -f "${data_dir}/PG_VERSION" ]; then
        first_run=1
        log "First run detected. Initializing PostgreSQL cluster in ${data_dir}..."

        local pwfile="${SERVER_DIR}/.pg_pw_init"
        printf '%s' "${DB_ROOT_PASSWORD}" > "${pwfile}"
        chmod 600 "${pwfile}"

        initdb -D "${data_dir}" \
               -U "${POSTGRES_USER:-postgres}" \
               --pwfile="${pwfile}" \
               --auth-local=trust \
               --auth-host=scram-sha-256 \
               --encoding=UTF8 \
               --locale=C.UTF-8 >/dev/null 2>&1

        rm -f "${pwfile}"
        ok "PostgreSQL cluster initialized."
    fi

    # Configure postgresql.conf and pg_hba.conf
    local conf_file="${data_dir}/postgresql.conf"
    local hba_file="${data_dir}/pg_hba.conf"

    # Inject performance parameters and security settings into postgresql.conf
    if [ -f "${conf_file}" ]; then
        cat <<EOF >> "${conf_file}"

# --- PotenFYR Studios Auto-Tuning & Hardening ---
port = ${SERVER_PORT}
listen_addresses = '*'
unix_socket_directories = '${socket_dir}'
password_encryption = scram-sha-256

# Memory & Caching
shared_buffers = ${TUNED_PG_SHARED_BUFFERS}
effective_cache_size = ${TUNED_PG_EFFECTIVE_CACHE}
maintenance_work_mem = ${TUNED_PG_MAINT_WORK_MEM}
work_mem = ${TUNED_PG_WORK_MEM}
max_connections = ${TUNED_PG_MAX_CONNECTIONS}

# Checkpoints & WAL
wal_buffers = 16MB
min_wal_size = 512MB
max_wal_size = 2GB
checkpoint_completion_target = 0.9
checkpoint_timeout = 10min

# Query Planner (SSD / NVMe tuned)
random_page_cost = 1.1
effective_io_concurrency = 200
default_statistics_target = 100
max_parallel_workers_per_gather = ${TUNED_PG_WORKERS}
EOF
    fi

    # Ensure pg_hba.conf enforces scram-sha-256 for all remote connections
    if [ -f "${hba_file}" ]; then
        if ! grep -q "0.0.0.0/0" "${hba_file}"; then
            cat <<EOF >> "${hba_file}"
# Allow all IPv4 and IPv6 remote connections with SCRAM-SHA-256 encryption
host    all             all             0.0.0.0/0               scram-sha-256
host    all             all             ::/0                    scram-sha-256
local   all             all                                     trust
EOF
        fi
    fi

    # If first run, create application DB, user, and extensions
    if [ "${first_run}" -eq 1 ]; then
        log "Starting temporary PostgreSQL daemon to provision database and users..."
        pg_ctl -D "${data_dir}" -o "-k ${socket_dir} -p ${SERVER_PORT}" -w start >/dev/null 2>&1

        local superuser="${POSTGRES_USER:-postgres}"

        if [ -n "${DB_USER:-}" ] && [ "${DB_USER}" != "${superuser}" ] && [ -n "${DB_PASSWORD:-}" ]; then
            psql -h "${socket_dir}" -p "${SERVER_PORT}" -U "${superuser}" -d postgres <<EOSQL >/dev/null 2>&1
CREATE USER "${DB_USER}" WITH ENCRYPTED PASSWORD '${DB_PASSWORD}';
EOSQL
            ok "Created PostgreSQL user '${DB_USER}'"
        fi

        if [ -n "${DB_NAME:-}" ] && [ "${DB_NAME}" != "postgres" ]; then
            local db_owner="${DB_USER:-${superuser}}"
            psql -h "${socket_dir}" -p "${SERVER_PORT}" -U "${superuser}" -d postgres <<EOSQL >/dev/null 2>&1
CREATE DATABASE "${DB_NAME}" OWNER "${db_owner}" ENCODING 'UTF8';
GRANT ALL PRIVILEGES ON DATABASE "${DB_NAME}" TO "${db_owner}";
EOSQL
            ok "Created database '${DB_NAME}' owned by '${db_owner}'"
        fi

        # Load standard extensions if available
        psql -h "${socket_dir}" -p "${SERVER_PORT}" -U "${superuser}" -d "${DB_NAME:-postgres}" <<EOSQL >/dev/null 2>&1
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "vector";
EOSQL
        ok "Loaded standard PostgreSQL extensions (uuid-ossp, pg_trgm, vector if available)."

        log "Shutting down temporary PostgreSQL daemon..."
        pg_ctl -D "${data_dir}" -w stop >/dev/null 2>&1
        ok "PostgreSQL initial provisioning completed."
    fi
}

start_postgres() {
    local data_dir="${DATA_DIR:-${SERVER_DIR}/data}"
    local socket_dir="${SERVER_DIR}/socket"

    log "Starting PostgreSQL on 0.0.0.0:${SERVER_PORT} (Shared Buffers: ${TUNED_PG_SHARED_BUFFERS:-auto})..."
    exec postgres -D "${data_dir}" -k "${socket_dir}" -p "${SERVER_PORT}" -h "0.0.0.0" ${EXTRA_ARGS:-}
}
