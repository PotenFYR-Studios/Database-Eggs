#!/usr/bin/env bash
# =============================================================================
#  PotenFYR Studios - MariaDB & MySQL Engine Handler
#  Crash-Proof, Docker OverlayFS Compatible, Auto-Tuned & Hardened
#  Honors DB_VERSION: prefers binaries provisioned by install-db-version.sh
#  (opt/mariadb or opt/mysql) and injects basedir automatically.
# =============================================================================

MARIADB_OPT_BASE="${SERVER_DIR}/opt/mariadb"
MYSQL_OPT_BASE="${SERVER_DIR}/opt/mysql"

find_mariadb_bin() { # find_mariadb_bin <name> [fallback-name]
    local name="$1" alt="${2:-}"
    local p
    for p in \
        "${MARIADB_OPT_BASE}/bin/${name}" \
        "${MYSQL_OPT_BASE}/bin/${name}" \
        "${MARIADB_OPT_BASE}/bin/${alt}" \
        "${MYSQL_OPT_BASE}/bin/${alt}"; do
        [ -n "${p}" ] && [ -x "${p}" ] && { printf '%s' "${p}"; return 0; }
    done
    if command -v "${name}" >/dev/null 2>&1; then command -v "${name}"; return 0; fi
    [ -n "${alt}" ] && command -v "${alt}" >/dev/null 2>&1 && { command -v "${alt}"; return 0; }
    return 1
}

activate_engine_libs() { # bundle libaio etc. for generic tarball builds
    for base in "${MARIADB_OPT_BASE}" "${MYSQL_OPT_BASE}"; do
        if [ -d "${base}/lib-extra" ]; then
            export LD_LIBRARY_PATH="${base}/lib-extra:${LD_LIBRARY_PATH:-}"
        fi
    done
}

