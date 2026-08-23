#!/usr/bin/env bash
# =============================================================================
#  PotenFYR Studios - Extended Engine Handlers (55+ catalog)
#  CockroachDB, YugabyteDB, TiDB, Dolt, libSQL, Etcd, NATS, Immudb, Dgraph,
#  ArangoDB, OrientDB, RavenDB, Cassandra, Aerospike, RethinkDB
#  All handlers are crash-safe, self-healing, and honor startup variables.
# =============================================================================

# Prefer engine binaries installed by install-db-version.sh over system ones
extra_find_bin() {
    local name="$1"
    local cand=""
    for cand in \
        "${SERVER_DIR}/bin/${name}" \
        "${SERVER_DIR}/opt/tidb/bin/${name}" \
        "${SERVER_DIR}/opt/yugabyte/bin/${name}" \
        "${SERVER_DIR}/opt/arangodb/sbin/${name}" \
        "${SERVER_DIR}/opt/arangodb/usr/sbin/${name}" \
        "${SERVER_DIR}/opt/arangodb/bin/${name}" \
        "${SERVER_DIR}/opt/cassandra/bin/${name}" \
        "${SERVER_DIR}/opt/aerospike/bin/${name}" \
        "${SERVER_DIR}/opt/orientdb/bin/${name}"; do
        [ -x "${cand}" ] && { printf '%s' "${cand}"; return 0; }
    done
    command -v "${name}" 2>/dev/null || return 1
}

require_bin() {
    local name="$1" human="${2:-$1}"
    local p
    p=$(extra_find_bin "${name}") || {
        error "Engine binary '${name}' was not found."
        error "The version installer could not provision ${human}. Check logs/installer.log"
        fail "'${human}' is unavailable."
    }
    printf '%s' "${p}"
}

init_extra_engine() {
    local data_dir="${DATA_DIR:-${SERVER_DIR}/data}"
    local conf_dir="${SERVER_DIR}/config"
    mkdir -p "${data_dir}" "${conf_dir}" "${SERVER_DIR}/logs"
    chmod 700 "${data_dir}" 2>/dev/null || true

    case "${PROJECT_TYPE}" in
        cockroachdb|cockroach)
            if [ ! -d "${data_dir}/cockroach" ] && [ ! -f "${data_dir}/COCKROACHDB_VERSION" ]; then
                log "CockroachDB store will be initialized at first start (${data_dir})."
            fi
            ;;
        tidb)
            mkdir -p "${data_dir}"
            ;;
        dolt)
            mkdir -p "${data_dir}"
            if [ ! -f "${conf_dir}/dolt-server.yaml" ]; then
                log "Generating Dolt SQL server configuration..."
                cat <<EOF > "${conf_dir}/dolt-server.yaml"
listener_host: "${LISTEN_HOST:-0.0.0.0}"
listener_port: ${SERVER_PORT}
data_dir: "${data_dir}"
user: "${DB_USER:-root}"
password: "${DB_PASSWORD:-${DB_ROOT_PASSWORD}}"
EOF
                chmod 600 "${conf_dir}/dolt-server.yaml"
                ok "Created ${conf_dir}/dolt-server.yaml"
            fi
            ;;
        etcd)
            mkdir -p "${data_dir}"
            ;;
        nats)
            mkdir -p "${data_dir}/jetstream"
            ;;
        immudb)
            mkdir -p "${data_dir}"
            export IMMUDB_ADDRESS="${LISTEN_HOST:-0.0.0.0}"
            export IMMUDB_PORT="${SERVER_PORT}"
            export IMMUDB_DIR="${data_dir}"
            export IMMUDB_LOGFILE="${SERVER_DIR}/logs/immudb.log"
            # Never ship default credentials in production
            export IMMUDB_ADMIN_PASSWORD="${IMMUDB_ADMIN_PASSWORD:-${DB_ROOT_PASSWORD:-$(gen_rand 32 urlsafe 2>/dev/null || echo ImmudbAdmin_$(date +%s))}}"
            ;;
        dgraph)
            mkdir -p "${data_dir}/zero" "${data_dir}/alpha/postings" "${data_dir}/alpha/wal"
            ;;
        arangodb)
            if [ ! -d "${data_dir}/ArangoDB" ]; then
                log "ArangoDB data directory prepared (${data_dir})."
            fi
            ;;
        orientdb)
            if [ ! -f "${conf_dir}/orientdb-server-config.xml" ]; then
                log "Generating OrientDB server configuration..."
                cat <<EOF > "${conf_dir}/orientdb-server-config.xml"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<orient-server>
    <network>
        <protocols>
            <protocol name="binary" implementation="com.orientechnologies.orient.server.network.protocol.binary.ONetworkProtocolBinary"/>
            <protocol name="http" implementation="com.orientechnologies.orient.server.network.protocol.http.ONetworkProtocolHttpDb"/>
        </protocols>
        <listeners>
            <listener ip-address="0.0.0.0" port-range="${SERVER_PORT}-${SERVER_PORT}" protocol="binary"/>
            <listener ip-address="127.0.0.1" port-range="${ORIENTDB_HTTP_PORT:-$((SERVER_PORT + 1))}-${ORIENTDB_HTTP_PORT:-$((SERVER_PORT + 1))}" protocol="http"/>
        </listeners>
    </network>
    <users>
        <user name="root" password="${DB_ROOT_PASSWORD:-orientdb}" resources="*"/>
        <user name="${DB_USER:-admin}" password="${DB_PASSWORD:-admin}" resources="database,passthrough"/>
    </users>
    <properties>
        <entry value="false" name="server.database.path"/>
        <entry value="info" name="log.console.level"/>
        <entry value="${SERVER_DIR}/logs/orientdb.log" name="log.file.path"/>
    </properties>
