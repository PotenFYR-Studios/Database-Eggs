#!/usr/bin/env bash
# =============================================================================
#  PotenFYR Studios - Storage, Backend & Analytical Handler (PocketBase, MinIO, InfluxDB, ClickHouse, VictoriaMetrics, Neo4j, CouchDB)
# =============================================================================

init_storage_family() {
    local data_dir="${DATA_DIR:-${SERVER_DIR}/data}"
    local conf_dir="${SERVER_DIR}/config"
    mkdir -p "${data_dir}" "${conf_dir}" "${SERVER_DIR}/logs"
    chmod 700 "${data_dir}" 2>/dev/null || true

    if [ "${PROJECT_TYPE}" = "clickhouse" ] && [ ! -f "${conf_dir}/clickhouse.xml" ]; then
        log "Generating ClickHouse server configuration..."
        cat <<EOF > "${conf_dir}/clickhouse.xml"
<clickhouse>
    <logger>
        <level>information</level>
        <log>${SERVER_DIR}/logs/clickhouse.log</log>
        <errorlog>${SERVER_DIR}/logs/clickhouse.err.log</errorlog>
        <size>100M</size>
        <count>5</count>
    </logger>
    <http_port>${SERVER_PORT}</http_port>
${TCP_PORT:+    <tcp_port>${TCP_PORT}</tcp_port>}
    <listen_host>0.0.0.0</listen_host>
    <max_connections>100</max_connections>
    <path>${data_dir}/</path>
    <tmp_path>${data_dir}/tmp/</tmp_path>
    <user_files_path>${data_dir}/user_files/</user_files_path>
    <users_config>${conf_dir}/users.xml</users_config>
</clickhouse>
EOF
        cat <<EOF > "${conf_dir}/users.xml"
<clickhouse>
    <users>
        <default>
            <password>${DB_PASSWORD:-${DB_ROOT_PASSWORD:-}}</password>
            <networks>
                <ip>::/0</ip>
            </networks>
            <profile>default</profile>
            <quota>default</quota>
        </default>
    </users>
    <profiles>
        <default />
    </profiles>
    <quotas>
        <default />
    </quotas>
</clickhouse>
EOF
        ok "Generated ClickHouse configuration."
    fi
}

stop_storage_family() {
    local pid="$1"
    case "${PROJECT_TYPE}" in
        neo4j)
            local nj_base="${SERVER_DIR}/opt/neo4j"
            if [ -x "${nj_base}/bin/neo4j" ]; then
                "${nj_base}/bin/neo4j" stop >/dev/null 2>&1 || true
            fi
            ;;
    esac

    if kill -0 "${pid}" 2>/dev/null; then
        kill -TERM "${pid}" 2>/dev/null || true
    fi
}

