#!/usr/bin/env bash
# =============================================================================
#  PotenFYR Studios - In-Memory & Caching Engine Handler (Redis, Valkey, KeyDB, Dragonfly, Memcached)
# =============================================================================

set -euo pipefail

init_redis_family() {
    local data_dir="${DATA_DIR:-${SERVER_DIR}/data}"
    local conf_dir="${SERVER_DIR}/config"
    local redis_conf="${conf_dir}/redis.conf"

    mkdir -p "${data_dir}" "${conf_dir}" "${SERVER_DIR}/logs"

    if [ ! -f "${redis_conf}" ]; then
        log "Generating optimized ${PROJECT_TYPE^^} configuration..."
        cat <<EOF > "${redis_conf}"
# PotenFYR Studios - In-Memory Engine Config
port ${SERVER_PORT}
bind 0.0.0.0
protected-mode no
dir ${data_dir}
pidfile ${SERVER_DIR}/redis.pid
logfile ${SERVER_DIR}/logs/redis.log
databases ${REDIS_DATABASES:-16}
maxmemory ${SERVER_MEMORY}mb
maxmemory-policy ${MAXMEMORY_POLICY:-allkeys-lru}

# Persistence (RDB & AOF)
save 900 1
save 300 10
save 60 10000
dbfilename dump.rdb
appendonly ${ENABLE_AOF:-yes}
appendfilename "appendonly.aof"
appendfsync everysec

# Security
${DB_PASSWORD:+requirepass ${DB_PASSWORD}}
${DB_ROOT_PASSWORD:+masterauth ${DB_ROOT_PASSWORD}}
EOF
        ok "Created ${redis_conf}"
    else
        # Update existing config with latest port and password if necessary
        sed -i "s/^port .*/port ${SERVER_PORT}/g" "${redis_conf}" 2>/dev/null || true
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
            log "Starting Dragonfly on 0.0.0.0:${SERVER_PORT}..."
            exec dragonfly --port="${SERVER_PORT}" --dir="${data_dir}" --maxmemory="${SERVER_MEMORY}MB" ${pw_arg} ${EXTRA_ARGS:-}
            ;;
        keydb)
            log "Starting KeyDB on 0.0.0.0:${SERVER_PORT}..."
            exec keydb-server "${redis_conf}" ${EXTRA_ARGS:-}
            ;;
        valkey)
            log "Starting Valkey on 0.0.0.0:${SERVER_PORT}..."
            exec valkey-server "${redis_conf}" ${EXTRA_ARGS:-}
            ;;
        memcached)
            log "Starting Memcached on 0.0.0.0:${SERVER_PORT}..."
            exec memcached -p "${SERVER_PORT}" -u container -m "${SERVER_MEMORY}" ${EXTRA_ARGS:-}
            ;;
        *) # redis
            log "Starting Redis on 0.0.0.0:${SERVER_PORT}..."
            exec redis-server "${redis_conf}" ${EXTRA_ARGS:-}
            ;;
    esac
}