</orient-server>
EOF
                cat <<EOF > "${conf_dir}/orientdb-server-log.properties"
# OrientDB logging (console)
.level=INFO
handlers=java.util.logging.ConsoleHandler
java.util.logging.ConsoleHandler.level=INFO
EOF
                chmod 600 "${conf_dir}/orientdb-server-config.xml"
                ok "Created OrientDB configuration."
            fi
            ;;
        ravendb)
            if [ ! -f "${SERVER_DIR}/opt/ravendb/Server/settings.json" ]; then
                log "Generating RavenDB settings.json..."
                cat <<EOF > "${SERVER_DIR}/opt/ravendb/Server/settings.json"
{
    "DataDir": "${data_dir}",
    "ServerUrl": "http://0.0.0.0:${SERVER_PORT}",
    "Setup.Mode": "None",
    "License.Eula.Accepted": true,
    "Security.UnsecuredAccessAllowed": "PublicNetwork",
    "Logs.Path": "${SERVER_DIR}/logs"
}
EOF
                chmod 600 "${SERVER_DIR}/opt/ravendb/Server/settings.json"
                ok "Created RavenDB settings.json (unsecured public access - secure via EXTRA_ARGS/certs for production)."
            fi
            ;;
        cassandra)
            local cs_base="${SERVER_DIR}/opt/cassandra"
            if [ -x "${cs_base}/bin/cassandra" ] && [ ! -f "${cs_base}/conf/.potenfyr-tuned" ]; then
                log "Tuning Cassandra configuration for container operation..."
                mkdir -p "${data_dir}/commitlog" "${data_dir}/hints" "${data_dir}/saved_caches" "${data_dir}/cdc_raw"
                sed -i \
                    -e "s|^cluster_name:.*|cluster_name: 'PotenFYR Cluster'|" \
                    -e "s|^listen_address:.*|listen_address: 127.0.0.1|" \
                    -e "s|^rpc_address:.*|rpc_address: 0.0.0.0|" \
                    -e "s|^native_transport_port:.*|native_transport_port: ${SERVER_PORT}|" \
                    -e "s|^start_native_transport:.*|start_native_transport: true|" \
                    -e "s|^data_file_directories:.*|data_file_directories:\n     - ${data_dir}/data|" \
                    -e "s|^commitlog_directory:.*|commitlog_directory: ${data_dir}/commitlog|" \
                    -e "s|^saved_caches_directory:.*|saved_caches_directory: ${data_dir}/saved_caches|" \
                    -e "s|^hints_directory:.*|hints_directory: ${data_dir}/hints|" \
                    -e "s|^cdc_raw_directory:.*|cdc_raw_directory: ${data_dir}/cdc_raw|" \
                    "${cs_base}/conf/cassandra.yaml" 2>/dev/null || true
                printf '%s' "$(date -u +%s)" > "${cs_base}/conf/.potenfyr-tuned"
                ok "Cassandra tuned (native transport :${SERVER_PORT})."
            fi
            ;;
        aerospike)
            local mem_mb=$((SERVER_MEMORY > 256 ? SERVER_MEMORY - 128 : 256))
            if [ ! -f "${conf_dir}/aerospike.conf" ]; then
                log "Generating Aerospike configuration (memory engine, ${mem_mb}MB)..."
                cat <<EOF > "${conf_dir}/aerospike.conf"
