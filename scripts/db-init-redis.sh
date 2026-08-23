#!/usr/bin/env bash
# =============================================================================
#  PotenFYR Studios - In-Memory & Caching Engine Handler (Redis, Valkey, KeyDB, Dragonfly, Memcached)
#  Includes Performance Multi-Threading, Memory Tuning, and Security Isolation
#  Honors DB_VERSION: prefers exact binaries provisioned into bin/.
# =============================================================================

find_inmemory_bin() {
    local name="$1"
    local p
    for p in "${SERVER_DIR}/bin/${name}"; do
        [ -x "${p}" ] && { printf '%s' "${p}"; return 0; }
    done
    command -v "${name}" 2>/dev/null || return 1
}

init_redis_family() {
    local data_dir="${DATA_DIR:-${SERVER_DIR}/data}"
    local conf_dir="${SERVER_DIR}/config"
    local redis_conf="${conf_dir}/redis.conf"

    mkdir -p "${data_dir}" "${conf_dir}" "${SERVER_DIR}/logs"
    chmod 700 "${data_dir}" 2>/dev/null || true

    # Run dynamic performance auto-tuning
    if command -v tune_redis_family >/dev/null 2>&1; then
        tune_redis_family
    else
        export TUNED_REDIS_MAXMEMORY="${SERVER_MEMORY:-1024}mb"
        export TUNED_REDIS_IO_THREADS="2"
    fi

    if [ ! -f "${redis_conf}" ]; then
        log "Generating performance-tuned & hardened ${PROJECT_TYPE^^} configuration..."
        cat <<EOF > "${redis_conf}"
# PotenFYR Studios - In-Memory Engine Config
port ${SERVER_PORT}
bind 0.0.0.0
protected-mode no
daemonize no
logfile ""
dir ${data_dir}
pidfile ${SERVER_DIR}/redis.pid
databases ${REDIS_DATABASES:-16}

# Memory Optimization & Eviction
maxmemory ${TUNED_REDIS_MAXMEMORY}
maxmemory-policy ${MAXMEMORY_POLICY:-allkeys-lru}
maxmemory-samples 7

# Multi-Threading & I/O Performance
io-threads ${TUNED_REDIS_IO_THREADS}
io-threads-do-reads yes
tcp-backlog ${TUNED_REDIS_TCP_BACKLOG:-511}

# Memory fragmentation (auto on >=1GB boxes)
activedefrag ${TUNED_REDIS_ACTIVE_DEFRAG:-no}
active-defrag-ignore-bytes 100mb
active-defrag-threshold-lower 10
active-defrag-threshold-upper 100

# Non-Blocking Background Deletion (High Performance)
lazyfree-lazy-eviction yes
lazyfree-lazy-expire yes
lazyfree-lazy-server-del yes
replica-lazy-flush yes

# Persistence (RDB & AOF) - save cadence scaled to instance size
save 900 1
save 300 10
save 60 10000
dbfilename dump.rdb
appendonly ${ENABLE_AOF:-yes}
appendfilename "appendonly.aof"
appendfsync everysec
no-appendfsync-on-rewrite yes
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb

# Security & Authentication
${DB_PASSWORD:+requirepass ${DB_PASSWORD}}
${DB_ROOT_PASSWORD:+masterauth ${DB_ROOT_PASSWORD}}

# Security Hardening (Disable dangerous debugging commands in production)
rename-command DEBUG ""
EOF
        ok "Created performance-tuned ${redis_conf}"
    else
        sed -i "s/^port .*/port ${SERVER_PORT}/g" "${redis_conf}" 2>/dev/null || true
        sed -i "/^activedefrag/d" "${redis_conf}" 2>/dev/null || true
        sed -i "/^active-defrag/d" "${redis_conf}" 2>/dev/null || true
        if [ -n "${DB_PASSWORD:-}" ]; then
            if grep -q "^requirepass" "${redis_conf}"; then
                sed -i "s/^requirepass .*/requirepass ${DB_PASSWORD}/g" "${redis_conf}" 2>/dev/null || true
            else
                echo "requirepass ${DB_PASSWORD}" >> "${redis_conf}"
            fi
        fi
    fi
}

start_redis_family() {
    local conf_dir="${SERVER_DIR}/config"
    local redis_conf="${conf_dir}/redis.conf"
    local data_dir="${DATA_DIR:-${SERVER_DIR}/data}"

    # Self-healing check: if configuration is missing, run init
    if [ ! -f "${redis_conf}" ]; then
        warn "Configuration missing. Initializing ${PROJECT_TYPE^^} config..."
        init_redis_family
    fi

    case "${PROJECT_TYPE}" in
        dragonfly)
            local df_bin
            df_bin=$(find_inmemory_bin "dragonfly") || {
                error "Dragonfly binary not found."
                fail "Dragonfly binary is unavailable."
            }
            local pw_arg=""
            [ -n "${DB_PASSWORD:-}" ] && pw_arg="--requirepass=${DB_PASSWORD}"
            local actual_version
            actual_version=$("${df_bin}" --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1)
            log "Starting Dragonfly ${actual_version:+v${actual_version} }on 0.0.0.0:${SERVER_PORT} (MaxMemory: ${TUNED_REDIS_MAXMEMORY:-${SERVER_MEMORY}MB})..."
            exec "${df_bin}" --port="${SERVER_PORT}" --dir="${data_dir}" --maxmemory="${TUNED_REDIS_MAXMEMORY:-${SERVER_MEMORY}MB}" ${pw_arg} ${EXTRA_ARGS:-}
            ;;
        keydb)
            local kd_bin
            kd_bin=$(find_inmemory_bin "keydb-server") || {
                error "KeyDB binary 'keydb-server' not found."
                fail "KeyDB binary is unavailable."
            }
            log "Starting KeyDB on 0.0.0.0:${SERVER_PORT} (Threads: ${TUNED_REDIS_IO_THREADS:-2})..."
            exec "${kd_bin}" "${redis_conf}" ${EXTRA_ARGS:-}
            ;;
        valkey)
            local vk_bin
            vk_bin=$(find_inmemory_bin "valkey-server") || {
                error "Valkey binary 'valkey-server' not found."
                fail "Valkey binary is unavailable."
            }
            log "Starting Valkey on 0.0.0.0:${SERVER_PORT}..."
            exec "${vk_bin}" "${redis_conf}" ${EXTRA_ARGS:-}
            ;;
        memcached)
            local mc_bin
            mc_bin=$(find_inmemory_bin "memcached") || {
                error "Memcached binary not found."
                fail "Memcached binary is unavailable."
            }
            log "Starting Memcached on 0.0.0.0:${SERVER_PORT}..."
            exec "${mc_bin}" -p "${SERVER_PORT}" -m "${SERVER_MEMORY:-1024}" -u "$(id -un 2>/dev/null || echo container)" ${EXTRA_ARGS:-}
            ;;
        *) # redis
            local rs_bin
            rs_bin=$(find_inmemory_bin "redis-server") || {
                error "Redis binary 'redis-server' not found."
                fail "Redis binary is unavailable."
            }
            local actual_version
            actual_version=$("${rs_bin}" --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1)
            log "Starting Redis ${actual_version:+v${actual_version} }on 0.0.0.0:${SERVER_PORT} (MaxMemory: ${TUNED_REDIS_MAXMEMORY:-auto}, IO Threads: ${TUNED_REDIS_IO_THREADS:-auto})..."
            exec "${rs_bin}" "${redis_conf}" ${EXTRA_ARGS:-}
            ;;
    esac
}