start_storage_family() {
    local data_dir="${DATA_DIR:-${SERVER_DIR}/data}"
    local conf_dir="${SERVER_DIR}/config"
    local daemon_pid=""

    # Self-healing check
    if [ ! -d "${data_dir}" ]; then
        init_storage_family
    fi

    case "${PROJECT_TYPE}" in
        pocketbase)
            local pb_bin="pocketbase"
            [ -x "${SERVER_DIR}/bin/pocketbase" ] && pb_bin="${SERVER_DIR}/bin/pocketbase"
            [ -x "${SERVER_DIR}/pocketbase" ] && pb_bin="${SERVER_DIR}/pocketbase"

            if ! command -v "${pb_bin}" >/dev/null 2>&1 && [ ! -x "${pb_bin}" ]; then
                error "PocketBase binary '${pb_bin}' not found in container PATH or bin/ directory."
                fail "PocketBase binary is unavailable."
            fi

            log "Starting PocketBase on 0.0.0.0:${SERVER_PORT}..."
            "${pb_bin}" serve --http="0.0.0.0:${SERVER_PORT}" --dir="${data_dir}/pb_data" ${EXTRA_ARGS:-} < /dev/null &
            daemon_pid=$!
            ;;
        minio)
            local root_user="${MINIO_ROOT_USER:-${DB_USER:-admin}}"
            local root_pass="${MINIO_ROOT_PASSWORD:-${DB_ROOT_PASSWORD:-${DB_PASSWORD}}}"
            export MINIO_ROOT_USER="${root_user}"
            export MINIO_ROOT_PASSWORD="${root_pass}"
            local console_port="${CONSOLE_PORT:-}"
            local console_arg=""
            if [ -n "${console_port}" ]; then
                console_arg="--console-address 0.0.0.0:${console_port}"
            else
                console_arg="--console-address 127.0.0.1:$((SERVER_PORT + 1))"
            fi

            local minio_bin="minio"
            [ -x "${SERVER_DIR}/bin/minio" ] && minio_bin="${SERVER_DIR}/bin/minio"
            [ -x "${SERVER_DIR}/minio" ] && minio_bin="${SERVER_DIR}/minio"

            if ! command -v "${minio_bin}" >/dev/null 2>&1 && [ ! -x "${minio_bin}" ]; then
                error "MinIO binary '${minio_bin}' not found in container PATH or bin/ directory."
                fail "MinIO binary is unavailable."
            fi

            log "Starting MinIO S3 on 0.0.0.0:${SERVER_PORT} (Console: ${console_port:+0.0.0.0:}${console_port:-loopback:$((SERVER_PORT + 1))})..."
            "${minio_bin}" server "${data_dir}" --address "0.0.0.0:${SERVER_PORT}" ${console_arg} ${EXTRA_ARGS:-} < /dev/null &
            daemon_pid=$!
            ;;
        influxdb)
            local influx_bin="${SERVER_DIR}/bin/influxd"
            [ -x "${influx_bin}" ] || influx_bin="$(command -v influxd 2>/dev/null || true)"
            if [ -z "${influx_bin}" ] || [ ! -x "${influx_bin}" ]; then
                error "InfluxDB binary 'influxd' not found."
                fail "InfluxDB binary is unavailable."
            fi
            mkdir -p "${data_dir}"
            log "Starting InfluxDB on 0.0.0.0:${SERVER_PORT}..."
            export INFLUXD_BOLT_PATH="${data_dir}/influxd.bolt"
            export INFLUXD_ENGINE_PATH="${data_dir}/engine"
            export INFLUXD_HTTP_BIND_ADDRESS="0.0.0.0:${SERVER_PORT}"
            "${influx_bin}" ${EXTRA_ARGS:-} < /dev/null &
            daemon_pid=$!
            ;;
        clickhouse)
            local ch_bin="${SERVER_DIR}/bin/clickhouse"
            if [ ! -x "${ch_bin}" ]; then
                ch_bin="$(command -v clickhouse-server 2>/dev/null || true)"
                [ -n "${ch_bin}" ] || ch_bin="$(command -v clickhouse 2>/dev/null || true)"
            fi
            if [ -z "${ch_bin}" ] || [ ! -x "${ch_bin}" ]; then
                error "ClickHouse binary not found in PATH or bin/ directory."
                fail "ClickHouse binary is unavailable."
            fi
            if [ ! -f "${conf_dir}/clickhouse.xml" ]; then
                init_storage_family
            fi
            log "Starting ClickHouse Server on 0.0.0.0:${SERVER_PORT}..."
            "${ch_bin}" server --config-file="${conf_dir}/clickhouse.xml" ${EXTRA_ARGS:-} < /dev/null &
            daemon_pid=$!
            ;;
        victoriametrics)
            local vm_bin="victoriametrics"
            [ -x "${SERVER_DIR}/bin/victoriametrics" ] && vm_bin="${SERVER_DIR}/bin/victoriametrics"
            [ -x "${SERVER_DIR}/bin/victoria-metrics-prod" ] && vm_bin="${SERVER_DIR}/bin/victoria-metrics-prod"

            if ! command -v "${vm_bin}" >/dev/null 2>&1 && [ ! -x "${vm_bin}" ]; then
                error "VictoriaMetrics binary '${vm_bin}' not found in container PATH or bin/ directory."
                fail "VictoriaMetrics binary is unavailable."
            fi

            log "Starting VictoriaMetrics on 0.0.0.0:${SERVER_PORT}..."
            "${vm_bin}" -storageDataPath="${data_dir}" -httpListenAddr="0.0.0.0:${SERVER_PORT}" ${EXTRA_ARGS:-} < /dev/null &
            daemon_pid=$!
            ;;
        couchdb)
            if ! command -v couchdb >/dev/null 2>&1; then
                error "CouchDB binary 'couchdb' not found in container PATH."
                fail "CouchDB binary is unavailable."
            fi
            local cfg_arg=""
            [ -f "${conf_dir}/local.ini" ] && cfg_arg="${conf_dir}/local.ini"
            log "Starting Apache CouchDB on 0.0.0.0:${SERVER_PORT}..."
            export COUCHDB_USER="${DB_USER:-admin}"
            export COUCHDB_PASSWORD="${DB_PASSWORD:-${DB_ROOT_PASSWORD}}"
            couchdb ${cfg_arg} ${EXTRA_ARGS:-} < /dev/null &
            daemon_pid=$!
            ;;
        neo4j)
            local nj_base="${SERVER_DIR}/opt/neo4j"
            local neo4j_bin=""
            [ -x "${nj_base}/bin/neo4j" ] && neo4j_bin="${nj_base}/bin/neo4j"
            [ -z "${neo4j_bin}" ] && neo4j_bin="$(command -v neo4j 2>/dev/null || true)"
            if [ -z "${neo4j_bin}" ]; then
                error "Neo4j binary 'neo4j' not found (installer download failed?). See logs/installer.log"
                fail "Neo4j is unavailable."
            fi
            if [ -z "${JAVA_HOME:-}" ] && [ -x "${SERVER_DIR}/.runtimes/jdk17/bin/java" ]; then
                export JAVA_HOME="${SERVER_DIR}/.runtimes/jdk17"
                export PATH="${JAVA_HOME}/bin:${PATH}"
            fi
            export NEO4J_AUTH="${NEO4J_AUTH:-neo4j/${DB_ROOT_PASSWORD:-${DB_PASSWORD}}}"
            log "Starting Neo4j Graph Database (bolt on 0.0.0.0:${SERVER_PORT})..."
            cd "${nj_base}" 2>/dev/null || true
            env \
                NEO4J_server_bolt__listen__address="0.0.0.0:${SERVER_PORT}" \
                NEO4J_server_http__listen__address="127.0.0.1:${NEO4J_HTTP_PORT:-7474}" \
                NEO4J_server_default__listen__address="127.0.0.1" \
                "${neo4j_bin}" console ${EXTRA_ARGS:-} < /dev/null &
            daemon_pid=$!
            ;;
        questdb)
            local qd_base="${SERVER_DIR}/bin/questdb"
            [ -d "${qd_base}" ] || {
                error "QuestDB installation not found at ${qd_base}."
                fail "QuestDB is unavailable."
            }
            mkdir -p "${data_dir}"
            if [ ! -f "${qd_base}/conf/server.conf.potenfyr" ]; then
                cat <<EOF > "${qd_base}/conf/server.conf.potenfyr"
