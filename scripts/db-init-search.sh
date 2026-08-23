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
        elasticsearch|opensearch)
            local engine_base flavor
            if [ "${PROJECT_TYPE}" = "opensearch" ]; then
                flavor="OpenSearch"; engine_base="${SERVER_DIR}/opt/opensearch"
            else
                flavor="Elasticsearch"; engine_base="${SERVER_DIR}/opt/elasticsearch"
            fi

            local es_bin=""
            [ -x "${engine_base}/bin/elasticsearch" ] && es_bin="${engine_base}/bin/elasticsearch"
            [ -x "${engine_base}/bin/opensearch" ] && es_bin="${engine_base}/bin/opensearch"
            [ -z "${es_bin}" ] && {
                error "${flavor} installation not found at ${engine_base}."
                fail "${flavor} is unavailable."
            }

            mkdir -p "${data_dir}" "${SERVER_DIR}/logs"

            log "Starting ${flavor} on 0.0.0.0:${SERVER_PORT}..."
            cd "${engine_base}" 2>/dev/null || true
            if [ "${PROJECT_TYPE}" = "opensearch" ]; then
                exec env OPENSEARCH_JAVA_HOME="${engine_base}/jdk" OPENSEARCH_PATH_CONF="${engine_base}/config" \
                    ./bin/opensearch \
                    -E "http.port=${SERVER_PORT}" \
                    -E "network.host=0.0.0.0" \
                    -E "discovery.type=single-node" \
                    -E "transport.host=127.0.0.1" \
                    -E "path.data=${data_dir}" \
                    -E "plugins.security.disabled=${OPENSEARCH_DISABLE_SECURITY:-true}" \
                    ${EXTRA_ARGS:-}
            else
                exec env ES_JAVA_HOME="${engine_base}/jdk" ES_PATH_CONF="${engine_base}/config" \
                    ./bin/elasticsearch \
                    -E "http.port=${SERVER_PORT}" \
                    -E "network.host=0.0.0.0" \
                    -E "discovery.type=single-node" \
                    -E "transport.host=127.0.0.1" \
                    -E "xpack.security.enabled=${ES_SECURITY_ENABLED:-false}" \
                    -E "path.data=${data_dir}" \
                    ${EXTRA_ARGS:-}
            fi
            ;;
        solr)
            local solr_base="${SERVER_DIR}/opt/solr"
            [ -x "${solr_base}/bin/solr" ] || {
                error "Solr installation not found at ${solr_base}."
                fail "Solr is unavailable."
            }
            [ -n "${JAVA_HOME:-}" ] && export JAVA_HOME
            mkdir -p "${data_dir}"
            log "Starting Solr on 0.0.0.0:${SERVER_PORT}..."
            cd "${solr_base}" 2>/dev/null || true
            exec ./bin/solr start -f \
                -p "${SERVER_PORT}" \
                -h "0.0.0.0" \
                -s "${data_dir}" \
                -m "${SOLR_HEAP:-${TUNED_SOLR_HEAP:-512m}}" \
                ${EXTRA_ARGS:-}
            ;;
        manticoresearch|manticore)
            local mc_bin="${SERVER_DIR}/bin/searchd"
            [ -x "${mc_bin}" ] || mc_bin="$(command -v searchd 2>/dev/null || true)"
            [ -n "${mc_bin}" ] && [ -x "${mc_bin}" ] || {
                error "Manticore 'searchd' binary unavailable."
                fail "Manticore Search is unavailable."
            }
            local mc_conf="${SERVER_DIR}/config/manticore.conf"
            if [ ! -f "${mc_conf}" ]; then
                log "Generating Manticore Search configuration..."
                cat <<EOF > "${mc_conf}"
