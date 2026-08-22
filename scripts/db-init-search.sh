#!/usr/bin/env bash
# =============================================================================
#  PotenFYR Studios - Search & Vector Engine Handler (Meilisearch, Typesense, Qdrant)
# =============================================================================

init_search_family() {
    local data_dir="${DATA_DIR:-${SERVER_DIR}/data}"
    mkdir -p "${data_dir}" "${SERVER_DIR}/logs"
    chmod 700 "${data_dir}" 2>/dev/null || true
}

start_search_family() {
    local data_dir="${DATA_DIR:-${SERVER_DIR}/data}"

    case "${PROJECT_TYPE}" in
        meilisearch)
            local master_key="${MASTER_KEY:-${DB_ROOT_PASSWORD:-${DB_PASSWORD}}}"
            local meili_bin="meilisearch"
            [ -x "${SERVER_DIR}/bin/meilisearch" ] && meili_bin="${SERVER_DIR}/bin/meilisearch"
            [ -x "${SERVER_DIR}/meilisearch" ] && meili_bin="${SERVER_DIR}/meilisearch"

            log "Starting Meilisearch on 0.0.0.0:${SERVER_PORT}..."
            exec "${meili_bin}" --http-addr "0.0.0.0:${SERVER_PORT}" \
                                --db-path "${data_dir}" \
                                --master-key "${master_key}" \
                                --env "${MEILI_ENV:-production}" ${EXTRA_ARGS:-}
            ;;
        typesense)
            local api_key="${TYPESENSE_API_KEY:-${DB_ROOT_PASSWORD:-${DB_PASSWORD}}}"
            local ts_bin="typesense-server"
            [ -x "${SERVER_DIR}/bin/typesense-server" ] && ts_bin="${SERVER_DIR}/bin/typesense-server"
            [ -x "${SERVER_DIR}/typesense-server" ] && ts_bin="${SERVER_DIR}/typesense-server"

            log "Starting Typesense on 0.0.0.0:${SERVER_PORT}..."
            exec "${ts_bin}" --data-dir="${data_dir}" \
                             --api-port="${SERVER_PORT}" \
                             --api-key="${api_key}" \
                             --enable-cors="${ENABLE_CORS:-true}" ${EXTRA_ARGS:-}
            ;;
        qdrant)
            local qdrant_bin="qdrant"
            [ -x "${SERVER_DIR}/bin/qdrant" ] && qdrant_bin="${SERVER_DIR}/bin/qdrant"
            [ -x "${SERVER_DIR}/qdrant" ] && qdrant_bin="${SERVER_DIR}/qdrant"

            log "Starting Qdrant Vector DB on 0.0.0.0:${SERVER_PORT}..."
            export QDRANT__SERVICE__HTTP_PORT="${SERVER_PORT}"
            export QDRANT__SERVICE__GRPC_PORT="${GRPC_PORT:-$((SERVER_PORT + 1))}"
            export QDRANT__STORAGE__STORAGE_PATH="${data_dir}"
            [ -n "${DB_PASSWORD:-}" ] && export QDRANT__SERVICE__API_KEY="${DB_PASSWORD}"
            exec "${qdrant_bin}" ${EXTRA_ARGS:-}
            ;;
        *)
            fail "Unknown search/vector engine: ${PROJECT_TYPE}"
            ;;
    esac
}
