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
            if [ -x "${SERVER_DIR}/bin/meilisearch" ]; then
                meili_bin="${SERVER_DIR}/bin/meilisearch"
            elif [ -x "${SERVER_DIR}/meilisearch" ]; then
                meili_bin="${SERVER_DIR}/meilisearch"
            elif [ -x "/usr/local/bin/meilisearch" ]; then
                meili_bin="/usr/local/bin/meilisearch"
            fi

            if ! command -v "${meili_bin}" >/dev/null 2>&1 && [ ! -x "${meili_bin}" ]; then
                error "Meilisearch binary '${meili_bin}' not found in container PATH or bin/ directory."
                fail "Meilisearch binary is unavailable."
            fi

            local cfg_arg=""
            [ -f "${SERVER_DIR}/config/meilisearch.toml" ] && cfg_arg="--config-file-path ${SERVER_DIR}/config/meilisearch.toml"

            log "Starting Meilisearch on 0.0.0.0:${SERVER_PORT}..."
            exec "${meili_bin}" --http-addr "0.0.0.0:${SERVER_PORT}" \
                                --db-path "${data_dir}" \
                                --master-key "${master_key}" \
                                --env "${MEILI_ENV:-production}" \
                                ${cfg_arg} ${EXTRA_ARGS:-}
            ;;
        typesense)
            local api_key="${TYPESENSE_API_KEY:-${DB_ROOT_PASSWORD:-${DB_PASSWORD}}}"
            local ts_bin="typesense-server"
            if [ -x "${SERVER_DIR}/bin/typesense-server" ]; then
                ts_bin="${SERVER_DIR}/bin/typesense-server"
            elif [ -x "${SERVER_DIR}/typesense-server" ]; then
                ts_bin="${SERVER_DIR}/typesense-server"
            elif [ -x "/usr/local/bin/typesense-server" ]; then
                ts_bin="/usr/local/bin/typesense-server"
            fi

            if ! command -v "${ts_bin}" >/dev/null 2>&1 && [ ! -x "${ts_bin}" ]; then
                error "Typesense binary '${ts_bin}' not found in container PATH or bin/ directory."
                fail "Typesense binary is unavailable."
            fi

            local cfg_arg=""
            [ -f "${SERVER_DIR}/config/typesense.ini" ] && cfg_arg="--config=${SERVER_DIR}/config/typesense.ini"

            log "Starting Typesense on 0.0.0.0:${SERVER_PORT}..."
            exec "${ts_bin}" --data-dir="${data_dir}" \
                             --api-port="${SERVER_PORT}" \
                             --api-key="${api_key}" \
                             --enable-cors="${ENABLE_CORS:-true}" \
                             ${cfg_arg} ${EXTRA_ARGS:-}
            ;;
        qdrant)
            local qdrant_bin="qdrant"
            if [ -x "${SERVER_DIR}/bin/qdrant" ]; then
                qdrant_bin="${SERVER_DIR}/bin/qdrant"
            elif [ -x "${SERVER_DIR}/qdrant" ]; then
                qdrant_bin="${SERVER_DIR}/qdrant"
            elif [ -x "/usr/local/bin/qdrant" ]; then
                qdrant_bin="/usr/local/bin/qdrant"
            fi

            if ! command -v "${qdrant_bin}" >/dev/null 2>&1 && [ ! -x "${qdrant_bin}" ]; then
                error "Qdrant binary '${qdrant_bin}' not found in container PATH or bin/ directory."
                fail "Qdrant binary is unavailable."
            fi

            local cfg_arg=""
            if [ -f "${SERVER_DIR}/config/config.yaml" ]; then
                cfg_arg="--config-path ${SERVER_DIR}/config/config.yaml"
            elif [ -f "${SERVER_DIR}/config.yaml" ]; then
                cfg_arg="--config-path ${SERVER_DIR}/config.yaml"
            fi

            log "Starting Qdrant Vector DB on 0.0.0.0:${SERVER_PORT}..."
            export QDRANT__SERVICE__HTTP_PORT="${SERVER_PORT}"
            export QDRANT__SERVICE__GRPC_PORT="${GRPC_PORT:-$((SERVER_PORT + 1))}"
            export QDRANT__STORAGE__STORAGE_PATH="${data_dir}"
            [ -n "${DB_PASSWORD:-}" ] && export QDRANT__SERVICE__API_KEY="${DB_PASSWORD}"
            exec "${qdrant_bin}" ${cfg_arg} ${EXTRA_ARGS:-}
            ;;
        *)
            fail "Unknown search/vector engine: ${PROJECT_TYPE}"
            ;;
    esac
}
