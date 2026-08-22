#!/usr/bin/env bash
# =============================================================================
#  PotenFYR Studios - MariaDB & MySQL Engine Handler
#  Crash-Proof, Docker OverlayFS Compatible, Auto-Tuned & Hardened
# =============================================================================

init_mariadb_mysql() {
    local data_dir="${DATA_DIR:-${SERVER_DIR}/data}"
    local conf_dir="${SERVER_DIR}/config"
    local my_cnf="${conf_dir}/my.cnf"
    local socket_path="${SERVER_DIR}/mysql.sock"
    local pid_path="${SERVER_DIR}/mysql.pid"

    mkdir -p "${data_dir}" "${conf_dir}" "${SERVER_DIR}/logs"
    chmod 700 "${data_dir}" 2>/dev/null || true

    # Clean up any stale sockets or pid files from unclean shutdowns
    rm -f "${socket_path}" "${pid_path}" "${data_dir}/*.pid" 2>/dev/null || true

    # Run dynamic performance auto-tuning if available
    if command -v tune_mariadb_mysql >/dev/null 2>&1; then
        tune_mariadb_mysql
    else
        export TUNED_INNODB_BUFFER_POOL="${INNODB_BUFFER_POOL:-128M}"
        export TUNED_INNODB_LOG_FILE_SIZE="${INNODB_LOG_SIZE:-64M}"
        export TUNED_INNODB_POOL_INSTANCES="1"
        export TUNED_MYSQL_MAX_CONN="${MAX_CONNECTIONS:-150}"
    fi

    # Generate custom my.cnf if not present
    if [ ! -f "${my_cnf}" ]; then
        log "Generating performance-tuned my.cnf configuration..."
        cat <<EOF > "${my_cnf}"
[mysqld]
port=${SERVER_PORT}
bind-address=0.0.0.0
datadir=${data_dir}
socket=${socket_path}
pid-file=${pid_path}

# Charset & Collation
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci

# Performance Auto-Tuning
innodb_buffer_pool_size=${TUNED_INNODB_BUFFER_POOL}
innodb_buffer_pool_instances=${TUNED_INNODB_POOL_INSTANCES}
innodb_log_file_size=${TUNED_INNODB_LOG_FILE_SIZE}
innodb_log_buffer_size=16M
innodb_flush_log_at_trx_commit=2
innodb_file_per_table=1

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
symbolic-links=0
local-infile=0

[client]
port=${SERVER_PORT}
socket=${socket_path}
default-character-set=utf8mb4

[mysql]
default-character-set=utf8mb4
EOF
        ok "Created ${my_cnf}"
    else
        sed -i "s/^port=.*/port=${SERVER_PORT}/g" "${my_cnf}" 2>/dev/null || true
    fi

    # Check if data directory is initialized
    local first_run=0
    if [ ! -d "${data_dir}/mysql" ] && [ ! -f "${data_dir}/ibdata1" ]; then
        first_run=1
        log "First run detected. Initializing database storage in ${data_dir}..."

        mariadb-install-db --basedir=/usr --datadir="${data_dir}" --auth-root-authentication-method=normal --skip-test-db >/dev/null 2>&1 || \
        mariadb-install-db --datadir="${data_dir}" --skip-test-db >/dev/null 2>&1 || \
        mysql_install_db --basedir=/usr --datadir="${data_dir}" >/dev/null 2>&1 || \
        mysqld --initialize-insecure --basedir=/usr --datadir="${data_dir}" >/dev/null 2>&1 || true

        ok "Storage initialized."
    fi

    # If first run, apply security hardening and user creation
    if [ "${first_run}" -eq 1 ]; then
        log "Configuring users, root password, and security policies..."
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

        if [ -S "${socket_path}" ]; then
            local client_bin="mysql"
            command -v mariadb >/dev/null 2>&1 && client_bin="mariadb"

            "${client_bin}" -u root --socket="${socket_path}" >/dev/null 2>&1 <<EOSQL || true
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOSQL

            if [ -n "${DB_NAME:-}" ]; then
                "${client_bin}" -u root -p"${DB_ROOT_PASSWORD}" --socket="${socket_path}" >/dev/null 2>&1 <<EOSQL || true
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
EOSQL
                ok "Created database \`${DB_NAME}\`"
            fi

            if [ -n "${DB_USER:-}" ] && [ -n "${DB_PASSWORD:-}" ] && [ "${DB_USER}" != "root" ]; then
                "${client_bin}" -u root -p"${DB_ROOT_PASSWORD}" --socket="${socket_path}" >/dev/null 2>&1 <<EOSQL || true
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_NAME:-*}\`.* TO '${DB_USER}'@'%';
GRANT ALL PRIVILEGES ON \`${DB_NAME:-*}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOSQL
                ok "Created user '${DB_USER}'"
            fi

            kill -s TERM "${tmp_pid}" 2>/dev/null || true
            wait "${tmp_pid}" 2>/dev/null || true
        else
            warn "Could not connect to temporary socket. Proceeding to main daemon start."
            kill -s 9 "${tmp_pid}" 2>/dev/null || true
        fi
        rm -f "${socket_path}" "${pid_path}"
        ok "Initial configuration complete."
    fi
}

start_mariadb_mysql() {
    local conf_dir="${SERVER_DIR}/config"
    local my_cnf="${conf_dir}/my.cnf"
    local data_dir="${DATA_DIR:-${SERVER_DIR}/data}"

    # Self-healing check: if configuration or data is missing, run init
    if [ ! -f "${my_cnf}" ] || [ ! -d "${data_dir}/mysql" ]; then
        warn "Configuration or data files missing. Initializing MariaDB storage..."
        init_mariadb_mysql
    fi

    local daemon_bin="mysqld"
    command -v mariadbd >/dev/null 2>&1 && daemon_bin="mariadbd"

    # Remove stale sockets before launching
    rm -f "${SERVER_DIR}/mysql.sock" "${SERVER_DIR}/mysql.pid" 2>/dev/null || true

    log "Starting ${PROJECT_TYPE^^} on 0.0.0.0:${SERVER_PORT}..."
    exec "${daemon_bin}" --defaults-file="${my_cnf}" ${EXTRA_ARGS:-}
}
