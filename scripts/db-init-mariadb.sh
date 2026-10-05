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

# MariaDB must never run as root. Bootstrap may remain privileged, but the
# database daemon is always dropped to a dedicated non-root UID (default 988,
# matching the image's `container` account).
DB_RUNTIME_UID="${DB_RUNTIME_UID:-988}"
DB_RUNTIME_GID="${DB_RUNTIME_GID:-988}"

ensure_db_runtime_user() {
    local uid="${DB_RUNTIME_UID}" gid="${DB_RUNTIME_GID}"
    if [ "${uid}" != "988" ] || [ "${gid}" != "988" ]; then
        # Custom UID/GID requested: refuse to mutate /etc/passwd for
        # system-reserved identities.
        [ "${uid}" -ge 1000 ] && [ "${gid}" -ge 1000 ] || return 1
    fi
    if ! getent passwd "${uid}" >/dev/null 2>&1; then
        # The image chmods /etc/passwd 666; the `container` account (988)
        # ships with the image, so this only fires for custom UIDs.
        if [ -w /etc/group ]; then echo "dbuser:x:${gid}:" >> /etc/group 2>/dev/null || true; fi
        if [ -w /etc/passwd ]; then
            echo "dbuser:x:${uid}:${gid}:Database runtime user:${SERVER_DIR}:/bin/bash" >> /etc/passwd 2>/dev/null || true
        fi
    fi
    getent passwd "${uid}" >/dev/null 2>&1 || return 1
}

run_db_as_runtime_user() {
    # NOTE: every path below exec()s. Call this function only in a
    # backgrounded context (`run_db_as_runtime_user daemon ... &`) so the
    # replacement happens inside the subshell and $! stays the daemon PID.
    ensure_db_runtime_user || return 1
    if [ "$(id -u 2>/dev/null || echo 1)" != "0" ]; then
        exec "$@"
    fi
    if command -v gosu >/dev/null 2>&1; then
        exec gosu "${DB_RUNTIME_UID}:${DB_RUNTIME_GID}" "$@"
    elif command -v runuser >/dev/null 2>&1; then
        exec runuser -u "${DB_RUNTIME_UID}" -g "${DB_RUNTIME_GID}" -- "$@"
    elif command -v setpriv >/dev/null 2>&1; then
        exec setpriv --reuid="${DB_RUNTIME_UID}" --regid="${DB_RUNTIME_GID}" --clear-groups -- "$@"
    else
        error "No privilege-drop helper found (gosu/runuser/setpriv)."
        return 1
    fi
}

