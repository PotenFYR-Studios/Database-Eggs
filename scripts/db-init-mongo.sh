#!/usr/bin/env bash
# =============================================================================
#  PotenFYR Studios - MongoDB & FerretDB Engine Handler
#  Includes WiredTiger Cache Optimization and Authentication Security
#  Honors DB_VERSION: prefers the exact mongod provisioned into bin/.
# =============================================================================

find_mongo_bin() { # find_mongo_bin <mongod|mongosh>
    local name="$1"
    local p
    for p in "${SERVER_DIR}/bin/${name}" "${SERVER_DIR}/.runtimes/bin/${name}"; do
        [ -x "${p}" ] && { printf '%s' "${p}"; return 0; }
    done
    command -v "${name}" 2>/dev/null || return 1
}

mongo_shell() { # returns shell command usable for provisioning (mongosh preferred)
    local sh_bin
    if sh_bin=$(find_mongo_bin "mongosh"); then printf '%s' "${sh_bin}"; return 0; fi
    if command -v mongo >/dev/null 2>&1; then command -v mongo; return 0; fi
    return 1
}

init_mongo_family() {
    local data_dir="${DATA_DIR:-${SERVER_DIR}/data}"
    local conf_dir="${SERVER_DIR}/config"
    local mongod_conf="${conf_dir}/mongod.conf"

    mkdir -p "${data_dir}" "${conf_dir}" "${SERVER_DIR}/logs"
    chmod 700 "${data_dir}" 2>/dev/null || true

    if [ "${PROJECT_TYPE}" = "ferretdb" ]; then
        return 0
    fi

    # Dynamic performance tuning for WiredTiger
    if command -v tune_mongodb >/dev/null 2>&1; then
        tune_mongodb
    else
        export TUNED_MONGO_CACHE_GB="0.5"
    fi

    # Generate mongod.conf if missing
    if [ ! -f "${mongod_conf}" ]; then
        log "Generating performance-tuned mongod.conf configuration..."
        cat <<EOF > "${mongod_conf}"
# PotenFYR Studios - MongoDB Configuration
net:
  port: ${SERVER_PORT}
  bindIp: 0.0.0.0
  maxIncomingConnections: 1000

storage:
  dbPath: ${data_dir}
  wiredTiger:
    engineConfig:
      cacheSizeGB: ${TUNED_MONGO_CACHE_GB}
      directoryForIndexes: true
    collectionConfig:
      blockCompressor: snappy
    indexConfig:
      prefixCompression: true

systemLog:
  destination: file
  path: ${SERVER_DIR}/logs/mongod.log
  logAppend: true

security:
  authorization: enabled
  javascriptEnabled: true
EOF
        ok "Created performance-tuned ${mongod_conf}"
    else
        sed -i "s/port: .*/port: ${SERVER_PORT}/g" "${mongod_conf}" 2>/dev/null || true
        # Migration: storage.journal.enabled was removed in MongoDB 6.1+
        sed -i '/^  journal:$/,/^    enabled: true$/d' "${mongod_conf}" 2>/dev/null || true
    fi

    # Check if first run
    local first_run=0
    if [ ! -d "${data_dir}/journal" ] && [ ! -f "${data_dir}/WiredTiger" ]; then
        first_run=1
        log "First run detected. Initializing MongoDB authentication..."

        local mongod_bin
        mongod_bin=$(find_mongo_bin "mongod") || {
            error "MongoDB daemon 'mongod' not found (installer failed?)."
            fail "'mongod' is unavailable."
        }

        local msh
        msh=$(mongo_shell) || {
            warn "No mongo shell available - skipping credential provisioning."
            warn "Provision manually later via EXTRA_RUNTIMES=mongosh."
            return 0
        }

        local init_log="${SERVER_DIR}/logs/mongod_init.log"
        # Start temporary mongod without auth bound strictly to local loopback
        "${mongod_bin}" --port "${SERVER_PORT}" --dbpath "${data_dir}" --bind_ip 127.0.0.1 --logpath "${init_log}" --fork >/dev/null 2>&1
        local fork_status=$?

        if [ ${fork_status} -ne 0 ]; then
            error "Failed to start temporary MongoDB initialization daemon."
            [ -f "${init_log}" ] && tail -n 25 "${init_log}" >&2
            fail "Fatal: MongoDB temporary initialization daemon failed to fork."
        fi

        local retries=30
        while ! "${msh}" --quiet --port "${SERVER_PORT}" --eval "db.adminCommand('ping')" >/dev/null 2>&1 && [ "${retries}" -gt 0 ]; do
            sleep 1
            retries=$((retries - 1))
        done

        if [ "${retries}" -le 0 ]; then
            error "Timed out waiting for temporary MongoDB daemon to respond."
            if [ -f "${init_log}" ]; then
                error "Recent mongod_init.log output:"
                tail -n 25 "${init_log}" >&2
            fi
            fail "Fatal: MongoDB initialization timeout."
        fi

        log "Creating admin superuser..."
        "${msh}" --quiet --port "${SERVER_PORT}" admin >/dev/null 2>&1 <<EOSCRIPT
db.createUser({
  user: "root",
  pwd: "${DB_ROOT_PASSWORD}",
  roles: [ { role: "root", db: "admin" } ]
});
EOSCRIPT
        ok "Created admin root user."

        # Create application database and user
        if [ -n "${DB_NAME:-}" ] && [ -n "${DB_USER:-}" ] && [ -n "${DB_PASSWORD:-}" ] && [ "${DB_USER}" != "root" ]; then
            "${msh}" --quiet --port "${SERVER_PORT}" -u "root" -p "${DB_ROOT_PASSWORD}" --authenticationDatabase "admin" "${DB_NAME}" >/dev/null 2>&1 <<EOSCRIPT
db.createUser({
  user: "${DB_USER}",
  pwd: "${DB_PASSWORD}",
  roles: [ { role: "readWrite", db: "${DB_NAME}" }, { role: "dbAdmin", db: "${DB_NAME}" } ]
});
EOSCRIPT
            ok "Created MongoDB user '${DB_USER}' with readWrite permissions on database '${DB_NAME}'"
        fi

        log "Shutting down temporary MongoDB instance..."
        "${msh}" --quiet --port "${SERVER_PORT}" -u "root" -p "${DB_ROOT_PASSWORD}" --authenticationDatabase "admin" --eval "db.adminCommand({shutdown: 1})" >/dev/null 2>&1 || true
        sleep 2
        ok "MongoDB authentication initialized successfully."
    fi
}

