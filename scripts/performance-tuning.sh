#!/usr/bin/env bash
# =============================================================================
#  PotenFYR Studios - Database Engine Dynamic Performance Auto-Tuning
#  Calculates optimal buffers, connection pools, and I/O settings based on
#  allocated container memory (SERVER_MEMORY) and CPU core count.
# =============================================================================

calculate_system_specs() {
    export MEM_TOTAL_MB="${SERVER_MEMORY:-1024}"
    local cores
    cores=$(nproc 2>/dev/null || echo 2)
    if [ "${cores}" -lt 1 ]; then
        cores=1
    fi
    export CPU_CORES="${cores}"
}

# --- MariaDB / MySQL Auto-Tuning --------------------------------------------
tune_mariadb_mysql() {
    calculate_system_specs
    local mem_mb="${MEM_TOTAL_MB}"

    # Allocate 60% of container memory to InnoDB Buffer Pool
    local pool_mb=$(( mem_mb * 60 / 100 ))
    if [ "${pool_mb}" -lt 64 ]; then pool_mb=64; fi

    # Log file size: 25% of buffer pool (min 32M, max 1024M)
    local log_file_mb=$(( pool_mb * 25 / 100 ))
    if [ "${log_file_mb}" -lt 32 ]; then log_file_mb=32; fi
    if [ "${log_file_mb}" -gt 1024 ]; then log_file_mb=1024; fi

    # Buffer pool instances (1 instance per 1024MB)
    local pool_instances=$(( pool_mb / 1024 ))
    if [ "${pool_instances}" -lt 1 ]; then pool_instances=1; fi

    # Max connections scaled by RAM
    local max_conn=150
    if [ "${mem_mb}" -ge 8192 ]; then
        max_conn=500
    elif [ "${mem_mb}" -ge 4096 ]; then
        max_conn=300
    elif [ "${mem_mb}" -ge 2048 ]; then
        max_conn=200
    elif [ "${mem_mb}" -lt 1024 ]; then
        max_conn=75
    fi

    export TUNED_INNODB_BUFFER_POOL="${pool_mb}M"
    export TUNED_INNODB_LOG_FILE_SIZE="${log_file_mb}M"
    export TUNED_INNODB_POOL_INSTANCES="${pool_instances}"
    export TUNED_MYSQL_MAX_CONN="${MAX_CONNECTIONS:-${max_conn}}"
    export TUNED_MYSQL_READ_IO_THREADS="${CPU_CORES}"
    export TUNED_MYSQL_WRITE_IO_THREADS="${CPU_CORES}"
}

# --- PostgreSQL Auto-Tuning (production cluster grade) -----------------------
tune_postgresql() {
    calculate_system_specs
    local mem_mb="${MEM_TOTAL_MB}"

    # shared_buffers: 25% of RAM
    local shared_buf_mb=$(( mem_mb * 25 / 100 ))
    if [ "${shared_buf_mb}" -lt 32 ]; then shared_buf_mb=32; fi

    # effective_cache_size: 75% of RAM (OS page cache estimate)
    local eff_cache_mb=$(( mem_mb * 75 / 100 ))
    if [ "${eff_cache_mb}" -lt 64 ]; then eff_cache_mb=64; fi

    # maintenance_work_mem: 10% of RAM (capped 1GB, floor 16MB)
    local maint_work_mb=$(( mem_mb * 10 / 100 ))
    if [ "${maint_work_mb}" -lt 16 ]; then maint_work_mb=16; fi
    if [ "${maint_work_mb}" -gt 1024 ]; then maint_work_mb=1024; fi

    # max_connections scaled by RAM
    local max_conn=100
    if [ "${mem_mb}" -ge 8192 ]; then max_conn=300;
    elif [ "${mem_mb}" -ge 4096 ]; then max_conn=200;
    elif [ "${mem_mb}" -lt 1024 ]; then max_conn=50; fi

    # work_mem: 25% of RAM spread across connections (per sort/hash node)
    local work_mem_mb=$(( (mem_mb * 25 / 100) / max_conn ))
    if [ "${work_mem_mb}" -lt 2 ]; then work_mem_mb=2; fi
    if [ "${work_mem_mb}" -gt 64 ]; then work_mem_mb=64; fi

    local workers=$(( CPU_CORES > 1 ? CPU_CORES / 2 : 1 ))
    local max_workers="${CPU_CORES}"
    local workers_per_gather=$(( workers > 4 ? 4 : workers ))

    # WAL sizing: 1/32 of RAM, clamped 256MB-4GB (checkpoint cadence)
    local wal_mb=$(( mem_mb / 32 ))
    if [ "${wal_mb}" -lt 256 ]; then wal_mb=256; fi
    if [ "${wal_mb}" -gt 4096 ]; then wal_mb=4096; fi

    # Autovacuum: scale workers with cores, naptime 30s, cost limit balanced
    local av_workers=$(( CPU_CORES > 6 ? 6 : CPU_CORES ))
    if [ "${av_workers}" -lt 2 ]; then av_workers=2; fi

    export TUNED_PG_SHARED_BUFFERS="${shared_buf_mb}MB"
    export TUNED_PG_EFFECTIVE_CACHE="${eff_cache_mb}MB"
    export TUNED_PG_MAINT_WORK_MEM="${maint_work_mb}MB"
    export TUNED_PG_WORK_MEM="${work_mem_mb}MB"
    export TUNED_PG_MAX_CONNECTIONS="${max_conn}"
    export TUNED_PG_WORKERS="${workers}"
    export TUNED_PG_MAX_WORKERS="${max_workers}"
    export TUNED_PG_WORKERS_PER_GATHER="${workers_per_gather}"
    export TUNED_PG_MIN_WAL="${wal_mb}MB"
    export TUNED_PG_MAX_WAL="$((wal_mb * 4))MB"
    export TUNED_PG_AV_WORKERS="${av_workers}"
    export TUNED_PG_AV_NAPTIME="30"
    export TUNED_PG_AV_COST="200"
}