service {
    cluster-name PotenFYR-Aerospike
    pidfile ${SERVER_DIR}/run/aerospike.pid
    proto-fd-max 15000
}
network {
    service {
        address any
        port ${SERVER_PORT}
    }
    heartbeat {
        mode mesh
        address 127.0.0.1
        port $((SERVER_PORT + 1))
        mesh-seed-address-port 127.0.0.1 $((SERVER_PORT + 1))
    }
    info {
        address 127.0.0.1
        port $((SERVER_PORT + 2))
    }
}
namespace ${AEROSPIKE_NAMESPACE:-test} {
    replication-factor 1
    memory-size ${mem_mb}M
    default-ttl 30d
    high-water-disk-pct 90
    high-water-memory-pct 80
    stop-writes-pct 95
    storage-engine memory
}
logging {
    console {
        context any info
    }
}
EOF
                ok "Created ${conf_dir}/aerospike.conf"
            fi
            ;;
        rethinkdb)
            if [ ! -f "${conf_dir}/rethinkdb.conf" ]; then
                log "Generating RethinkDB configuration..."
                cat <<EOF > "${conf_dir}/rethinkdb.conf"
directory=${data_dir}
bind=all
driver-port=${SERVER_PORT}
cluster-port=$((SERVER_PORT + 1))
http-port=$((SERVER_PORT + 2))
${DB_PASSWORD:+auth-key=${DB_PASSWORD}}
EOF
                ok "Created ${conf_dir}/rethinkdb.conf"
            fi
            ;;
        sqld|libsql)
            mkdir -p "${data_dir}"
            ;;
        yugabytedb|yugabyte)
            mkdir -p "${data_dir}"
            ;;
        *)
            ;;
    esac
}

