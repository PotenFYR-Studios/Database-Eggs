#!/usr/bin/env bash
# =============================================================================
#  PotenFYR Studios - PostgreSQL Engine Handler
#  Includes Automatic Performance Tuning and Production Security Hardening
# =============================================================================

export PATH="/usr/lib/postgresql/16/bin:/usr/lib/postgresql/15/bin:/usr/lib/postgresql/14/bin:${PATH}"

find_pg_bin() {
    local bin_name="$1"
    if command -v "${bin_name}" >/dev/null 2>&1; then
        command -v "${bin_name}"
        return 0
    fi
    local found
    found=$(find /usr/lib/postgresql /usr/local/bin /usr/bin -name "${bin_name}" -type f 2>/dev/null | sort -V | tail -n 1)
    if [ -n "${found}" ] && [ -x "${found}" ]; then
        echo "${found}"
        return 0
    fi
    echo "${bin_name}"
}

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

    local initdb_bin
    initdb_bin=$(find_pg_bin "initdb")

    local first_run=0
    if [ ! -f "${data_dir}/PG_VERSION" ] || [ ! -f "${data_dir}/postgresql.conf" ]; then
        first_run=1
        log "First run or uninitialized cluster detected. Initializing PostgreSQL in ${data_dir}..."

        # If data dir exists but has broken/incomplete files from a failed previous boot, clean it
        if [ -d "${data_dir}" ] && [ "$(ls -A "${data_dir}" 2>/dev/null)" ]; then
            if [ ! -f "${data_dir}/PG_VERSION" ]; then
                warn "Found incomplete data directory. Preparing clean cluster path..."
                rm -rf "${data_dir:?}"/* 2>/dev/null || true
            fi
        fi

        local pwfile="${SERVER_DIR}/.pg_pw_init"
        printf '%s' "${DB_ROOT_PASSWORD:-postgres}" > "${pwfile}"
        chmod 600 "${pwfile}"

        # Initialize cluster with UTF8 encoding
        "${initdb_bin}" -D "${data_dir}" \
               -U "${POSTGRES_USER:-postgres}" \
               --pwfile="${pwfile}" \
               --auth-local=trust \
               --auth-host=scram-sha-256 \
               --encoding=UTF8 \
               --locale=C.UTF-8 >/dev/null 2>&1
        local init_status=$?

        # Fallback if locale C.UTF-8 is unavailable in minimal container
        if [ ${init_status} -ne 0 ] || [ ! -f "${data_dir}/postgresql.conf" ]; then
            warn "Retrying cluster initialization with default system locale..."
            rm -rf "${data_dir:?}"/* 2>/dev/null || true
            "${initdb_bin}" -D "${data_dir}" \
                   -U "${POSTGRES_USER:-postgres}" \
                   --pwfile="${pwfile}" \
                   --auth-local=trust \
                   --auth-host=scram-sha-256 >/dev/null 2>&1 || true
        fi

        rm -f "${pwfile}"

        if [ -f "${data_dir}/PG_VERSION" ]; then
            ok "PostgreSQL cluster initialized successfully."
        else
            warn "Cluster initialization warning. Creating baseline postgresql.conf..."
        fi
    fi

    # Configure postgresql.conf and pg_hba.conf
    local conf_file="${data_dir}/postgresql.conf"
    local hba_file="${data_dir}/pg_hba.conf"

    # Emergency fallback if postgresql.conf still does not exist
    if [ ! -f "${conf_file}" ]; then
        cat <<EOF > "${conf_file}"
listen_addresses = '*'
port = ${SERVER_PORT}
max_connections = 100
shared_buffers = 128MB
dynamic_shared_memory_type = posix
password_encryption = scram-sha-256
EOF
    fi

    # Respect user custom config in config/postgresql.conf and config/pg_hba.conf if present
    if [ -f "${conf_dir}/pg_hba.conf" ]; then
        cp -f "${conf_dir}/pg_hba.conf" "${hba_file}" 2>/dev/null || true
    fi

    # Inject performance parameters and security settings into postgresql.conf
    if [ -f "${conf_file}" ]; then
        # Remove any previous appended tuning blocks to prevent duplicate accumulation
        sed -i '/# --- PotenFYR Studios Auto-Tuning/,/# --- End PotenFYR Tuning/d' "${conf_file}" 2>/dev/null || true

        cat <<EOF >> "${conf_file}"

# --- PotenFYR Studios Auto-Tuning & Hardening ---
port = ${SERVER_PORT}
listen_addresses = '*'
unix_socket_directories = '${socket_dir}'
password_encryption = scram-sha-256

# Include user custom configuration from config/postgresql.conf if present
include_if_exists = '${conf_dir}/postgresql.conf'
include_dir = '${conf_dir}/conf.d'
EOF

        if [ "${PERFORMANCE_TUNING:-1}" = "1" ]; then
            cat <<EOF >> "${conf_file}"

# Memory & Caching
shared_buffers = ${TUNED_PG_SHARED_BUFFERS:-128MB}
effective_cache_size = ${TUNED_PG_EFFECTIVE_CACHE:-512MB}
maintenance_work_mem = ${TUNED_PG_MAINT_WORK_MEM:-64MB}
work_mem = ${TUNED_PG_WORK_MEM:-4MB}
max_connections = ${TUNED_PG_MAX_CONNECTIONS:-100}

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
max_parallel_workers_per_gather = ${TUNED_PG_WORKERS:-2}
EOF
        fi

        cat <<EOF >> "${conf_file}"
# --- End PotenFYR Tuning ---
EOF
    fi

    # Ensure pg_hba.conf exists and enforces scram-sha-256 for all remote connections
    if [ ! -f "${hba_file}" ]; then
        cat <<EOF > "${hba_file}"
local   all             all                                     trust
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             ::1/128                 scram-sha-256
host    all             all             0.0.0.0/0               scram-sha-256
host    all             all             ::/0                    scram-sha-256
EOF
    elif ! grep -q "0.0.0.0/0" "${hba_file}"; then
        cat <<EOF >> "${hba_file}"
# Allow all IPv4 and IPv6 remote connections with SCRAM-SHA-256 encryption
host    all             all             0.0.0.0/0               scram-sha-256
host    all             all             ::/0                    scram-sha-256
local   all             all                                     trust
EOF
    fi

    # If first run, create application DB, user, and extensions
    if [ "${first_run}" -eq 1 ] && [ -f "${conf_file}" ]; then
        log "Starting temporary PostgreSQL daemon to provision database and users..."
        local pg_ctl_bin
        pg_ctl_bin=$(find_pg_bin "pg_ctl")

        "${pg_ctl_bin}" -D "${data_dir}" -o "-k ${socket_dir} -p ${SERVER_PORT}" -w start >/dev/null 2>&1 || true

        local superuser="${POSTGRES_USER:-postgres}"

        if [ -n "${DB_USER:-}" ] && [ "${DB_USER}" != "${superuser}" ] && [ -n "${DB_PASSWORD:-}" ]; then
            psql -h "${socket_dir}" -p "${SERVER_PORT}" -U "${superuser}" -d postgres >/dev/null 2>&1 <<EOSQL || true
CREATE USER "${DB_USER}" WITH ENCRYPTED PASSWORD '${DB_PASSWORD}';
EOSQL
            ok "Created PostgreSQL user '${DB_USER}'"
        fi

        if [ -n "${DB_NAME:-}" ] && [ "${DB_NAME}" != "postgres" ]; then
            local db_owner="${DB_USER:-${superuser}}"
            psql -h "${socket_dir}" -p "${SERVER_PORT}" -U "${superuser}" -d postgres >/dev/null 2>&1 <<EOSQL || true
CREATE DATABASE "${DB_NAME}" OWNER "${db_owner}" ENCODING 'UTF8';
GRANT ALL PRIVILEGES ON DATABASE "${DB_NAME}" TO "${db_owner}";
EOSQL
            ok "Created database '${DB_NAME}' owned by '${db_owner}'"
        fi

        # Load standard extensions if available
        psql -h "${socket_dir}" -p "${SERVER_PORT}" -U "${superuser}" -d "${DB_NAME:-postgres}" >/dev/null 2>&1 <<EOSQL || true
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "vector";
EOSQL
        ok "Loaded standard PostgreSQL extensions (uuid-ossp, pg_trgm, vector if available)."

        log "Shutting down temporary PostgreSQL daemon..."
        "${pg_ctl_bin}" -D "${data_dir}" -w stop >/dev/null 2>&1 || true
        ok "PostgreSQL initial provisioning completed."
    fi
}

start_postgres() {
    local data_dir="${DATA_DIR:-${SERVER_DIR}/data}"
    local socket_dir="${SERVER_DIR}/socket"

    # Self-healing check: if configuration is missing, run init
    if [ ! -f "${data_dir}/postgresql.conf" ] || [ ! -f "${data_dir}/PG_VERSION" ]; then
        warn "PostgreSQL cluster configuration missing in ${data_dir}. Initializing cluster..."
        init_postgres
    fi

    local pg_bin
    pg_bin=$(find_pg_bin "postgres")

    mkdir -p "${socket_dir}"
    chmod 777 "${socket_dir}" 2>/dev/null || true

    log "Starting PostgreSQL on 0.0.0.0:${SERVER_PORT} (Shared Buffers: ${TUNED_PG_SHARED_BUFFERS:-auto})..."
    exec "${pg_bin}" -D "${data_dir}" -k "${socket_dir}" -p "${SERVER_PORT}" -h "0.0.0.0" ${EXTRA_ARGS:-}
}