start_mongo_family() {
    local conf_dir="${SERVER_DIR}/config"
    local mongod_conf="${conf_dir}/mongod.conf"
    local data_dir="${DATA_DIR:-${SERVER_DIR}/data}"

    # Self-healing check: if configuration is missing, run init
    if [ ! -f "${mongod_conf}" ] && [ "${PROJECT_TYPE}" != "ferretdb" ]; then
        warn "MongoDB configuration missing. Initializing config..."
        init_mongo_family
    fi

    if [ "${PROJECT_TYPE}" = "ferretdb" ]; then
        local fdb_bin
        fdb_bin=$(find_mongo_bin "ferretdb") || {
            error "FerretDB binary not found in container."
            fail "FerretDB binary is unavailable."
        }
        log "Starting FerretDB on 0.0.0.0:${SERVER_PORT}..."
        exec "${fdb_bin}" --listen-addr="0.0.0.0:${SERVER_PORT}" \
                      --handler="${FERRETDB_HANDLER:-sqlite}" \
                      --sqlite-url="${data_dir}/" ${EXTRA_ARGS:-}
    else
        local mongod_bin
        mongod_bin=$(find_mongo_bin "mongod") || {
            error "MongoDB binary 'mongod' not found in container."
            fail "MongoDB daemon 'mongod' is unavailable."
        }
        local actual_version
        actual_version=$("${mongod_bin}" --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1)
        log "Starting MongoDB ${actual_version:+v${actual_version} }on 0.0.0.0:${SERVER_PORT} (WiredTiger Cache: ${TUNED_MONGO_CACHE_GB:-auto}GB)..."
        exec "${mongod_bin}" --config "${mongod_conf}" ${EXTRA_ARGS:-}
    fi
}
