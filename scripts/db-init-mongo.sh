#!/usr/bin/env bash
# =============================================================================
#  PotenFYR Studios - MongoDB & FerretDB Engine Handler
#  Includes WiredTiger Cache Optimization and Authentication Security
# =============================================================================

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
  journal:
    enabled: true
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
    fi

    # Check if first run
    local first_run=0
    if [ ! -d "${data_dir}/journal" ] && [ ! -f "${data_dir}/WiredTiger" ]; then
        first_run=1
        log "First run detected. Initializing MongoDB authentication..."

        # Start temporary mongod without auth bound strictly to local loopback
        mongod --port "${SERVER_PORT}" --dbpath "${data_dir}" --bind_ip 127.0.0.1 --logpath "${SERVER_DIR}/logs/mongod_init.log" --fork

        local retries=30
        while ! mongosh --port "${SERVER_PORT}" --eval "db.adminCommand('ping')" >/dev/null 2>&1 && [ "${retries}" -gt 0 ]; do
            sleep 1
            retries=$((retries - 1))
        done

        log "Creating admin superuser..."
        mongosh --port "${SERVER_PORT}" admin >/dev/null 2>&1 <<EOSCRIPT
db.createUser({
  user: "root",
  pwd: "${DB_ROOT_PASSWORD}",
  roles: [ { role: "root", db: "admin" } ]
});
EOSCRIPT
        ok "Created admin root user."

        # Create application database and user
        if [ -n "${DB_NAME:-}" ] && [ -n "${DB_USER:-}" ] && [ -n "${DB_PASSWORD:-}" ] && [ "${DB_USER}" != "root" ]; then
            mongosh --port "${SERVER_PORT}" -u "root" -p "${DB_ROOT_PASSWORD}" --authenticationDatabase "admin" "${DB_NAME}" >/dev/null 2>&1 <<EOSCRIPT
db.createUser({
  user: "${DB_USER}",
  pwd: "${DB_PASSWORD}",
  roles: [ { role: "readWrite", db: "${DB_NAME}" }, { role: "dbAdmin", db: "${DB_NAME}" } ]
});
EOSCRIPT
            ok "Created MongoDB user '${DB_USER}' with readWrite permissions on database '${DB_NAME}'"
        fi

        log "Shutting down temporary MongoDB instance..."
        mongosh --port "${SERVER_PORT}" -u "root" -p "${DB_ROOT_PASSWORD}" --authenticationDatabase "admin" --eval "db.adminCommand({shutdown: 1})" >/dev/null 2>&1 || true
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
        log "Starting FerretDB on 0.0.0.0:${SERVER_PORT}..."
        exec ferretdb --listen-addr="0.0.0.0:${SERVER_PORT}" \
                      --handler="${FERRETDB_HANDLER:-sqlite}" \
                      --sqlite-url="${data_dir}/" ${EXTRA_ARGS:-}
    else
        log "Starting MongoDB on 0.0.0.0:${SERVER_PORT} (WiredTiger Cache: ${TUNED_MONGO_CACHE_GB:-auto}GB)..."
        exec mongod --config "${mongod_conf}" ${EXTRA_ARGS:-}
    fi
}