own_db_runtime_dirs() { # own_db_runtime_dirs <data_dir> <socket_dir>  (logs dir is derived)
    local data="${1:?data_dir required}" sock="${2:?socket_dir required}"
    chown -R "${DB_RUNTIME_UID}:${DB_RUNTIME_GID}" "${data}" "${sock}" "${SERVER_DIR}/logs" 2>/dev/null || true
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

    own_db_runtime_dirs "${data_dir}" "${socket_dir}"

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
# innodb_buffer_pool_instances deliberately not set: removed in MariaDB 13
# (warns even with the loose- prefix) and its old default behavior is what
# every supported version already picks for pools of this size.
innodb_log_file_size=${TUNED_INNODB_LOG_FILE_SIZE}
innodb_log_buffer_size=16M
# innodb_file_per_table intentionally not set: deprecated in MariaDB 13 and
# ON by default on every supported version.
innodb_flush_log_at_trx_commit=2
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
        # Persistent my.cnf may contain stale datadir/socket/pid/basedir values
        # from an older egg version or a moved DATA_DIR. Repair them all to the
        # effective paths before starting the daemon.
        mkdir -p "${data_dir}" "${socket_dir}" "${SERVER_DIR}/logs" 2>/dev/null || true
        sed -i "s/^port=.*/port=${SERVER_PORT}/g" "${my_cnf}" 2>/dev/null || true
        sed -i "s|^bind-address=.*|bind-address=${BIND_ADDRESS:-0.0.0.0}|g" "${my_cnf}" 2>/dev/null || true
        if grep -q '^datadir=' "${my_cnf}" 2>/dev/null; then
            sed -i "s|^datadir=.*|datadir=${data_dir}|g" "${my_cnf}" 2>/dev/null || true
        else
            sed -i "/^\[mysqld\]/a datadir=${data_dir}" "${my_cnf}" 2>/dev/null || true
        fi
        if grep -q '^socket=' "${my_cnf}" 2>/dev/null; then
            sed -i "s|^socket=.*|socket=${socket_path}|g" "${my_cnf}" 2>/dev/null || true
        else
            sed -i "/^\[mysqld\]/a socket=${socket_path}" "${my_cnf}" 2>/dev/null || true
        fi
        if grep -q '^pid-file=' "${my_cnf}" 2>/dev/null; then
            sed -i "s|^pid-file=.*|pid-file=${pid_path}|g" "${my_cnf}" 2>/dev/null || true
        else
            sed -i "/^\[mysqld\]/a pid-file=${pid_path}" "${my_cnf}" 2>/dev/null || true
        fi
        if [ -n "${engine_basedir}" ]; then
            if grep -q '^basedir=' "${my_cnf}" 2>/dev/null; then
                sed -i "s|^basedir=.*|basedir=${engine_basedir}|g" "${my_cnf}" 2>/dev/null || true
            else
                sed -i "/^\[mysqld\]/a basedir=${engine_basedir}" "${my_cnf}" 2>/dev/null || true
            fi
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
        # MariaDB 12.x defaults root@localhost to unix_socket auth, which an
        # unprivileged (uid 988) init cannot use. Run the bootstrap daemon with
        # skip-grant-tables and FLUSH PRIVILEGES inside the session so the root
        # password + accounts are provisioned reliably on every major version.
        # The daemon runs as the runtime user (never root) and owns the datadir.
        run_db_as_runtime_user "${daemon_bin}" --defaults-file="${my_cnf}" --skip-networking --skip-grant-tables --socket="${socket_path}" > "${init_log}" 2>&1 &
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
FLUSH PRIVILEGES;
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
# With skip-name-resolve, TCP clients from 127.0.0.1 need an explicit IP account.
# root is deliberately LOCAL-ONLY (localhost + 127.0.0.1); remote access is
# provided by the DB_USER application account, never by root@%.
CREATE USER IF NOT EXISTS 'root'@'127.0.0.1' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;
# Stale proxies_priv rows (seeded by an earlier bootstrap under a different
# container hostname) trigger an "ignored in --skip-name-resolve mode"
# warning on every start - remove them at the source.
DELETE FROM mysql.proxies_priv WHERE Host <> 'localhost' AND Host <> '127.0.0.1';
FLUSH PRIVILEGES;
EOSQL

            if [ -n "${DB_NAME:-}" ]; then
                "${client_bin}" -u root -p"${DB_ROOT_PASSWORD}" --socket="${socket_path}" >/dev/null 2>&1 <<EOSQL || true
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
EOSQL
                ok "Created database \`${DB_NAME}\`"
            fi

            if [ "${PF_USERS_MODE:-legacy}" = "legacy" ] && [ -n "${DB_USER:-}" ] && [ -n "${DB_PASSWORD:-}" ] && [ "${DB_USER}" != "root" ]; then
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

pf_mariadb_root_auth_ok() { # pf_mariadb_root_auth_ok <client-bin> <password>
    local client="${1:-mysql}" pw="${2:-}"
    [ -n "${pw}" ] || return 1
    "${client}" --protocol=tcp -h 127.0.0.1 -P "${SERVER_PORT:-3306}" -u root -p"${pw}" -N -e "SELECT 1" >/dev/null 2>&1
}

pf_mariadb_recover_root_auth() {
    # Existing installations may hold a stale/wrong root password (rotated
    # DB_ROOT_PASSWORD, legacy installs). Repair root credentials via a
    # skip-grant-tables bootstrap session WITHOUT deleting or reinitializing
    # the datadir, then restart the daemon normally. On success the new
    # daemon PID is published via PF_MARIADB_RECOVERED_PID for the supervisor.
    local old_pid="$1" daemon_bin="$2" my_cnf="$3" client="$4"
    local data_dir="${DATA_DIR:-${SERVER_DIR}/data}"
    local socket_dir="/tmp/.db-sockets"
    local recovery_socket="${socket_dir}/mysql-recovery.sock"
    local recovery_pidfile="${socket_dir}/mysql-recovery.pid"
    local recovery_log="${SERVER_DIR}/logs/mariadb-recovery.log"
    local recovery_pid="" rootpw="${DB_ROOT_PASSWORD:-}"

    # Only safe when the quote helper is available (db-init-users.sh loads it).
    command -v _pf_sql_quote >/dev/null 2>&1 || return 1
    [ -n "${rootpw}" ] || return 1
    [ -x "${daemon_bin}" ] || return 1
    mkdir -p "${socket_dir}" "${SERVER_DIR}/logs" "${data_dir}" 2>/dev/null || true
    rm -f "${recovery_socket}" "${recovery_pidfile}" 2>/dev/null || true

    warn "MariaDB root authentication failed. Starting automatic local recovery (data will NOT be deleted)."
    if [ -n "${old_pid}" ] && kill -0 "${old_pid}" 2>/dev/null; then
        kill -TERM "${old_pid}" 2>/dev/null || true
        local waited=0
        while kill -0 "${old_pid}" 2>/dev/null && [ "${waited}" -lt 15 ]; do
            sleep 1; waited=$((waited + 1))
        done
        if kill -0 "${old_pid}" 2>/dev/null; then kill -KILL "${old_pid}" 2>/dev/null || true; sleep 1; fi
        wait "${old_pid}" 2>/dev/null || true
    fi
    rm -f "${socket_dir}/mysql.sock" "${socket_dir}/mysql.pid" 2>/dev/null || true
    own_db_runtime_dirs "${data_dir}" "${socket_dir}"

    # Recovery must use an isolated configuration: the persistent my.cnf points
    # at the normal mysql.sock, and reusing it can start recovery on the normal
    # socket or leave two daemons fighting over the datadir. --no-defaults
    # ignores my.cnf entirely; every path is passed explicitly.
    local recovery_basedir=""
    [ -x "${MARIADB_OPT_BASE}/bin/mariadbd" ] && recovery_basedir="${MARIADB_OPT_BASE}"
    [ -z "${recovery_basedir}" ] && [ -x "${MYSQL_OPT_BASE}/bin/mysqld" ] && recovery_basedir="${MYSQL_OPT_BASE}"
    local -a recovery_args=(--no-defaults --datadir="${data_dir}" --skip-networking --skip-grant-tables
        --socket="${recovery_socket}" --pid-file="${recovery_pidfile}" --log-error="${recovery_log}"
        --port=0 --skip-name-resolve)
    [ -n "${recovery_basedir}" ] && recovery_args+=(--basedir="${recovery_basedir}")

    run_db_as_runtime_user "${daemon_bin}" "${recovery_args[@]}" > /dev/null 2>&1 &
    recovery_pid=$!

    local retries=30
    while [ ! -S "${recovery_socket}" ] && [ "${retries}" -gt 0 ]; do
        if ! kill -0 "${recovery_pid}" 2>/dev/null; then
            warn "MariaDB recovery daemon exited early."; tail -n 40 "${recovery_log}" 2>/dev/null || true; return 1
        fi
        sleep 1; retries=$((retries - 1))
    done
    if [ ! -S "${recovery_socket}" ]; then
        warn "MariaDB recovery socket did not become ready."
        local early_pid; early_pid=$(cat "${recovery_pidfile}" 2>/dev/null || true)
        [ -n "${early_pid}" ] && kill -KILL "${early_pid}" 2>/dev/null || true
        kill -KILL "${recovery_pid}" 2>/dev/null || true; wait "${recovery_pid}" 2>/dev/null || true
        rm -f "${recovery_socket}" "${recovery_pidfile}" 2>/dev/null || true
        return 1
    fi

    local qpw qdb quser quserpw
    qpw=$(_pf_sql_quote "${rootpw}")
    qdb="${DB_NAME:-database}"; qdb="${qdb//\`/\`\`}"
    quser="${DB_USER:-}"; quserpw=$(_pf_sql_quote "${DB_PASSWORD:-}")

    if "${client}" --protocol=socket --socket="${recovery_socket}" -u root -N 2>/dev/null <<__RECOVERY_SQL
FLUSH PRIVILEGES;
ALTER USER IF EXISTS 'root'@'localhost' IDENTIFIED BY '${qpw}';
CREATE USER IF NOT EXISTS 'root'@'localhost' IDENTIFIED BY '${qpw}';
ALTER USER IF EXISTS 'root'@'127.0.0.1' IDENTIFIED BY '${qpw}';
CREATE USER IF NOT EXISTS 'root'@'127.0.0.1' IDENTIFIED BY '${qpw}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION;
DROP USER IF EXISTS 'root'@'%';
DELETE FROM mysql.proxies_priv WHERE Host <> 'localhost' AND Host <> '127.0.0.1';
__RECOVERY_SQL
    then
        if [ -n "${quser}" ] && [ "${quser}" != "root" ] && [ -n "${DB_PASSWORD:-}" ]; then
            "${client}" --protocol=socket --socket="${recovery_socket}" -u root -N 2>/dev/null <<__USER_SQL || true
ALTER USER IF EXISTS '${quser}'@'%' IDENTIFIED BY '${quserpw}';
ALTER USER IF EXISTS '${quser}'@'localhost' IDENTIFIED BY '${quserpw}';
CREATE USER IF NOT EXISTS '${quser}'@'%' IDENTIFIED BY '${quserpw}';
CREATE USER IF NOT EXISTS '${quser}'@'localhost' IDENTIFIED BY '${quserpw}';
CREATE DATABASE IF NOT EXISTS \`${qdb}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON \`${qdb}\`.* TO '${quser}'@'%';
GRANT ALL PRIVILEGES ON \`${qdb}\`.* TO '${quser}'@'localhost';
FLUSH PRIVILEGES;
__USER_SQL
        fi
        ok "MariaDB root authentication repaired; root is local-only and the application account is provisioned."
    else
        warn "MariaDB recovery SQL failed. Existing data was left untouched."
        tail -n 40 "${recovery_log}" 2>/dev/null || true
        kill -TERM "${recovery_pid}" 2>/dev/null || true; wait "${recovery_pid}" 2>/dev/null || true
        rm -f "${recovery_socket}" "${recovery_pidfile}"
        return 1
    fi

    # The real daemon PID is in the pidfile (our run_db_as_runtime_user execs,
    # so $! already matches, but reading the pidfile is authoritative and
    # belt-and-braces against wrapper changes).
    local recovery_real_pid=""
    recovery_real_pid=$(cat "${recovery_pidfile}" 2>/dev/null || true)
    [ -n "${recovery_real_pid}" ] && kill -TERM "${recovery_real_pid}" 2>/dev/null || true
    kill -TERM "${recovery_pid}" 2>/dev/null || true
    waited=0
    while [ "${waited}" -lt 10 ]; do
        if [ -n "${recovery_real_pid}" ] && ! kill -0 "${recovery_real_pid}" 2>/dev/null; then break; fi
        if [ -z "${recovery_real_pid}" ] && ! kill -0 "${recovery_pid}" 2>/dev/null; then break; fi
        sleep 1; waited=$((waited + 1))
    done
    [ -n "${recovery_real_pid}" ] && kill -KILL "${recovery_real_pid}" 2>/dev/null || true
    kill -KILL "${recovery_pid}" 2>/dev/null || true; wait "${recovery_pid}" 2>/dev/null || true
    rm -f "${recovery_socket}" "${recovery_pidfile}" 2>/dev/null || true

    own_db_runtime_dirs "${data_dir}" "${socket_dir}"
    rm -f "${socket_dir}/mysql.sock" "${socket_dir}/mysql.pid" 2>/dev/null || true
    log "Starting MariaDB normally after authentication recovery..."
    run_db_as_runtime_user "${daemon_bin}" --defaults-file="${my_cnf}" ${EXTRA_ARGS:-} < /dev/null &
    PF_MARIADB_RECOVERED_PID=$!; export PF_MARIADB_RECOVERED_PID

    retries=30
    while [ ! -S "${socket_dir}/mysql.sock" ] && [ "${retries}" -gt 0 ]; do
        if ! kill -0 "${PF_MARIADB_RECOVERED_PID}" 2>/dev/null; then
            warn "MariaDB failed to restart after authentication recovery."; return 1
        fi
        sleep 1; retries=$((retries - 1))
    done
    [ -S "${socket_dir}/mysql.sock" ] || { warn "MariaDB socket did not return after authentication recovery."; return 1; }
    return 0
}

pf_mariadb_restore_dump() {
    # Optional one-shot SQL dump restore from ${SERVER_DIR}/dump.
    # RESTORE_DUMP=1 enables it. System schemas from older MariaDB/MySQL
    # dumps are skipped by default because their internal table definitions
    # are version-specific and must be managed by the running server.
    # This function never fails the boot: every exit path returns 0.
    [ "${RESTORE_DUMP:-0}" = "1" ] || return 0
    local dump_dir="${SERVER_DIR}/dump"
    [ -d "${dump_dir}" ] || { mkdir -p "${dump_dir}" 2>/dev/null || true; return 0; }

    local dump_file=""
    local f
    for f in "${dump_dir}"/*.sql "${dump_dir}"/*.sql.gz "${dump_dir}"/*.sql.xz "${dump_dir}"/*.sql.zst; do
        [ -f "${f}" ] || continue
        dump_file="${f}"
        break
    done
    if [ -z "${dump_file}" ]; then
        log "Dump restore enabled, but no .sql/.sql.gz/.sql.xz/.sql.zst file was found in ${dump_dir}."
        return 0
    fi

    local marker="${dump_dir}/.restored.sha256"
    local hash
    hash=$(sha256sum "${dump_file}" 2>/dev/null | awk '{print $1}')
    [ -n "${hash}" ] || { warn "Cannot calculate dump checksum: ${dump_file}"; return 0; }

    if [ -f "${marker}" ] && grep -qx "${hash}" "${marker}" 2>/dev/null; then
        log "Dump already restored: $(basename "${dump_file}")"
        return 0
    fi

    local client="${1:-mysql}" rootpw="${DB_ROOT_PASSWORD:-}" port="${SERVER_PORT:-3306}"
    [ -n "${rootpw}" ] || { warn "Dump restore skipped: DB_ROOT_PASSWORD is empty."; return 0; }

    # Logical dumps from older MariaDB releases can contain the old mysql.*
    # system database. Importing it into a newer MariaDB release produces
    # errors such as an incompatible mysql.column_stats definition.
    # The running server owns these system tables, so skip them by default.
    # Only the literal 0 disables the filter; empty/invalid keeps it enabled.
    local skip_system=1
    [ "${RESTORE_DUMP_SKIP_SYSTEM:-1}" = "0" ] && skip_system=0
    # Only the literal 1 enables --force; anything else keeps strict failure.
    local restore_force=0
    [ "${RESTORE_DUMP_FORCE:-0}" = "1" ] && restore_force=1
    local -a mysql_cmd=(--protocol=tcp -h 127.0.0.1 -P "${port}" -u root -p"${rootpw}" --max_allowed_packet=1G)
    [ "${restore_force}" = "1" ] && mysql_cmd+=(--force)
    local restore_log="${SERVER_DIR}/logs/dump-restore.log"
    log "Restoring database dump: $(basename "${dump_file}")..."
    if [ "${skip_system}" = "1" ]; then
        log "Skipping MariaDB system schemas (mysql, performance_schema, information_schema)."
    else
        log "System-schema filtering disabled (RESTORE_DUMP_SKIP_SYSTEM=0)."
    fi
    if [ "${restore_force}" = "1" ]; then
        log "MariaDB client --force enabled (RESTORE_DUMP_FORCE=1); SQL errors will not abort the import."
    fi

    local awk_filter='
        BEGIN { db = "" }
        /^[[:space:]]*USE[[:space:]]+/ {
            line = $0
            sub(/^[[:space:]]*USE[[:space:]]+/, "", line)
            gsub(/[`;]/, "", line)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
            db = tolower(line)
        }
        {
            if (skip_system && (db == "mysql" || db == "performance_schema" || db == "information_schema")) next
            print
        }'

    # Every pipeline stage is collected: a failure in decompression, the awk
    # filter, or the client (including a 3600s timeout) must never be treated
    # as a successful restore. The client stage is wrapped in `timeout` because
    # it is the long pole that could otherwise hang startup forever.
    local -a rcs=()
    : > "${restore_log}" 2>/dev/null || true

    case "${dump_file}" in
        *.sql)
            awk -v skip_system="${skip_system}" "${awk_filter}" "${dump_file}" \
                | timeout 3600 "${client}" "${mysql_cmd[@]}" >>"${restore_log}" 2>&1
            rcs=("${PIPESTATUS[@]}")
            ;;
        *.sql.gz)
            if command -v gzip >/dev/null 2>&1; then
                gzip -dc "${dump_file}" \
                    | awk -v skip_system="${skip_system}" "${awk_filter}" \
                    | timeout 3600 "${client}" "${mysql_cmd[@]}" >>"${restore_log}" 2>&1
                rcs=("${PIPESTATUS[@]}")
            else
                warn "gzip is unavailable; cannot restore $(basename "${dump_file}")."
                return 0
            fi
            ;;
        *.sql.xz)
            if command -v xz >/dev/null 2>&1; then
                xz -dc "${dump_file}" \
                    | awk -v skip_system="${skip_system}" "${awk_filter}" \
                    | timeout 3600 "${client}" "${mysql_cmd[@]}" >>"${restore_log}" 2>&1
                rcs=("${PIPESTATUS[@]}")
            else
                warn "xz is unavailable; cannot restore $(basename "${dump_file}")."
                return 0
            fi
            ;;
        *.sql.zst)
            if command -v zstd >/dev/null 2>&1; then
                zstd -dc "${dump_file}" \
                    | awk -v skip_system="${skip_system}" "${awk_filter}" \
                    | timeout 3600 "${client}" "${mysql_cmd[@]}" >>"${restore_log}" 2>&1
                rcs=("${PIPESTATUS[@]}")
            else
                warn "zstd is unavailable; cannot restore $(basename "${dump_file}")."
                return 0
            fi
            ;;
    esac

    # Strict success: requires every stage of the pipeline to have exited 0.
    local restore_ok=1
    if [ "${#rcs[@]}" -eq 0 ]; then
        restore_ok=0
    else
        local rc
        for rc in "${rcs[@]}"; do
            [ "${rc}" -eq 0 ] || restore_ok=0
        done
    fi

    # Error accounting: count the SQL error lines the client wrote to the log.
    local errors
    errors=$(grep -cE '^[[:space:]]*ERROR' "${restore_log}" 2>/dev/null || true)
    case "${errors}" in
        '' | *[!0-9]*) errors=0 ;;
    esac

    # force=1: record the restore even when SQL errors were reported, and note
    # the error count. force=0: only a clean import (every stage 0 AND no ERROR
    # lines) is recorded, so a partial import is never marked as restored.
    if [ "${restore_ok}" -eq 1 ] && { [ "${restore_force}" = "1" ] || [ "${errors}" -eq 0 ]; }; then
        printf '%s\n' "${hash}" > "${marker}" 2>/dev/null || true
        chmod 600 "${marker}" 2>/dev/null || true
        ok "Database dump restored successfully: $(basename "${dump_file}")"
        if [ "${restore_force}" = "1" ] && [ "${errors}" -gt 0 ]; then
            warn "Database dump restored with ${errors} SQL error(s); see ${restore_log}."
            printf '# forced=1 errors=%s at=%s\n' "${errors}" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "${marker}" 2>/dev/null || true
        fi
    else
        local last_err=""
        [ -f "${restore_log}" ] && last_err=$(grep -v '^[[:space:]]*$' "${restore_log}" 2>/dev/null | tail -n1)
        warn "Database dump restore failed: $(basename "${dump_file}")${last_err:+ (${last_err})}. The database remains running; fix the dump and restart to retry."
    fi
    return 0
}