http.net.bind.to=0.0.0.0:${SERVER_PORT}
line.tcp.net.bind.to=127.0.0.1:${QUESTDB_LINE_PORT:-$((SERVER_PORT + 1))}
pg.net.bind.to=127.0.0.1:${QUESTDB_PG_PORT:-$((SERVER_PORT + 2))}
cairo.root=${data_dir}
cairo.sql.copy.root=${data_dir}/copy
shared.worker.count=2
line.default.partition.by=DAY
EOF
            fi
            cp -f "${qd_base}/conf/server.conf.potenfyr" "${qd_base}/conf/server.conf" 2>/dev/null || true
            local qd_java="${qd_base}/jdk/bin/java"
            [ -x "${qd_java}" ] || qd_java="$(command -v java 2>/dev/null || echo java)"
            log "Starting QuestDB on 0.0.0.0:${SERVER_PORT}..."
            cd "${qd_base}" 2>/dev/null || true
            "${qd_java}" $( [ -x "${qd_base}/jdk/bin/java" ] && echo "-XX:+UseG1GC" ) \
                -Dquestdb.server.conf.file="${qd_base}/conf/server.conf" \
                -cp "${qd_base}" io.questdb.ServerMain -d "${qd_base}" ${EXTRA_ARGS:-} < /dev/null &
            daemon_pid=$!
            ;;
        seaweedfs|weed)
            local weed_bin="${SERVER_DIR}/bin/weed"
            [ -x "${weed_bin}" ] || {
                error "SeaweedFS binary 'weed' unavailable."
                fail "SeaweedFS is unavailable."
            }
            mkdir -p "${data_dir}"
            local master_port="${SEAWEED_MASTER_PORT:-$((SERVER_PORT + 1))}" s3_port="${SEAWEED_S3_PORT:-$((SERVER_PORT + 2))}"
            log "Starting SeaweedFS (volume :${SERVER_PORT}, master :127.0.0.1:${master_port}${SEAWEED_S3_PORT:+, S3 :0.0.0.0:${s3_port}})..."
            "${weed_bin}" server \
                -dir="${data_dir}" \
                -ip="${INTERNAL_IP:-127.0.0.1}" \
                -ip.bind="${SEAWEED_BIND_IP:-0.0.0.0}" \
                -master.port="${master_port}" \
                -volume.port="${SERVER_PORT}" \
                ${SEAWEED_S3_PORT:+-s3.port="${s3_port}"} \
                -master.volumeSizeLimitMB="${SEAWEED_VOLUME_LIMIT_MB:-1024}" \
                ${EXTRA_ARGS:-} < /dev/null &
            daemon_pid=$!
            ;;
        garage)
            local garage_bin="${SERVER_DIR}/bin/garage"
            [ -x "${garage_bin}" ] || {
                error "Garage binary unavailable."
                fail "Garage is unavailable."
            }
            mkdir -p "${data_dir}/meta" "${data_dir}/data" "${SERVER_DIR}/run"
            local garage_conf="${SERVER_DIR}/config/garage.toml"
            cat <<EOF > "${garage_conf}"
