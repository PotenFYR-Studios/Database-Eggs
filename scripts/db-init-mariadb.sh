#!/usr/bin/env bash
# =============================================================================
#  PotenFYR Studios - MariaDB & MySQL Engine Handler
# =============================================================================

set -euo pipefail

init_mariadb_mysql() {
    local data_dir="${DATA_DIR:-${SERVER_DIR}/data}"
    local conf_dir="${SERVER_DIR}/config"
    local my_cnf="${conf_dir}/my.cnf"
    local socket_path="${SERVER_DIR}/mysql.sock"
    local pid_path="${SERVER_DIR}/mysql.pid"

    mkdir -p "${data_dir}" "${conf_dir}" "${SERVER_DIR}/logs"

    # Generate custom my.cnf if not present
    if [ ! -f "${my_cnf}" ]; then
        log "Generating optimized my.cnf configuration..."
        cat <<EOF > "${my_cnf}"
[mysqld]
user=container
port=${SERVER_PORT}
bind-address=0.0.0.0
datadir=${data_dir}
socket=${socket_path}
pid-file=${pid_path}
log-error=${SERVER_DIR}/logs/mysql_error.log
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci
max_connections=${MAX_CONNECTIONS:-150}
innodb_buffer_pool_size=${INNODB_BUFFER_POOL:-128M}
innodb_log_file_size=${INNODB_LOG_SIZE:-64M}
innodb_flush_log_at_trx_commit=2
innodb_file_per_table=1
skip-name-resolve
skip-host-cache

[client]
port=${SERVER_PORT}
socket=${socket_path}
default-character-set=utf8mb4

[mysql]
default-character-set=utf8mb4
EOF
        ok "Created ${my_cnf}"
    else
        # Ensure port and paths in existing config match current allocation
        sed -i "s/^port=.*/port=${SERVER_PORT}/g" "${my_cnf}" 2>/dev/null || true
    fi

    # Check if data directory is initialized
    local first_run=0
    if [ ! -d "${data_dir}/mysql" ] && [ ! -f "${data_dir}/ibdata1" ]; then
        first_run=1
        log "First run detected. Initializing database storage in ${data_dir}..."

        if command -v mariadb-install-db >/dev/null 2>&1; then
            mariadb-install-db --user=container --datadir="${data_dir}" --auth-root-authentication-method=normal >/dev/null 2>&1
        elif command -v mysql_install_db >/dev/null 2>&1; then
            mysql_install_db --user=container --datadir="${data_dir}" >/dev/null 2>&1
        elif command -v mysqld >/dev/null 2>&1; then
            mysqld --initialize-insecure --user=container --datadir="${data_dir}" >/dev/null 2>&1
        else
            fail "Neither mariadb-install-db nor mysqld was found in the container image."
        fi
        ok "Storage initialized."
    fi

    # If first run or credentials need applying
    if [ "${first_run}" -eq 1 ]; then
        log "Starting temporary MySQL daemon to apply user credentials..."
        local daemon_bin="mysqld"
        command -v mariadbd >/dev/null 2>&1 && daemon_bin="mariadbd"

        "${daemon_bin}" --defaults-file="${my_cnf}" --skip-networking --socket="${socket_path}" &
        local tmp_pid=$!

        # Wait for socket
        local retries=30
        while [ ! -S "${socket_path}" ] && [ "${retries}" -gt 0 ]; do
            sleep 1
            retries=$((retries - 1))
        done

        if [ ! -S "${socket_path}" ]; then
            fail "Temporary MySQL daemon failed to start within 30 seconds."
        fi

        log "Configuring users and permissions..."
        local client_bin="mysql"
        command -v mariadb >/dev/null 2>&1 && client_bin="mariadb"

        # Apply root password
        "${client_bin}" -u root --socket="${socket_path}" <<EOSQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;
EOSQL

        # Create application database and user if specified
        if [ -n "${DB_NAME:-}" ]; then
            "${client_bin}" -u root -p"${DB_ROOT_PASSWORD}" --socket="${socket_path}" <<EOSQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
EOSQL
            ok "Created database \`${DB_NAME}\`"
        fi

        if [ -n "${DB_USER:-}" ] && [ -n "${DB_PASSWORD:-}" ] && [ "${DB_USER}" != "root" ]; then
            "${client_bin}" -u root -p"${DB_ROOT_PASSWORD}" --socket="${socket_path}" <<EOSQL
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_NAME:-*}\`.* TO '${DB_USER}'@'%';
GRANT ALL PRIVILEGES ON \`${DB_NAME:-*}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOSQL
            ok "Created user '${DB_USER}' with full privileges on '${DB_NAME:-*}'"
        fi

        "${client_bin}" -u root -p"${DB_ROOT_PASSWORD}" --socket="${socket_path}" -e "FLUSH PRIVILEGES;"

        log "Shutting down temporary MySQL daemon..."
        kill -s TERM "${tmp_pid}" 2>/dev/null || true
        wait "${tmp_pid}" 2>/dev/null || true
        rm -f "${socket_path}" "${pid_path}"
        ok "Initial database configuration complete."
    fi
}

start_mariadb_mysql() {
    local conf_dir="${SERVER_DIR}/config"
    local my_cnf="${conf_dir}/my.cnf"
    local daemon_bin="mysqld"
    command -v mariadbd >/dev/null 2>&1 && daemon_bin="mariadbd"

    log "Starting ${PROJECT_TYPE^^} on 0.0.0.0:${SERVER_PORT}..."
    exec "${daemon_bin}" --defaults-file="${my_cnf}" ${EXTRA_ARGS:-}
}
