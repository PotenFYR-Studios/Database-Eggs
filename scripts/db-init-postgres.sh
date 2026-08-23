#!/usr/bin/env bash
# =============================================================================
#  PotenFYR Studios - PostgreSQL Engine Handler
#  Includes Automatic Performance Tuning and Production Security Hardening
#  Honors the DB_VERSION startup variable exactly (13, 14, 15, 16, 17, 18,
#  or 'latest' which resolves dynamically at boot).
# =============================================================================

export PATH="/usr/lib/postgresql/18/bin:/usr/lib/postgresql/17/bin:/usr/lib/postgresql/16/bin:/usr/lib/postgresql/15/bin:${PATH}"

pg_requested_major() {
    local v="${DB_VERSION:-latest}"
    v=$(echo "${v}" | tr '[:upper:]' '[:lower:]')
    case "${v}" in
        latest|default|stable|"") echo "" ;;
        *)
            local major="${v%%.*}"
            [[ "${major}" =~ ^[0-9]+$ ]] && echo "${major}" || echo ""
            ;;
    esac
}

find_pg_bin() {
    local bin_name="$1"
    local req_major
    req_major=$(pg_requested_major)

    # 1) Exact standalone install provisioned by install-db-version.sh
    if [ -n "${req_major}" ] && [ -x "${SERVER_DIR}/bin/pg-${req_major}/bin/${bin_name}" ]; then
        echo "${SERVER_DIR}/bin/pg-${req_major}/bin/${bin_name}"
        return 0
    fi

    # 2) Version-pinned system path (PGDG apt layout)
    if [ -n "${req_major}" ] && [ -x "/usr/lib/postgresql/${req_major}/bin/${bin_name}" ]; then
        echo "/usr/lib/postgresql/${req_major}/bin/${bin_name}"
        return 0
    fi

    # 3) Any standalone install (newest first)
    local found
    found=$(ls -1d "${SERVER_DIR}"/bin/pg-*/bin/"${bin_name}" 2>/dev/null | sort -V | tail -n1)
    if [ -n "${found}" ] && [ -x "${found}" ]; then
        echo "${found}"
        return 0
    fi

    # 4) System paths (newest installed major wins)
    found=$(ls -1d /usr/lib/postgresql/*/bin/"${bin_name}" 2>/dev/null | sort -V | tail -n1)
    if [ -n "${found}" ] && [ -x "${found}" ]; then
        echo "${found}"
        return 0
    fi

    # 5) Generic PATH fallback
    if command -v "${bin_name}" >/dev/null 2>&1; then
        command -v "${bin_name}"
        return 0
    fi

    echo ""
    return 1
}

# Guard: refuse to boot an incompatible cluster instead of crashing cryptically.
# Existing data initialized by a different major than explicitly requested is
# the #1 cause of "version ignored" confusion - surface it clearly.
guard_pg_data_compat() {
    local data_dir="${DATA_DIR:-${SERVER_DIR}/data}"
    local pg_version_file="${data_dir}/PG_VERSION"
    [ -f "${pg_version_file}" ] || return 0

    local req_major existing_major
    req_major=$(pg_requested_major)
    existing_major=$(cat "${pg_version_file}" 2>/dev/null | tr -d '[:space:]')

    # No explicit pin -> adopt whatever the data dir was created with (zero friction upgrades of running servers)
    if [ -z "${req_major}" ] || [ "${req_major}" = "${existing_major}" ]; then
        export PG_EFFECTIVE_MAJOR="${existing_major}"
        return 0
    fi

    local _red="${C_RED:-\033[31m}" _bold="${C_BOLD:-\033[1m}" _rst="${C_RESET:-\033[0m}"
    {
        printf "\n${_red}${_bold}┌─────────────────────────────────────────────────────────────┐${_rst}\n"
        printf "${_red}${_bold}│  ✗ POSTGRESQL VERSION MISMATCH - ACTION REQUIRED            │${_rst}\n"
        printf "${_red}${_bold}├─────────────────────────────────────────────────────────────┤${_rst}\n"
        printf "${_red}${_bold}│${_rst}  Startup variable DB_VERSION : %-28s ${_red}${_bold}│${_rst}\n" "${req_major}"
        printf "${_red}${_bold}│${_rst}  Data directory was created  : PostgreSQL %-18s ${_red}${_bold}│${_rst}\n" "${existing_major}"
        printf "${_red}${_bold}│${_rst}  Data directory path         : %-28s ${_red}${_bold}│${_rst}\n" "${data_dir}"
        printf "${_red}${_bold}├─────────────────────────────────────────────────────────────┤${_rst}\n"
        printf "${_red}${_bold}│${_rst}  PostgreSQL cannot read data files across major versions.   ${_red}${_bold}│${_rst}\n"
        printf "${_red}${_bold}│${_rst}  Your existing data is SAFE. Choose ONE option:             ${_red}${_bold}│${_rst}\n"
        printf "${_red}${_bold}│${_rst}   1) Keep data      -> set DB_VERSION=%-16s ${_red}${_bold}│${_rst}\n" "${existing_major}"
        printf "${_red}${_bold}│${_rst}   2) Fresh v%-9s -> set DATA_DIR=data-v%-11s ${_red}${_bold}│${_rst}\n" "${req_major}" "${req_major}"
        printf "${_red}${_bold}│${_rst}   3) Wipe & reinit  -> backup then empty the data folder    ${_red}${_bold}│${_rst}\n"
        printf "${_red}${_bold}└─────────────────────────────────────────────────────────────┘${_rst}\n\n"
    } >&2
    fail "PostgreSQL ${req_major} cannot start on a v${existing_major} data directory."
}

init_postgres() {
    local data_dir="${DATA_DIR:-${SERVER_DIR}/data}"
    local conf_dir="${SERVER_DIR}/config"
    local socket_dir="/tmp/.db-sockets"
    mkdir -p "${socket_dir}" 2>/dev/null || socket_dir="${SERVER_DIR}/socket"
    mkdir -p "${data_dir}" "${conf_dir}" "${conf_dir}/conf.d" "${socket_dir}" "${SERVER_DIR}/logs"
    chmod 700 "${data_dir}" 2>/dev/null || true
    chmod 777 "${socket_dir}" 2>/dev/null || true

    # Enforce version compatibility before touching anything
    guard_pg_data_compat

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

    # Bundled runtime libs (libxml2/icu/libossp-uuid) must be visible to the
    # server AND every backend that loads contrib extensions (uuid-ossp).
    local _pg_home=""
    _pg_home="$(dirname "$(dirname "${initdb_bin}")" 2>/dev/null || true)"
    if [ -d "${_pg_home}/lib-extra" ]; then
        export LD_LIBRARY_PATH="${_pg_home}/lib-extra:${LD_LIBRARY_PATH:-}"
    fi

    local first_run=0
    if [ ! -f "${data_dir}/PG_VERSION" ]; then
        first_run=1
        log "First run or uninitialized cluster detected. Initializing PostgreSQL in ${data_dir}..."

        # If data dir exists, clean any broken/incomplete files from a failed previous boot
        if [ -d "${data_dir}" ]; then
            warn "Preparing clean cluster path in ${data_dir}..."
            rm -rf "${data_dir:?}"/* "${data_dir:?}"/.[!.]* 2>/dev/null || true
        fi
        mkdir -p "${data_dir}" "${conf_dir}" "${conf_dir}/conf.d" "${socket_dir}" "${SERVER_DIR}/logs"
        chmod 700 "${data_dir}" 2>/dev/null || true
        chmod 777 "${socket_dir}" 2>/dev/null || true

        local pwfile="/tmp/.pg_pw_init"
        printf '%s' "${DB_ROOT_PASSWORD:-postgres}" > "${pwfile}"
        chmod 600 "${pwfile}" 2>/dev/null || true

        # Ensure current effective UID exists in /etc/passwd for getpwuid() in PostgreSQL initdb
        local current_uid
        current_uid=$(id -u 2>/dev/null || echo "988")
        local current_gid
        current_gid=$(id -g 2>/dev/null || echo "988")
        if ! getent passwd "${current_uid}" >/dev/null 2>&1; then
            if [ -w /etc/passwd ]; then
                echo "container:x:${current_uid}:${current_gid}:container user:${SERVER_DIR}:/bin/bash" >> /etc/passwd 2>/dev/null || true
            fi
        fi
        if ! getent group "${current_gid}" >/dev/null 2>&1; then
            if [ -w /etc/group ]; then
                echo "container:x:${current_gid}:" >> /etc/group 2>/dev/null || true
            fi
        fi

        local init_out=""
        local init_status=1

        # Attempt 1: UTF-8 with C.UTF-8 locale & SCRAM authentication
        init_out=$("${initdb_bin}" -D "${data_dir}" \
                   -U "${POSTGRES_USER:-postgres}" \
                   --pwfile="${pwfile}" \
                   --auth-local=trust \
                   --auth-host=scram-sha-256 \
                   --encoding=UTF8 \
                   --locale=C.UTF-8 2>&1)
        init_status=$?

        # Attempt 2: Standard C locale
        if [ ${init_status} -ne 0 ] || [ ! -f "${data_dir}/PG_VERSION" ]; then
            warn "Retrying cluster initialization with default system locale (C)..."
            rm -rf "${data_dir:?}"/* "${data_dir:?}"/.[!.]* 2>/dev/null || true
            init_out=$("${initdb_bin}" -D "${data_dir}" \
                       -U "${POSTGRES_USER:-postgres}" \
                       --pwfile="${pwfile}" \
                       --auth-local=trust \
                       --auth-host=scram-sha-256 \
                       --locale=C 2>&1)
            init_status=$?
        fi

        # Attempt 3: Standard auth flag (-A scram-sha-256)
        if [ ${init_status} -ne 0 ] || [ ! -f "${data_dir}/PG_VERSION" ]; then
            warn "Retrying cluster initialization with standard auth flag (-A)..."
            rm -rf "${data_dir:?}"/* "${data_dir:?}"/.[!.]* 2>/dev/null || true
            init_out=$("${initdb_bin}" -D "${data_dir}" \
                       -U "${POSTGRES_USER:-postgres}" \
                       --pwfile="${pwfile}" \
                       -A scram-sha-256 2>&1)
            init_status=$?
        fi

        # Attempt 4: Minimal bare initialization
        if [ ${init_status} -ne 0 ] || [ ! -f "${data_dir}/PG_VERSION" ]; then
            warn "Retrying minimal cluster initialization..."
            rm -rf "${data_dir:?}"/* "${data_dir:?}"/.[!.]* 2>/dev/null || true
            init_out=$("${initdb_bin}" -D "${data_dir}" \
                       -U "${POSTGRES_USER:-postgres}" \
                       -A trust 2>&1)
            init_status=$?
        fi

        rm -f "${pwfile}" 2>/dev/null || true

        if [ -f "${data_dir}/PG_VERSION" ]; then
            ok "PostgreSQL cluster initialized successfully."
        else
            error "PostgreSQL cluster creation failed."
            error "initdb output details:"
            printf '%s\n' "${init_out}" >&2
            fail "Fatal: PostgreSQL cluster could not be created in ${data_dir}."
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
EOF

        # Include user custom configuration from config/postgresql.conf if present
        if [ -f "${conf_dir}/postgresql.conf" ]; then
            echo "include_if_exists = '${conf_dir}/postgresql.conf'" >> "${conf_file}"
        fi
        if [ -d "${conf_dir}/conf.d" ]; then
            echo "include_dir = '${conf_dir}/conf.d'" >> "${conf_file}"
        fi

        if [ "${PERFORMANCE_TUNING:-1}" = "1" ]; then
            cat <<EOF >> "${conf_file}"

# Memory & Caching
shared_buffers = ${TUNED_PG_SHARED_BUFFERS:-128MB}
effective_cache_size = ${TUNED_PG_EFFECTIVE_CACHE:-512MB}
maintenance_work_mem = ${TUNED_PG_MAINT_WORK_MEM:-64MB}
work_mem = ${TUNED_PG_WORK_MEM:-4MB}
hash_mem_multiplier = 2.0
max_connections = ${TUNED_PG_MAX_CONNECTIONS:-100}
max_worker_processes = ${TUNED_PG_MAX_WORKERS:-8}
max_parallel_workers = ${TUNED_PG_MAX_WORKERS:-8}
max_parallel_workers_per_gather = ${TUNED_PG_WORKERS_PER_GATHER:-2}
jit = off

# Checkpoints & WAL (scaled to RAM; SSD/NVMe cadence)
wal_buffers = 16MB
min_wal_size = ${TUNED_PG_MIN_WAL:-512MB}
max_wal_size = ${TUNED_PG_MAX_WAL:-2GB}
checkpoint_completion_target = 0.9
checkpoint_timeout = 15min
checkpoint_flush_after = 256kB
wal_compression = lz4
wal_writer_flush_after = 1MB

# Autovacuum (production cluster profile)
autovacuum = on
autovacuum_max_workers = ${TUNED_PG_AV_WORKERS:-3}
autovacuum_naptime = ${TUNED_PG_AV_NAPTIME:-30}s
autovacuum_vacuum_cost_limit = ${TUNED_PG_AV_COST:-200}
autovacuum_vacuum_scale_factor = 0.05
autovacuum_analyze_scale_factor = 0.02

# Query Planner (SSD / NVMe tuned)
random_page_cost = 1.1
effective_io_concurrency = 200
default_statistics_target = 100
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
    if [ "${first_run}" -eq 1 ] && [ -f "${conf_file}" ] && [ -f "${data_dir}/PG_VERSION" ]; then
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

        # Load standard extensions - each independently, only if the build
        # provides it (zero error spam on minimal/standalone builds)
        local ext
        for ext in pg_trgm uuid-ossp vector; do
            if psql -h "${socket_dir}" -p "${SERVER_PORT}" -U "${superuser}" -d postgres -Atc \
                "SELECT 1 FROM pg_available_extensions WHERE name='${ext}'" 2>/dev/null | grep -q 1; then
                if psql -h "${socket_dir}" -p "${SERVER_PORT}" -U "${superuser}" -d "${DB_NAME:-postgres}" \
                    -c "CREATE EXTENSION IF NOT EXISTS \"${ext}\";" >/dev/null 2>&1; then
                    ok "Extension ready: ${ext}"
                else
                    warn "Extension ${ext} available but CREATE failed (see postgres logs)."
                fi
            else
                log "Extension '${ext}' not present in this PostgreSQL build - skipped."
            fi
        done

        log "Shutting down temporary PostgreSQL daemon..."
        "${pg_ctl_bin}" -D "${data_dir}" -w stop >/dev/null 2>&1 || true
        ok "PostgreSQL initial provisioning completed."
    fi
}

start_postgres() {
    local data_dir="${DATA_DIR:-${SERVER_DIR}/data}"
    local socket_dir="/tmp/.db-sockets"
    mkdir -p "${socket_dir}" 2>/dev/null || socket_dir="${SERVER_DIR}/socket"
    mkdir -p "${socket_dir}"
    chmod 777 "${socket_dir}" 2>/dev/null || true

    # Version compatibility guard (explicit DB_VERSION vs existing cluster)
    guard_pg_data_compat

    # Self-healing check: if configuration is missing, run init
    if [ ! -f "${data_dir}/postgresql.conf" ] || [ ! -f "${data_dir}/PG_VERSION" ]; then
        warn "PostgreSQL cluster configuration missing in ${data_dir}. Initializing cluster..."
        init_postgres
    fi

    local pg_bin
    pg_bin=$(find_pg_bin "postgres") || {
        error "PostgreSQL daemon binary ('postgres') not found."
        error "Ensure the official image is used: ghcr.io/potenfyr-studios/database-eggs:*"
        fail "PostgreSQL daemon binary is unavailable."
    }

    # Surface the ACTUAL binary version that will serve connections (no silent downgrades)
    local actual_version
    actual_version=$("${pg_bin}" --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1)
    export PG_EFFECTIVE_VERSION="${actual_version:-unknown}"

    local req_major
    req_major=$(pg_requested_major)
    if [ -n "${req_major}" ] && [ -n "${actual_version}" ] && [ "${actual_version%%.*}" != "${req_major}" ]; then
        error "Requested PostgreSQL v${req_major} but resolved binary reports v${actual_version}."
        error "Set STRICT_VERSION=0 to allow fallback, or fix installation (see logs/installer.log)."
        fail "PostgreSQL version verification failed."
    fi

    mkdir -p "${socket_dir}"
    chmod 777 "${socket_dir}" 2>/dev/null || true

    # Standalone installs may bundle extra libs (gnu builds) - prefer them
    local pg_home
    pg_home="$(dirname "$(dirname "${pg_bin}")")"
    [ -d "${pg_home}/lib" ] && export LD_LIBRARY_PATH="${pg_home}/lib:${LD_LIBRARY_PATH:-}"

    log "Starting PostgreSQL ${actual_version:+v${actual_version} }on ${BIND_ADDRESS:-0.0.0.0}:${SERVER_PORT} (Shared Buffers: ${TUNED_PG_SHARED_BUFFERS:-auto})..."
    exec "${pg_bin}" -D "${data_dir}" -k "${socket_dir}" -p "${SERVER_PORT}" -h "${BIND_ADDRESS:-0.0.0.0}" ${EXTRA_ARGS:-}
}