init_mariadb_mysql() {
    activate_engine_libs
    local data_dir="${DATA_DIR:-${SERVER_DIR}/data}"
    local conf_dir="${SERVER_DIR}/config"
    local my_cnf="${conf_dir}/my.cnf"

    # Isolate unix sockets into /tmp/.db-sockets or fallback to internal socket dir
    local socket_dir="/tmp/.db-sockets"
    mkdir -p "${socket_dir}" 2>/dev/null || socket_dir="${SERVER_DIR}/socket"
    mkdir -p "${socket_dir}" "${data_dir}" "${conf_dir}" "${SERVER_DIR}/logs"
    chmod 700 "${socket_dir}" "${data_dir}" 2>/dev/null || true

    local socket_path="${socket_dir}/mysql.sock"
    local pid_path="${socket_dir}/mysql.pid"

    # Version-installed engine root (basedir) when present
    local engine_basedir=""
    [ -x "${MARIADB_OPT_BASE}/bin/mariadbd" ] && engine_basedir="${MARIADB_OPT_BASE}"
    [ -x "${MYSQL_OPT_BASE}/bin/mysqld" ] && engine_basedir="${MYSQL_OPT_BASE}"

    # Clean up any stale sockets or pid files from unclean shutdowns
    rm -f "${socket_path}" "${pid_path}" "${SERVER_DIR}/mysql.sock" "${SERVER_DIR}/mysql.pid" "${data_dir}/*.pid" 2>/dev/null || true

    # Run dynamic performance auto-tuning if available
    if command -v tune_mariadb_mysql >/dev/null 2>&1; then
        tune_mariadb_mysql
    else
        export TUNED_INNODB_BUFFER_POOL="${INNODB_BUFFER_POOL:-128M}"
        export TUNED_INNODB_LOG_FILE_SIZE="${INNODB_LOG_SIZE:-64M}"
        export TUNED_INNODB_POOL_INSTANCES="1"
        export TUNED_MYSQL_MAX_CONN="${MAX_CONNECTIONS:-150}"
    fi

    # Generate custom my.cnf if not present (or regenerate when basedir appeared)
    if [ ! -f "${my_cnf}" ]; then
        log "Generating performance-tuned my.cnf configuration..."
        cat <<EOF > "${my_cnf}"
[mysqld]
port=${SERVER_PORT}
bind-address=${BIND_ADDRESS:-0.0.0.0}
${engine_basedir:+basedir=${engine_basedir}}
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
innodb_flush_neighbors=0
innodb_io_capacity=2000
innodb_io_capacity_max=4000
join_buffer_size=1M
sort_buffer_size=2M
read_rnd_buffer_size=1M

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
        sed -i "s|^bind-address=.*|bind-address=${BIND_ADDRESS:-0.0.0.0}|g" "${my_cnf}" 2>/dev/null || true
        if [ -n "${engine_basedir}" ] && ! grep -q '^basedir=' "${my_cnf}" 2>/dev/null; then
            printf 'basedir=%s\n' "${engine_basedir}" >> "${my_cnf}"
        fi
    fi

    # Check if data directory is initialized
    local first_run=0
    if [ ! -d "${data_dir}/mysql" ] && [ ! -f "${data_dir}/ibdata1" ]; then
        first_run=1
        log "First run detected. Initializing database storage in ${data_dir}..."

        local init_out=""
        local init_ok=0

        local install_db_bin=""
        install_db_bin=$(find_mariadb_bin "mariadb-install-db" "mysql_install_db") || install_db_bin=""

        local basedir_arg="--basedir=/usr"
        local engine_basedir=""
        [ -x "${MARIADB_OPT_BASE}/bin/mariadbd" ] && engine_basedir="${MARIADB_OPT_BASE}"
        [ -x "${MYSQL_OPT_BASE}/bin/mysqld" ] && engine_basedir="${MYSQL_OPT_BASE}"
        [ -n "${engine_basedir}" ] && basedir_arg="--basedir=${engine_basedir}"

        if [ -n "${install_db_bin}" ]; then
            case "$(basename "${install_db_bin}")" in
                mariadb-install-db)
                    init_out=$("${install_db_bin}" ${basedir_arg} --datadir="${data_dir}" --auth-root-authentication-method=normal --skip-test-db 2>&1) && init_ok=1
                    if [ ${init_ok} -eq 0 ]; then
                        init_out=$("${install_db_bin}" --datadir="${data_dir}" --skip-test-db 2>&1) && init_ok=1
                    fi
                    ;;
                mysql_install_db)
                    init_out=$("${install_db_bin}" ${basedir_arg} --datadir="${data_dir}" 2>&1) && init_ok=1
                    ;;
            esac
        fi

        if [ ${init_ok} -eq 0 ]; then
            local mysqld_init_bin
            mysqld_init_bin=$(find_mariadb_bin "mariadbd" "mysqld") || mysqld_init_bin=""
            if [ -n "${mysqld_init_bin}" ] && basename "${mysqld_init_bin}" | grep -q "^mysqld$"; then
                init_out=$("${mysqld_init_bin}" --initialize-insecure ${basedir_arg} --datadir="${data_dir}" 2>&1) && init_ok=1
            fi
        fi

        if [ -d "${data_dir}/mysql" ] || [ -f "${data_dir}/ibdata1" ]; then
            ok "MariaDB/MySQL storage initialized successfully."
        else
            error "MariaDB/MySQL storage initialization failed."
            error "Detailed installer output:"
            printf '%s\n' "${init_out}" >&2
            fail "Fatal: Failed to initialize database storage in ${data_dir}."
        fi
    fi

    # If first run, apply security hardening and user creation
    if [ "${first_run}" -eq 1 ]; then
        log "Configuring users, root password, and security policies..."
        local daemon_bin
        daemon_bin=$(find_mariadb_bin "mariadbd" "mysqld") || {
            error "Neither mariadbd nor mysqld could be located."
            fail "MariaDB/MySQL daemon binary is unavailable."
        }

        local init_log="${SERVER_DIR}/logs/mariadb_init.log"
        "${daemon_bin}" --defaults-file="${my_cnf}" --skip-networking --socket="${socket_path}" > "${init_log}" 2>&1 &
        local tmp_pid=$!

        # Wait for socket
        local retries=30
        while [ ! -S "${socket_path}" ] && [ "${retries}" -gt 0 ]; do
            if ! kill -0 "${tmp_pid}" 2>/dev/null; then
                error "Temporary MariaDB daemon exited prematurely."
                if [ -f "${init_log}" ]; then
                    error "Recent daemon log output:"
                    tail -n 25 "${init_log}" >&2
                fi
                fail "Fatal: MariaDB initialization daemon crashed."
            fi
            sleep 1
            retries=$((retries - 1))
        done

        if [ -S "${socket_path}" ]; then
            local client_bin
            client_bin=$(find_mariadb_bin "mariadb" "mysql") || client_bin="mysql"

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
            warn "Could not connect to temporary socket. Checking init log..."
            [ -f "${init_log}" ] && tail -n 20 "${init_log}" >&2
            kill -s 9 "${tmp_pid}" 2>/dev/null || true
        fi
        rm -f "${socket_path}" "${pid_path}"
        ok "Initial configuration complete."
    fi
}
 
