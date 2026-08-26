#!/usr/bin/env bash
# =============================================================================
#  PotenFYR Studios - SurrealDB & Multi-Model Engine Handler
# =============================================================================

init_surreal_family() {
    local data_dir="${DATA_DIR:-${SERVER_DIR}/data}"
    mkdir -p "${data_dir}" "${SERVER_DIR}/logs"
    chmod 700 "${data_dir}" 2>/dev/null || true
}

stop_surreal_family() {
    local pid="$1"
    if kill -0 "${pid}" 2>/dev/null; then
        kill -TERM "${pid}" 2>/dev/null || true
    fi
}

start_surreal_family() {
    local data_dir="${DATA_DIR:-${SERVER_DIR}/data}"
    local storage="${SURREAL_STORAGE:-surrealkv://${data_dir}}"
    # Automatically convert deprecated file:// storage scheme to modern surrealkv://
    storage="${storage/#file:\/\//surrealkv://}"

    local user="${DB_USER:-${SURREAL_USER:-root}}"
    local pass="${DB_PASSWORD:-${DB_ROOT_PASSWORD:-${SURREAL_PASS:-root}}}"
    local log_level="${SURREAL_LOG:-info}"

    local daemon_pid=""

    if [ "${PROJECT_TYPE}" = "rethinkdb" ]; then
        if ! command -v rethinkdb >/dev/null 2>&1; then
            error "RethinkDB binary not found in container PATH."
            fail "RethinkDB binary is unavailable."
        fi
        log "Starting RethinkDB on 0.0.0.0:${SERVER_PORT}..."
        rethinkdb --directory "${data_dir}" \
                  --bind all \
                  --driver-port "${SERVER_PORT}" \
                  --cluster-port "${CLUSTER_PORT:-29015}" \
                  --http-port "${WEB_PORT:-8080}" ${EXTRA_ARGS:-} < /dev/null &
        daemon_pid=$!
        supervise_daemon "${daemon_pid}" "stop_surreal_family"
        return 0
    fi

    local bin_cmd="surreal"
    [ -x "${SERVER_DIR}/bin/surreal" ] && bin_cmd="${SERVER_DIR}/bin/surreal"
    [ -x "${SERVER_DIR}/surreal" ] && bin_cmd="${SERVER_DIR}/surreal"

    if ! command -v "${bin_cmd}" >/dev/null 2>&1 && [ ! -x "${bin_cmd}" ]; then
        error "SurrealDB binary '${bin_cmd}' not found in container PATH or bin/ directory."
        fail "SurrealDB binary '${bin_cmd}' is unavailable."
    fi

    log "Starting SurrealDB on 0.0.0.0:${SERVER_PORT} (Storage: ${storage})..."
    "${bin_cmd}" start --bind "0.0.0.0:${SERVER_PORT}" \
                       --user "${user}" \
                       --pass "${pass}" \
                       --log "${log_level}" \
                       ${EXTRA_ARGS:-} \
                       "${storage}" < /dev/null &
    daemon_pid=$!
    supervise_daemon "${daemon_pid}" "stop_surreal_family"
}