start_mariadb_mysql() {
    activate_engine_libs
    local conf_dir="${SERVER_DIR}/config"
    local my_cnf="${conf_dir}/my.cnf"
    local data_dir="${DATA_DIR:-${SERVER_DIR}/data}"
    local socket_dir="/tmp/.db-sockets"
    local socket_path="${socket_dir}/mysql.sock"
    local pid_path="${socket_dir}/mysql.pid"

    # Always create the effective data directory before MariaDB starts. Older
    # boots may have left my.cnf pointing at opt/mariadb/data while the panel
    # environment points DATA_DIR somewhere else (or vice versa). MariaDB
    # otherwise fails with "Can't change dir ... No such file or directory"
    # before it can report a useful initialization error.
    mkdir -p "${data_dir}" "${socket_dir}" "${SERVER_DIR}/logs" 2>/dev/null || true
    if grep -q '^datadir=' "${my_cnf}" 2>/dev/null; then
        local configured_data_dir
        configured_data_dir=$(sed -n 's/^datadir=//p' "${my_cnf}" | head -n1)
        if [ -n "${configured_data_dir}" ]; then
            data_dir="${configured_data_dir}"
            mkdir -p "${data_dir}" 2>/dev/null || true
        fi
    fi

    # Self-healing check: if configuration or data is missing, run init
    if [ ! -f "${my_cnf}" ] || [ ! -d "${data_dir}/mysql" ]; then
        warn "Configuration or data files missing. Initializing MariaDB storage in ${data_dir}..."
        init_mariadb_mysql
        # Re-read the effective datadir after init in case init repaired my.cnf.
        if grep -q '^datadir=' "${my_cnf}" 2>/dev/null; then
            local repaired_data_dir
            repaired_data_dir=$(sed -n 's/^datadir=//p' "${my_cnf}" | head -n1)
            [ -n "${repaired_data_dir}" ] && data_dir="${repaired_data_dir}"
        fi
        mkdir -p "${data_dir}" 2>/dev/null || true
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

    ensure_db_runtime_user || fail "Cannot prepare non-root MariaDB runtime user ${DB_RUNTIME_UID}:${DB_RUNTIME_GID}."
    own_db_runtime_dirs "${data_dir}" "${socket_dir}"

    log "Starting ${PROJECT_TYPE^^} ${actual_version:+v${actual_version} }on ${BIND_ADDRESS:-0.0.0.0}:${SERVER_PORT} as uid ${DB_RUNTIME_UID}..."
    run_db_as_runtime_user "${daemon_bin}" --defaults-file="${my_cnf}" ${EXTRA_ARGS:-} < /dev/null &
    local daemon_pid=$!

    # Account model:
    #   * DB_USER / DB_PASSWORD is the REMOTE application account.
    #   * root is local-only (localhost + 127.0.0.1) and is never root@%.
    #   * A root-password drift alone must not take a healthy instance offline:
    #     pf_users_reconcile_mysql repairs it via the stored credential.
    # Full recovery (stop daemon -> skip-grant-tables repair -> restart) runs
    # only when the application account is unusable, or when
    # DB_FORCE_ROOT_RECOVERY=1 is explicitly requested. If recovery fails, the
    # daemon is restarted normally so the server never stays down.
    local client_bin
    client_bin=$(find_mariadb_bin "mariadb" "mysql" 2>/dev/null || echo mysql)
    PF_MARIADB_RECOVERED_PID=""
    local auth_wait=30
    while [ ! -S "${socket_path}" ] && [ "${auth_wait}" -gt 0 ] && kill -0 "${daemon_pid}" 2>/dev/null; do
        sleep 1; auth_wait=$((auth_wait - 1))
    done
    if [ -S "${socket_path}" ]; then
        # The app account's real password is the stored one (.db-users/
        # credentials): credentials apply exactly once at creation, so an
        # edited DB_PASSWORD must not make a healthy account look broken.
        local app_user="${DB_USER:-}"
        local app_pw=""
        if [ -n "${app_user}" ] && [ "${app_user}" != "root" ]; then
            if command -v pf_users_stored_password >/dev/null 2>&1; then
                app_pw="$(pf_users_stored_password "${app_user}")"
            fi
            [ -n "${app_pw}" ] || app_pw="${DB_PASSWORD:-}"
        fi
        local app_ok=1
        # Only probe the app account when it is EXPECTED to exist already.
        # On a genuine first boot the account is created later by
        # pf_users_reconcile_mysql - probing then would report a false
        # "not usable" and trigger an unnecessary full recovery.
        local app_expected=0
        if command -v pf_users_prev_list >/dev/null 2>&1 && pf_users_prev_list 2>/dev/null | grep -qxF "${app_user}"; then
            app_expected=1
        elif command -v pf_users_is_new >/dev/null 2>&1 && ! pf_users_is_new "${app_user}"; then
            app_expected=1
        fi
        if [ "${app_expected}" -eq 1 ] && [ -n "${app_user}" ] && [ "${app_user}" != "root" ] && [ -n "${app_pw}" ]; then
            if "${client_bin}" --protocol=tcp -h 127.0.0.1 -P "${SERVER_PORT:-3306}" -u "${app_user}" -p"${app_pw}" -N -e "SELECT 1" >/dev/null 2>&1; then
                log "Remote application account ${app_user}@% is healthy."
            else
                app_ok=0
                warn "Remote application account ${app_user}@% is not usable; automatic account recovery is required."
            fi
        fi
        local root_ok=1
        if ! pf_mariadb_root_auth_ok "${client_bin}" "${DB_ROOT_PASSWORD:-}"; then
            # If the app account is healthy, pf_users_reconcile_mysql repairs
            # the drift via the stored credential - do not warn twice when the
            # drift is about to be silently fixed a few lines below.
            if ! [ "${app_ok}" -eq 0 ] && [ "${DB_FORCE_ROOT_RECOVERY:-0}" != "1" ]; then
                root_ok=0
            fi
        fi

        if [ "${app_ok}" -eq 0 ] || [ "${DB_FORCE_ROOT_RECOVERY:-0}" = "1" ]; then
            if pf_mariadb_recover_root_auth "${daemon_pid}" "${daemon_bin}" "${my_cnf}" "${client_bin}"; then
                daemon_pid="${PF_MARIADB_RECOVERED_PID:-${daemon_pid}}"
            else
                warn "Automatic account recovery failed; restarting MariaDB normally without changing database data."
                rm -f "${socket_dir}/mysql.sock" "${socket_dir}/mysql.pid" 2>/dev/null || true
                run_db_as_runtime_user "${daemon_bin}" --defaults-file="${my_cnf}" ${EXTRA_ARGS:-} < /dev/null &
                daemon_pid=$!
                local restart_retries=30
                while [ ! -S "${socket_dir}/mysql.sock" ] && [ "${restart_retries}" -gt 0 ]; do
                    if ! kill -0 "${daemon_pid}" 2>/dev/null; then
                        warn "MariaDB could not be restarted after failed account recovery."
                        break
                    fi
                    sleep 1
                    restart_retries=$((restart_retries - 1))
                done
                [ -S "${socket_dir}/mysql.sock" ] && log "MariaDB restarted normally after failed account recovery."
            fi
        elif [ "${root_ok}" -eq 0 ]; then
            warn "Root password drift detected, but ${app_user:-the application account}@% is healthy; keeping MariaDB online. Use DB_FORCE_ROOT_RECOVERY=1 to repair root."
        fi
    fi

    # Restore the optional dump first so account reconciliation re-applies
    # grants after any DROP DATABASE inside the dump (RESTORE_DUMP=1).
    pf_mariadb_restore_dump "${client_bin}"

    # Multi-user account reconciliation (idempotent, retries while daemon warms up)
    if command -v pf_users_reconcile_mysql >/dev/null 2>&1; then
        pf_users_reconcile_mysql "${client_bin}"
    fi

    supervise_daemon "${daemon_pid}" "stop_mariadb_mysql"
}