searchd {
    listen = 0.0.0.0:${SERVER_PORT}
    listen = 127.0.0.1:${MANTICORE_MYSQL_PORT:-$((SERVER_PORT + 1))}:mysql41
    pid_file = ${SERVER_DIR}/run/manticore.pid
    log = ${SERVER_DIR}/logs/manticore.log
    query_log = ${SERVER_DIR}/logs/manticore_query.log
    data_dir = ${data_dir}
}
EOF
                ok "Created ${mc_conf}"
            fi
            mkdir -p "${SERVER_DIR}/run" "${data_dir}"
            log "Starting Manticore Search on 0.0.0.0:${SERVER_PORT}..."
            exec "${mc_bin}" --config "${mc_conf}" ${EXTRA_ARGS:-}
            ;;
        milvus)
            local mv_bin="${SERVER_DIR}/bin/milvus"
            [ -x "${mv_bin}" ] || mv_bin="$(command -v milvus 2>/dev/null || true)"
            [ -n "${mv_bin}" ] && [ -x "${mv_bin}" ] || {
                error "Milvus standalone binary unavailable (upstream ships Docker-first)."
                error "Use DATABASE_TYPE=custom with CUSTOM_DOWNLOAD_URL or the official Milvus image."
                fail "Milvus is unavailable."
            }
            mkdir -p "${data_dir}/etcd" "${data_dir}/milvus"
            log "Starting Milvus standalone on 0.0.0.0:${SERVER_PORT}..."
            exec env \
                ETCD_USE_EMBED="true" \
                ETCD_DATA_DIR="${data_dir}/etcd" \
                ETCD_CONFIG_PATH="" \
                COMMON_STORAGETYPE="local" \
                MILVUS_SERVER_PORT="${SERVER_PORT}" \
                "${mv_bin}" run standalone ${EXTRA_ARGS:-}
            ;;
        weaviate)
            local wv_bin="${SERVER_DIR}/bin/weaviate"
            [ -x "${wv_bin}" ] || wv_bin="$(command -v weaviate 2>/dev/null || true)"
            [ -n "${wv_bin}" ] && [ -x "${wv_bin}" ] || {
                error "Weaviate binary unavailable."
                fail "Weaviate is unavailable."
            }
            mkdir -p "${data_dir}"
            log "Starting Weaviate on 0.0.0.0:${SERVER_PORT}..."
            exec env \
                PERSISTENCE_DATA_PATH="${data_dir}" \
                AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED="${WEAVIATE_ANONYMOUS_ACCESS:-true}" \
                DEFAULT_VECTORIZER_MODULE="${WEAVIATE_VECTORIZER:-none}" \
                QUERY_DEFAULTS_LIMIT="${WEAVIATE_QUERY_LIMIT:-25}" \
                CLUSTER_HOSTNAME="node-${SERVER_PORT}" \
                ENABLE_MODULES="${WEAVIATE_MODULES:-}" \
                "${wv_bin}" \
                --port "${SERVER_PORT}" \
                --host "0.0.0.0" \
                ${EXTRA_ARGS:-}
            ;;
        quickwit)
            local qw_bin="${SERVER_DIR}/bin/quickwit"
            [ -x "${qw_bin}" ] || qw_bin="$(command -v quickwit 2>/dev/null || true)"
            [ -n "${qw_bin}" ] && [ -x "${qw_bin}" ] || {
                error "Quickwit binary unavailable."
                fail "Quickwit is unavailable."
            }
            mkdir -p "${data_dir}/qwdata"
            log "Starting Quickwit on 0.0.0.0:${SERVER_PORT}..."
            exec env \
                QW_DATA_DIR="${data_dir}/qwdata" \
                QW_LISTEN_ADDRESS="0.0.0.0" \
                QW_REST_LISTEN_PORT="${SERVER_PORT}" \
                QW_METASTORE_URI="${QUICKWIT_METASTORE_URI:-ram://}" \
                "${qw_bin}" run ${EXTRA_ARGS:-}
            ;;
        *)
            fail "Unknown search/vector engine: ${PROJECT_TYPE}"
            ;;
    esac
}