stop_mariadb_mysql() {
    local pid="$1"
    local socket_dir="/tmp/.db-sockets"
    local socket_path="${socket_dir}/mysql.sock"
    local client_bin
    client_bin=$(find_mariadb_bin "mariadb-admin" "mysqladmin") || client_bin=""

    # Attempt clean shutdown via admin client if socket is live
    if [ -n "${client_bin}" ] && [ -S "${socket_path}" ]; then
        "${client_bin}" -u root ${DB_ROOT_PASSWORD:+-p"${DB_ROOT_PASSWORD}"} --socket="${socket_path}" shutdown >/dev/null 2>&1 || true
    fi

    # Forward SIGTERM to daemon process if still running
    if kill -0 "${pid}" 2>/dev/null; then
        kill -TERM "${pid}" 2>/dev/null || true
    fi
}

start_mariadb_mysql() {
    activate_engine_libs
    local conf_dir="${SERVER_DIR}/config"
    local my_cnf="${conf_dir}/my.cnf"
    local data_dir="${DATA_DIR:-${SERVER_DIR}/data}"
    local socket_dir="/tmp/.db-sockets"
    local socket_path="${socket_dir}/mysql.sock"
    local pid_path="${socket_dir}/mysql.pid"

    # Self-healing check: if configuration or data is missing, run init
    if [ ! -f "${my_cnf}" ] || [ ! -d "${data_dir}/mysql" ]; then
        warn "Configuration or data files missing. Initializing MariaDB storage..."
        init_mariadb_mysql
    fi

    local daemon_bin
    daemon_bin=$(find_mariadb_bin "mariadbd" "mysqld") || {
        error "MariaDB/MySQL daemon binary not found in container."
        error "Please ensure your server uses the official image: ghcr.io/potenfyr-studios/database-eggs:*"
        fail "Daemon binary is unavailable."
    }

    # Surface the actual engine version being started (no silent downgrades)
    local actual_version
    actual_version=$("${daemon_bin}" --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+(-MariaDB)?' | head -n1)

    # Remove stale sockets before launching
    rm -f "${socket_path}" "${pid_path}" "${SERVER_DIR}/mysql.sock" "${SERVER_DIR}/mysql.pid" "/tmp/.db-sockets/mysql.sock" 2>/dev/null || true

    log "Starting ${PROJECT_TYPE^^} ${actual_version:+v${actual_version} }on ${BIND_ADDRESS:-0.0.0.0}:${SERVER_PORT}..."
    "${daemon_bin}" --defaults-file="${my_cnf}" ${EXTRA_ARGS:-} < /dev/null &
    local daemon_pid=$!
    supervise_daemon "${daemon_pid}" "stop_mariadb_mysql"
}