# --- Redis / Valkey / KeyDB Auto-Tuning (production grade) -------------------
tune_redis_family() {
    calculate_system_specs
    local mem_mb="${MEM_TOTAL_MB}"

    # Leave 15% headroom for background saving, replication buffers and OS
    local redis_max_mem=$(( mem_mb * 85 / 100 ))
    if [ "${redis_max_mem}" -lt 32 ]; then redis_max_mem=32; fi

    local io_threads=$(( CPU_CORES > 4 ? 4 : CPU_CORES ))
    if [ "${io_threads}" -lt 1 ]; then io_threads=1; fi

    # TCP backlog scales with expected connection churn
    local tcp_backlog=511
    if [ "${mem_mb}" -ge 4096 ]; then tcp_backlog=2048; fi

    # Active defrag: enabled only with headroom (>=1GB), off on tiny boxes
    local defrag="${REDIS_ACTIVE_DEFRAG:-auto}"
    if [ "${defrag}" = "auto" ]; then
        if [ "${mem_mb}" -ge 1024 ]; then defrag="yes"; else defrag="no"; fi
    fi

    # Save frequency: relaxed on big instances (less fork pressure)
    local save_policy="900 1
300 10
60 10000"
    if [ "${mem_mb}" -ge 4096 ]; then
        save_policy="1800 10
600 100
120 10000"
    fi

    export TUNED_REDIS_MAXMEMORY="${redis_max_mem}mb"
    export TUNED_REDIS_IO_THREADS="${io_threads}"
    export TUNED_REDIS_TCP_BACKLOG="${tcp_backlog}"
    export TUNED_REDIS_ACTIVE_DEFRAG="${defrag}"
}

# --- MongoDB Auto-Tuning (production grade) ----------------------------------
tune_mongodb() {
    calculate_system_specs
    local mem_mb="${MEM_TOTAL_MB}"

    # WiredTiger cache: 50% of (RAM - 1GB headroom), min 0.25GB, max ~60GB
    local avail_mb=$(( mem_mb - 1024 ))
    if [ "${avail_mb}" -lt 256 ]; then avail_mb=256; fi
    local cache_gb=$(awk "BEGIN {printf \"%.2f\", (${avail_mb} * 0.5) / 1024}")

    export TUNED_MONGO_CACHE_GB="${cache_gb}"
}

# --- Host Kernel Tunables (best-effort; requires root, silent otherwise) -----
# Containers cannot change host kernel state unprivileged - we attempt only
# when root, and always print one clear guidance line when we cannot.
apply_host_tunables() {
    calculate_system_specs
    local can_sysctl=0
    if [ "$(id -u 2>/dev/null || echo 1)" = "0" ] && command -v sysctl >/dev/null 2>&1; then
        can_sysctl=1
    fi

    # 1) vm.overcommit_memory=1 - Redis fork() safety for RDB/AOF rewrites.
    #    REDIS_OVERCOMMIT_MEMORY=1 (default) attempts the sysctl when possible.
    if [ "${REDIS_OVERCOMMIT_MEMORY:-1}" = "1" ]; then
        if [ "${can_sysctl}" = "1" ]; then
            sysctl -qw vm.overcommit_memory=1 2>/dev/null \
                && ok "Host tunable applied: vm.overcommit_memory=1" \
                || warn "Could not set vm.overcommit_memory (host restriction)."
        else
            warn "Redis background-save safety: host should set vm.overcommit_memory=1 (needs root on the HOST: sysctl vm.overcommit_memory=1)."
        fi
    fi

    # 2) net.core.somaxconn - accept-queue depth for connection-heavy engines.
    if [ -n "${HOST_SOMAXCONN:-}" ] && [ "${HOST_SOMAXCONN}" != "0" ]; then
        if [ "${can_sysctl}" = "1" ]; then
            sysctl -qw net.core.somaxconn="${HOST_SOMAXCONN}" 2>/dev/null \
                && ok "Host tunable applied: net.core.somaxconn=${HOST_SOMAXCONN}" \
                || warn "Could not set net.core.somaxconn (host restriction)."
        else
            warn "For high-connection workloads the host should set net.core.somaxconn=${HOST_SOMAXCONN} (needs root on the HOST)."
        fi
    fi

    # 3) Transparent Huge Pages - THP causes latency spikes for Redis/Mongo.
    if [ "${HOST_DISABLE_THP:-1}" = "1" ]; then
        if [ -w /sys/kernel/mm/transparent_hugepage/enabled ] 2>/dev/null; then
            echo madvise > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null \
                && ok "Host tunable applied: THP=madvise" || true
        elif [ "${can_sysctl}" = "1" ]; then
            sysctl -qw vm.transparent_hugepages=madvise 2>/dev/null || true
        fi
    fi
}
