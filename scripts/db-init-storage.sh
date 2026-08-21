#!/usr/bin/env bash
# =============================================================================
#  PotenFYR Studios - Storage, Backend & Analytical Handler (PocketBase, MinIO, InfluxDB, ClickHouse, VictoriaMetrics, Neo4j, CouchDB)
# =============================================================================

set -euo pipefail

init_storage_family() {
    local data_dir="${DATA_DIR:-${SERVER_DIR}/data}"
    mkdir -p "${data_dir}" "${SERVER_DIR}/logs"
}

start_storage_family() {
    local data_dir="${DATA_DIR:-${SERVER_DIR}/data}"

    case "${PROJECT_TYPE}" in
        pocketbase)
            log "Starting PocketBase on 0.0.0.0:${SERVER_PORT}..."
            local pb_bin="./pocketbase"
            command -v pocketbase >/dev/null 2>&1 && pb_bin="pocketbase"
            exec "${pb_bin}" serve --http="0.0.0.0:${SERVER_PORT}" --dir="${data_dir}/pb_data" ${EXTRA_ARGS:-}
            ;;
        minio)
            local root_user="${MINIO_ROOT_USER:-${DB_USER:-admin}}"
            local root_pass="${MINIO_ROOT_PASSWORD:-${DB_ROOT_PASSWORD:-${DB_PASSWORD}}}"
            export MINIO_ROOT_USER="${root_user}"
            export MINIO_ROOT_PASSWORD="${root_pass}"
            local console_port="${CONSOLE_PORT:-$((SERVER_PORT + 1))}"

            log "Starting MinIO S3 Object Storage on 0.0.0.0:${SERVER_PORT} (Console: :${console_port})..."
            exec minio server "${data_dir}" --address "0.0.0.0:${SERVER_PORT}" --console-address "0.0.0.0:${console_port}" ${EXTRA_ARGS:-}
            ;;
        influxdb)
            log "Starting InfluxDB on 0.0.0.0:${SERVER_PORT}..."
            export INFLUXD_BOLT_PATH="${data_dir}/influxd.bolt"
            export INFLUXD_ENGINE_PATH="${data_dir}/engine"
            export INFLUXD_HTTP_BIND_ADDRESS="0.0.0.0:${SERVER_PORT}"
            exec influxd ${EXTRA_ARGS:-}
            ;;
        clickhouse)
            log "Starting ClickHouse Server on 0.0.0.0:${SERVER_PORT}..."
            exec clickhouse-server --config-file="${SERVER_DIR}/config/clickhouse.xml" ${EXTRA_ARGS:-}
            ;;
        victoriametrics)
            log "Starting VictoriaMetrics on 0.0.0.0:${SERVER_PORT}..."
            exec victoriametrics -storageDataPath="${data_dir}" -httpListenAddr="0.0.0.0:${SERVER_PORT}" ${EXTRA_ARGS:-}
            ;;
        couchdb)
            log "Starting Apache CouchDB on 0.0.0.0:${SERVER_PORT}..."
            export COUCHDB_USER="${DB_USER:-admin}"
            export COUCHDB_PASSWORD="${DB_PASSWORD:-${DB_ROOT_PASSWORD}}"
            exec couchdb ${EXTRA_ARGS:-}
            ;;
        neo4j)
            log "Starting Neo4j Graph Database on 0.0.0.0:${SERVER_PORT}..."
            export NEO4J_AUTH="${NEO4J_AUTH:-neo4j/${DB_ROOT_PASSWORD:-${DB_PASSWORD}}}"
            exec neo4j console ${EXTRA_ARGS:-}
            ;;
        *)
            fail "Unknown storage/analytical engine: ${PROJECT_TYPE}"
            ;;
    esac
}
