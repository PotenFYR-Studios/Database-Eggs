#!/usr/bin/env bash
# =============================================================================
#  PotenFYR Studios - SurrealDB & Multi-Model Engine Handler
# =============================================================================

set -euo pipefail

init_surreal_family() {
    local data_dir="${DATA_DIR:-${SERVER_DIR}/data}"
    mkdir -p "${data_dir}" "${SERVER_DIR}/logs"
}

start_surreal_family() {
    local data_dir="${DATA_DIR:-${SERVER_DIR}/data}"
    local storage="${SURREAL_STORAGE:-file://${data_dir}/surreal.db}"
    local user="${DB_USER:-${SURREAL_USER:-root}}"
    local pass="${DB_PASSWORD:-${DB_ROOT_PASSWORD:-${SURREAL_PASS:-root}}}"
    local log_level="${SURREAL_LOG:-info}"

    if [ "${PROJECT_TYPE}" = "rethinkdb" ]; then
        log "Starting RethinkDB on 0.0.0.0:${SERVER_PORT}..."
        exec rethinkdb --directory "${data_dir}" \
                       --bind all \
                       --driver-port "${SERVER_PORT}" \
                       --cluster-port "${CLUSTER_PORT:-29015}" \
                       --http-port "${WEB_PORT:-8080}" ${EXTRA_ARGS:-}
    fi

    log "Starting SurrealDB on 0.0.0.0:${SERVER_PORT}..."
    exec surreal start --bind "0.0.0.0:${SERVER_PORT}" \
                       --user "${user}" \
                       --pass "${pass}" \
                       --log "${log_level}" \
                       ${EXTRA_ARGS:-} \
                       "${storage}"
}
