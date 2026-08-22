#!/usr/bin/env bash
# =============================================================================
#  PotenFYR Studios - In-Memory & Caching Engine Handler (Redis, Valkey, KeyDB, Dragonfly, Memcached)
#  Includes Performance Multi-Threading, Memory Tuning, and Security Isolation
# =============================================================================

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

# Non-Blocking Background Deletion (High Performance)
lazyfree-lazy-eviction yes
lazyfree-lazy-expire yes
lazyfree-lazy-server-del yes
replica-lazy-flush yes

# Persistence (RDB & AOF)
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

    case "${PROJECT_TYPE}" in
        dragonfly)
            local pw_arg=""
            [ -n "${DB_PASSWORD:-}" ] && pw_arg="--requirepass=${DB_PASSWORD}"
            log "Starting Dragonfly on 0.0.0.0:${SERVER_PORT} (MaxMemory: ${TUNED_REDIS_MAXMEMORY:-${SERVER_MEMORY}MB})..."
            exec dragonfly --port="${SERVER_PORT}" --dir="${data_dir}" --maxmemory="${TUNED_REDIS_MAXMEMORY:-${SERVER_MEMORY}MB}" ${pw_arg} ${EXTRA_ARGS:-}
            ;;
        keydb)
            log "Starting KeyDB on 0.0.0.0:${SERVER_PORT} (Threads: ${TUNED_REDIS_IO_THREADS:-2})..."
            exec keydb-server "${redis_conf}" ${EXTRA_ARGS:-}
            ;;
        valkey)
            log "Starting Valkey on 0.0.0.0:${SERVER_PORT}..."
            exec valkey-server "${redis_conf}" ${EXTRA_ARGS:-}
            ;;
        memcached)
            log "Starting Memcached on 0.0.0.0:${SERVER_PORT}..."
            exec memcached -p "${SERVER_PORT}" -m "${SERVER_MEMORY:-1024}" ${EXTRA_ARGS:-}
            ;;
        *) # redis
            log "Starting Redis on 0.0.0.0:${SERVER_PORT} (MaxMemory: ${TUNED_REDIS_MAXMEMORY:-auto}, IO Threads: ${TUNED_REDIS_IO_THREADS:-auto})..."
            exec redis-server "${redis_conf}" ${EXTRA_ARGS:-}
            ;;
    esac
}