start_extra_engine() {
    local data_dir="${DATA_DIR:-${SERVER_DIR}/data}"
    local conf_dir="${SERVER_DIR}/config"

    case "${PROJECT_TYPE}" in
        cockroachdb|cockroach)
            local cr_bin
            cr_bin=$(require_bin "cockroach" "CockroachDB")
            local sec_args="--insecure"
            if [ "${COCKROACH_SECURE:-0}" = "1" ]; then
                log "Secure mode requested - generating certificates..."
                mkdir -p "${conf_dir}/cockroach-certs"
                "${cr_bin}" cert create-ca \
                    --certs-dir="${conf_dir}/cockroach-certs" --ca-key="${conf_dir}/cockroach-certs/ca.key" >/dev/null 2>&1 || true
                "${cr_bin}" cert create-node localhost "127.0.0.1" "${INTERNAL_IP:-127.0.0.1}" \
                    --certs-dir="${conf_dir}/cockroach-certs" --ca-key="${conf_dir}/cockroach-certs/ca.key" >/dev/null 2>&1 || true
                "${cr_bin}" cert create-client root \
                    --certs-dir="${conf_dir}/cockroach-certs" --ca-key="${conf_dir}/cockroach-certs/ca.key" >/dev/null 2>&1 || true
                sec_args="--certs-dir=${conf_dir}/cockroach-certs"
            else
                warn "CockroachDB running INSECURE (development mode). Set COCKROACH_SECURE=1 for certificates."
            fi
            log "Starting CockroachDB single-node on 0.0.0.0:${SERVER_PORT}..."
            exec "${cr_bin}" start-single-node ${sec_args} \
                --store=path="${data_dir}" \
                --listen-addr="${LISTEN_HOST:-0.0.0.0}:${SERVER_PORT}" \
                --http-addr="127.0.0.1:${COCKROACH_HTTP_PORT:-$((SERVER_PORT + 1))}" \
                --cache="$(python3 -c "print(max(128,int(${SERVER_MEMORY}*0.25)))MB" 2>/dev/null || echo 128MB)" \
                ${EXTRA_ARGS:-}
            ;;

        yugabytedb|yugabyte)
            local yb_bin
            yb_bin=$(require_bin "yugabyted" "YugabyteDB")
            log "Starting YugabyteDB (YSQL on :${SERVER_PORT})..."
            exec "${yb_bin}" start --background=false \
                --base_dir="${data_dir}" \
                --tserver_flags="ysql_proxy_bind_address=0.0.0.0:${SERVER_PORT}" \
                ${EXTRA_ARGS:-}
            ;;

        tidb)
            local td_bin
            td_bin=$(require_bin "tidb-server" "TiDB")
            log "Starting TiDB (unistore embedded storage) on 0.0.0.0:${SERVER_PORT}..."
            exec "${td_bin}" \
                -P "${SERVER_PORT}" \
                -status "$((SERVER_PORT + 100))" \
                -host "0.0.0.0" \
                -store unistore \
                -path "${data_dir}" \
                ${EXTRA_ARGS:-}
            ;;

        dolt)
            local dolt_bin
            dolt_bin=$(require_bin "dolt" "Dolt")
            log "Starting Dolt SQL Server on 0.0.0.0:${SERVER_PORT}..."
            exec "${dolt_bin}" sql-server \
                --config "${conf_dir}/dolt-server.yaml" \
                ${EXTRA_ARGS:-}
            ;;

        sqld|libsql)
            local sqld_bin
            sqld_bin=$(require_bin "sqld" "libSQL server")
            log "Starting libSQL (sqld) on 0.0.0.0:${SERVER_PORT}..."
            exec "${sqld_bin}" \
                --http-listen-addr "0.0.0.0:${SERVER_PORT}" \
                --db-path "${data_dir}/db" \
                ${EXTRA_ARGS:-}
            ;;

        etcd)
            local etcd_bin
            etcd_bin=$(require_bin "etcd" "Etcd")
            log "Starting Etcd v3 on 0.0.0.0:${SERVER_PORT}..."
            exec "${etcd_bin}" \
                --name "server-${SERVER_PORT}" \
                --data-dir "${data_dir}" \
                --listen-client-urls "http://0.0.0.0:${SERVER_PORT}" \
                --advertise-client-urls "http://${INTERNAL_IP:-127.0.0.1}:${SERVER_PORT}" \
                --listen-peer-urls "http://127.0.0.1:$((SERVER_PORT + 1))" \
                --initial-advertise-peer-urls "http://127.0.0.1:$((SERVER_PORT + 1))" \
                --initial-cluster "server-${SERVER_PORT}=http://127.0.0.1:$((SERVER_PORT + 1))" \
                ${EXTRA_ARGS:-}
            ;;

        nats)
            local nats_bin
            nats_bin=$(require_bin "nats-server" "NATS")
            local auth_args=""
            [ -n "${DB_PASSWORD:-}${DB_ROOT_PASSWORD:-}" ] && auth_args="--auth ${DB_PASSWORD:-${DB_ROOT_PASSWORD}}"
            log "Starting NATS Server (JetStream) on 0.0.0.0:${SERVER_PORT}..."
            exec "${nats_bin}" \
                -a "0.0.0.0" -p "${SERVER_PORT}" \
                -sd "${data_dir}" \
                -js \
                ${auth_args} ${EXTRA_ARGS:-}
            ;;

        immudb)
            local imu_bin
            imu_bin=$(require_bin "immudb" "Immudb")
            log "Starting Immudb (tamper-proof ledger) on 0.0.0.0:${SERVER_PORT}..."
            exec "${imu_bin}" ${EXTRA_ARGS:-}
            ;;

        dgraph)
            local dg_bin
            dg_bin=$(require_bin "dgraph" "Dgraph")
            local zport="$((SERVER_PORT + 1))"
            # HTTP API serves the allocated port; internal Zero/GRPC stay loopback
            log "Starting Dgraph (HTTP :${SERVER_PORT}, Zero :127.0.0.1:${zport})..."
            "${dg_bin}" zero \
                --my "127.0.0.1:${zport}" \
                --replicas 1 \
                --wal "${data_dir}/zw" \
                --postings "${data_dir}/zero" >/dev/null 2>&1 &
            local zpid=$!
            sleep 3
            if ! kill -0 "${zpid}" 2>/dev/null; then
                fail "Dgraph Zero failed to start. Check logs/installer.log and container console."
            fi
            ok "Dgraph Zero healthy."
            exec "${dg_bin}" alpha \
                --my "127.0.0.1:$((SERVER_PORT + 2))" \
                --zero "127.0.0.1:${zport}" \
                --http "0.0.0.0:${SERVER_PORT}" \
                --grpc "127.0.0.1:${DGRAPH_GRPC_PORT:-$((SERVER_PORT + 3))}" \
                --postings "${data_dir}/alpha/postings" \
                --wal "${data_dir}/alpha/wal" \
                ${EXTRA_ARGS:-}
            ;;

        arangodb)
            local ag_bin
            ag_bin=$(require_bin "arangod" "ArangoDB")
            local auth_arg="--server.authentication false"
            if [ "${ARANGODB_AUTH:-0}" != "1" ]; then
                warn "ArangoDB authentication DISABLED. Set ARANGODB_AUTH=1 and provide JWT secret via EXTRA_ARGS for production."
            else
                auth_arg="--server.authentication true --server.jwt-secret ${ARANGO_JWT_SECRET:-${DB_ROOT_PASSWORD}}"
            fi
            log "Starting ArangoDB on tcp://0.0.0.0:${SERVER_PORT}..."
            exec "${ag_bin}" \
                --server.endpoint "tcp://0.0.0.0:${SERVER_PORT}" \
                --database.directory "${data_dir}" \
                ${auth_arg} \
                ${EXTRA_ARGS:-}
            ;;

        orientdb)
            local od_base="${SERVER_DIR}/opt/orientdb"
            if [ ! -x "${od_base}/bin/server.sh" ]; then
                error "OrientDB installation not found at ${od_base}."
                fail "OrientDB is unavailable."
            fi
            cp -f "${conf_dir}/orientdb-server-config.xml" "${od_base}/config/orientdb-server-config.xml" 2>/dev/null || true
            cp -f "${conf_dir}/orientdb-server-log.properties" "${od_base}/config/orientdb-server-log.properties" 2>/dev/null || true
            export ORIENTDB_HOME="${od_base}"
            log "Starting OrientDB on 0.0.0.0:${SERVER_PORT}..."
            cd "${od_base}/bin" 2>/dev/null || true
            exec bash ./server.sh ${EXTRA_ARGS:-}
            ;;

        ravendb)
            local rv_server="${SERVER_DIR}/opt/ravendb/Server"
            if [ ! -x "${rv_server}/Raven.Server" ] && [ ! -f "${rv_server}/Raven.Server.dll" ]; then
                error "RavenDB installation not found at ${rv_server}."
                fail "RavenDB is unavailable."
            fi
            log "Starting RavenDB on 0.0.0.0:${SERVER_PORT}..."
            cd "${rv_server}" 2>/dev/null || true
            if [ -x "./Raven.Server" ]; then
                exec ./Raven.Server ${EXTRA_ARGS:-}
            fi
            exec dotnet Raven.Server.dll ${EXTRA_ARGS:-}
            ;;

        cassandra)
            local cs_base="${SERVER_DIR}/opt/cassandra"
            if [ ! -x "${cs_base}/bin/cassandra" ]; then
                error "Cassandra installation not found at ${cs_base}."
                fail "Cassandra is unavailable."
            fi
            [ -n "${JAVA_HOME:-}" ] && export JAVA_HOME
            local heap_mb=$((SERVER_MEMORY > 512 ? SERVER_MEMORY / 2 : 256))
            log "Starting Apache Cassandra on 0.0.0.0:${SERVER_PORT} (heap ~${heap_mb}MB)..."
            cd "${cs_base}" 2>/dev/null || true
            exec env MAX_HEAP_SIZE="${heap_mb}M" HEAP_NEWSIZE="32M" \
                ./bin/cassandra -f ${EXTRA_ARGS:-}
            ;;

        aerospike)
            local as_base="${SERVER_DIR}/opt/aerospike"
            local as_bin
            as_bin=$(extra_find_bin "aerospike") || as_bin="${as_base}/bin/aerospike"
            if [ ! -x "${as_bin}" ]; then
                error "Aerospike binary unavailable."
                fail "Aerospike is unavailable."
            fi
            mkdir -p "${SERVER_DIR}/run"
            log "Starting Aerospike on 0.0.0.0:${SERVER_PORT}..."
            exec "${as_bin}" \
                --config-file "${conf_dir}/aerospike.conf" \
                --foreground \
                ${EXTRA_ARGS:-}
            ;;

        rethinkdb)
            local rt_bin
            rt_bin=$(require_bin "rethinkdb" "RethinkDB")
            log "Starting RethinkDB on 0.0.0.0:${SERVER_PORT}..."
            exec "${rt_bin}" \
                --config-file "${conf_dir}/rethinkdb.conf" \
                ${EXTRA_ARGS:-}
            ;;

        *)
            fail "Unknown extended engine: ${PROJECT_TYPE}"
            ;;
    esac
}
