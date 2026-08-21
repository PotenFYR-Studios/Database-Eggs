#!/usr/bin/env bash
# =============================================================================
#  PotenFYR Studios - PostgreSQL Engine Handler
# =============================================================================

set -euo pipefail

init_postgres() {
    local data_dir="${DATA_DIR:-${SERVER_DIR}/data}"
    local conf_dir="${SERVER_DIR}/config"
    local socket_dir="${SERVER_DIR}/socket"
    mkdir -p "${data_dir}" "${conf_dir}" "${socket_dir}" "${SERVER_DIR}/logs"

    local first_run=0
    if [ ! -f "${data_dir}/PG_VERSION" ]; then
        first_run=1
        log "First run detected. Initializing PostgreSQL cluster in ${data_dir}..."

        # Create custom pwfile for initial superuser
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

    # Symlink or persist configs if requested
    if [ -f "${conf_file}" ]; then
        sed -i "s/^#*port = .*/port = ${SERVER_PORT}/g" "${conf_file}" 2>/dev/null || true
        sed -i "s/^#*listen_addresses = .*/listen_addresses = '*'/g" "${conf_file}" 2>/dev/null || true
        sed -i "s|^#*unix_socket_directories = .*|unix_socket_directories = '${socket_dir}'|g" "${conf_file}" 2>/dev/null || true
    fi

    # Ensure pg_hba.conf allows remote host connections with scram-sha-256 / md5
    if [ -f "${hba_file}" ]; then
        if ! grep -q "0.0.0.0/0" "${hba_file}"; then
            cat <<EOF >> "${hba_file}"
# Allow all IPv4 and IPv6 remote connections with password
host    all             all             0.0.0.0/0               scram-sha-256
host    all             all             ::/0                    scram-sha-256
local   all             all                                     trust
EOF
        fi
    fi

    # If first run, create application DB and user
    if [ "${first_run}" -eq 1 ]; then
        log "Starting temporary PostgreSQL daemon to provision database and users..."
        pg_ctl -D "${data_dir}" -o "-k ${socket_dir} -p ${SERVER_PORT}" -w start >/dev/null 2>&1

        local superuser="${POSTGRES_USER:-postgres}"

        # Create application user if specified
        if [ -n "${DB_USER:-}" ] && [ "${DB_USER}" != "${superuser}" ] && [ -n "${DB_PASSWORD:-}" ]; then
            psql -h "${socket_dir}" -p "${SERVER_PORT}" -U "${superuser}" -d postgres <<EOSQL >/dev/null 2>&1
CREATE USER "${DB_USER}" WITH ENCRYPTED PASSWORD '${DB_PASSWORD}';
EOSQL
            ok "Created PostgreSQL user '${DB_USER}'"
        fi

        # Create application database if specified
        if [ -n "${DB_NAME:-}" ] && [ "${DB_NAME}" != "postgres" ]; then
            local db_owner="${DB_USER:-${superuser}}"
            psql -h "${socket_dir}" -p "${SERVER_PORT}" -U "${superuser}" -d postgres <<EOSQL >/dev/null 2>&1
CREATE DATABASE "${DB_NAME}" OWNER "${db_owner}" ENCODING 'UTF8';
GRANT ALL PRIVILEGES ON DATABASE "${DB_NAME}" TO "${db_owner}";
EOSQL
            ok "Created database '${DB_NAME}' owned by '${db_owner}'"
        fi

        # Install common extensions if present (e.g. uuid-ossp, pg_trgm, vector)
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

    log "Starting PostgreSQL on 0.0.0.0:${SERVER_PORT}..."
    exec postgres -D "${data_dir}" -k "${socket_dir}" -p "${SERVER_PORT}" -h "0.0.0.0" ${EXTRA_ARGS:-}
}
