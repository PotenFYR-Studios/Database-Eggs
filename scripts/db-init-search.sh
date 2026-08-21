#!/usr/bin/env bash
# =============================================================================
#  PotenFYR Studios - Search & Vector Engine Handler (Meilisearch, Typesense, Qdrant)
# =============================================================================

set -euo pipefail

init_search_family() {
    local data_dir="${DATA_DIR:-${SERVER_DIR}/data}"
    mkdir -p "${data_dir}" "${SERVER_DIR}/logs"
}

start_search_family() {
    local data_dir="${DATA_DIR:-${SERVER_DIR}/data}"

    case "${PROJECT_TYPE}" in
        meilisearch)
            local master_key="${MASTER_KEY:-${DB_ROOT_PASSWORD:-${DB_PASSWORD}}}"
            log "Starting Meilisearch on 0.0.0.0:${SERVER_PORT}..."
            exec meilisearch --http-addr "0.0.0.0:${SERVER_PORT}" \
                             --db-path "${data_dir}" \
                             --master-key "${master_key}" \
                             --env "${MEILI_ENV:-production}" ${EXTRA_ARGS:-}
            ;;
        typesense)
            local api_key="${TYPESENSE_API_KEY:-${DB_ROOT_PASSWORD:-${DB_PASSWORD}}}"
            log "Starting Typesense on 0.0.0.0:${SERVER_PORT}..."
            exec typesense-server --data-dir="${data_dir}" \
                                  --api-port="${SERVER_PORT}" \
                                  --api-key="${api_key}" \
                                  --enable-cors="${ENABLE_CORS:-true}" ${EXTRA_ARGS:-}
            ;;
        qdrant)
            log "Starting Qdrant Vector DB on 0.0.0.0:${SERVER_PORT}..."
            export QDRANT__SERVICE__HTTP_PORT="${SERVER_PORT}"
            export QDRANT__SERVICE__GRPC_PORT="${GRPC_PORT:-$((SERVER_PORT + 1))}"
            export QDRANT__STORAGE__STORAGE_PATH="${data_dir}"
            [ -n "${DB_PASSWORD:-}" ] && export QDRANT__SERVICE__API_KEY="${DB_PASSWORD}"
            exec qdrant ${EXTRA_ARGS:-}
            ;;
        *)
            fail "Unknown search/vector engine: ${PROJECT_TYPE}"
            ;;
    esac
}
