#!/usr/bin/env bash
# =============================================================================
#  PotenFYR Studios - MariaDB & MySQL Engine Handler
#  Includes Automatic Performance Tuning and Production Security Hardening
# =============================================================================

set -euo pipefail

init_mariadb_mysql() {
    local data_dir="${DATA_DIR:-${SERVER_DIR}/data}"
    local conf_dir="${SERVER_DIR}/config"
    local my_cnf="${conf_dir}/my.cnf"
    local socket_path="${SERVER_DIR}/mysql.sock"
    local pid_path="${SERVER_DIR}/mysql.pid"

    mkdir -p "${data_dir}" "${conf_dir}" "${SERVER_DIR}/logs"
    chmod 700 "${data_dir}" 2>/dev/null || true

    # Run dynamic performance auto-tuning if available
    if command -v tune_mariadb_mysql >/dev/null 2>&1; then
        tune_mariadb_mysql
    else
        export TUNED_INNODB_BUFFER_POOL="${INNODB_BUFFER_POOL:-128M}"
        export TUNED_INNODB_LOG_FILE_SIZE="${INNODB_LOG_SIZE:-64M}"
        export TUNED_INNODB_POOL_INSTANCES="1"
        export TUNED_MYSQL_MAX_CONN="${MAX_CONNECTIONS:-150}"
        export TUNED_MYSQL_READ_IO_THREADS="4"
        export TUNED_MYSQL_WRITE_IO_THREADS="4"
    fi

    # Generate custom my.cnf if not present
    if [ ! -f "${my_cnf}" ]; then
        log "Generating performance-tuned & hardened my.cnf configuration..."
        cat <<EOF > "${my_cnf}"
[mysqld]
user=container
port=${SERVER_PORT}
bind-address=0.0.0.0
datadir=${data_dir}
socket=${socket_path}
pid-file=${pid_path}
log-error=${SERVER_DIR}/logs/mysql_error.log

# Charset & Collation
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci

# Performance Auto-Tuning (Calculated from SERVER_MEMORY=${SERVER_MEMORY:-1024}M)
innodb_buffer_pool_size=${TUNED_INNODB_BUFFER_POOL}
innodb_buffer_pool_instances=${TUNED_INNODB_POOL_INSTANCES}
innodb_log_file_size=${TUNED_INNODB_LOG_FILE_SIZE}
innodb_log_buffer_size=16M
innodb_flush_log_at_trx_commit=2
innodb_flush_method=O_DIRECT
innodb_file_per_table=1
innodb_read_io_threads=${TUNED_MYSQL_READ_IO_THREADS}
innodb_write_io_threads=${TUNED_MYSQL_WRITE_IO_THREADS}

# Connections & Caches
max_connections=${TUNED_MYSQL_MAX_CONN}
max_connect_errors=10000
thread_cache_size=32
table_open_cache=2000
table_definition_cache=1000
tmp_table_size=64M
max_heap_table_size=64M

# Security Hardening
skip-name-resolve
skip-host-cache
symbolic-links=0
local-infile=0

[client]
port=${SERVER_PORT}
socket=${socket_path}
default-character-set=utf8mb4

[mysql]
default-character-set=utf8mb4
EOF
        ok "Created performance-tuned ${my_cnf}"
    else
        # Ensure port matches current allocation
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

    # If first run, apply security hardening and user creation
    if [ "${first_run}" -eq 1 ]; then
        log "Starting temporary MySQL daemon to apply user credentials and security policies..."
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

        log "Configuring users, grants, and removing insecure defaults..."
        local client_bin="mysql"
        command -v mariadb >/dev/null 2>&1 && client_bin="mariadb"

        # Apply root password & remove insecure defaults
        "${client_bin}" -u root --socket="${socket_path}" <<EOSQL
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
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
            ok "Created user '${DB_USER}' with privileges on '${DB_NAME:-*}'"
        fi

        log "Shutting down temporary MySQL daemon..."
        kill -s TERM "${tmp_pid}" 2>/dev/null || true
        wait "${tmp_pid}" 2>/dev/null || true
        rm -f "${socket_path}" "${pid_path}"
        ok "Initial database configuration & security hardening complete."
    fi
}

start_mariadb_mysql() {
    local conf_dir="${SERVER_DIR}/config"
    local my_cnf="${conf_dir}/my.cnf"
    local daemon_bin="mysqld"
    command -v mariadbd >/dev/null 2>&1 && daemon_bin="mariadbd"

    log "Starting ${PROJECT_TYPE^^} on 0.0.0.0:${SERVER_PORT} (Buffer Pool: ${TUNED_INNODB_BUFFER_POOL:-auto})..."
    exec "${daemon_bin}" --defaults-file="${my_cnf}" ${EXTRA_ARGS:-}
}