metadata_dir = "${data_dir}/meta"
data_dir = "${data_dir}/data"
db_engine = "lmdb"

replication_factor = 1

rpc_bind_addr = "127.0.0.1:${GARAGE_RPC_PORT:-$((SERVER_PORT + 1))}"
rpc_public_addr = "127.0.0.1:${GARAGE_RPC_PORT:-$((SERVER_PORT + 1))}"
rpc_secret = "$(gen_rand 32 urlsafe 2>/dev/null || echo garage-rpc-$(date +%s))"

[s3_api]
s3_region = "${GARAGE_REGION:-us-east-1}"
api_bind_addr = "0.0.0.0:${SERVER_PORT}"

[s3_web]
bind_addr = "127.0.0.1:${GARAGE_WEB_PORT:-$((SERVER_PORT + 2))}"
root_domain = ".web.garage.localhost"

[admin]
api_bind_addr = "127.0.0.1:${GARAGE_ADMIN_PORT:-$((SERVER_PORT + 3))}"
EOF
            chmod 600 "${garage_conf}"
            log "Starting Garage S3 storage on 0.0.0.0:${SERVER_PORT}..."
            "${garage_bin}" -c "${garage_conf}" server ${EXTRA_ARGS:-} < /dev/null &
            daemon_pid=$!
            ;;
        *)
            fail "Unknown storage/analytical engine: ${PROJECT_TYPE}"
            ;;
    esac

    supervise_daemon "${daemon_pid}" "stop_storage_family"
}
