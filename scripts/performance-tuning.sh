#!/usr/bin/env bash
# =============================================================================
#  PotenFYR Studios - Database Engine Dynamic Performance Auto-Tuning
#  Calculates optimal buffers, connection pools, and I/O settings based on
#  allocated container memory (SERVER_MEMORY) and CPU core count.
# =============================================================================

set -euo pipefail

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

# --- PostgreSQL Auto-Tuning -------------------------------------------------
tune_postgresql() {
    calculate_system_specs
    local mem_mb="${MEM_TOTAL_MB}"

    # shared_buffers: 25% of RAM
    local shared_buf_mb=$(( mem_mb * 25 / 100 ))
    if [ "${shared_buf_mb}" -lt 32 ]; then shared_buf_mb=32; fi

    # effective_cache_size: 75% of RAM
    local eff_cache_mb=$(( mem_mb * 75 / 100 ))
    if [ "${eff_cache_mb}" -lt 64 ]; then eff_cache_mb=64; fi

    # maintenance_work_mem: 10% of RAM (capped at 512MB)
    local maint_work_mb=$(( mem_mb * 10 / 100 ))
    if [ "${maint_work_mb}" -lt 16 ]; then maint_work_mb=16; fi
    if [ "${maint_work_mb}" -gt 512 ]; then maint_work_mb=512; fi

    # max_connections
    local max_conn=100
    if [ "${mem_mb}" -ge 8192 ]; then max_conn=300;
    elif [ "${mem_mb}" -ge 4096 ]; then max_conn=200;
    elif [ "${mem_mb}" -lt 1024 ]; then max_conn=50; fi

    # work_mem: (25% of RAM) / max_connections
    local work_mem_mb=$(( (mem_mb * 25 / 100) / max_conn ))
    if [ "${work_mem_mb}" -lt 2 ]; then work_mem_mb=2; fi
    if [ "${work_mem_mb}" -gt 64 ]; then work_mem_mb=64; fi

    local workers=$(( CPU_CORES > 1 ? CPU_CORES / 2 : 1 ))

    export TUNED_PG_SHARED_BUFFERS="${shared_buf_mb}MB"
    export TUNED_PG_EFFECTIVE_CACHE="${eff_cache_mb}MB"
    export TUNED_PG_MAINT_WORK_MEM="${maint_work_mb}MB"
    export TUNED_PG_WORK_MEM="${work_mem_mb}MB"
    export TUNED_PG_MAX_CONNECTIONS="${max_conn}"
    export TUNED_PG_WORKERS="${workers}"
}

# --- Redis / Valkey / KeyDB Auto-Tuning --------------------------------------
tune_redis_family() {
    calculate_system_specs
    local mem_mb="${MEM_TOTAL_MB}"

    # Leave 15% headroom for background saving and OS
    local redis_max_mem=$(( mem_mb * 85 / 100 ))
    if [ "${redis_max_mem}" -lt 32 ]; then redis_max_mem=32; fi

    local io_threads=$(( CPU_CORES > 4 ? 4 : CPU_CORES ))
    if [ "${io_threads}" -lt 1 ]; then io_threads=1; fi

    export TUNED_REDIS_MAXMEMORY="${redis_max_mem}mb"
    export TUNED_REDIS_IO_THREADS="${io_threads}"
}

# --- MongoDB Auto-Tuning ----------------------------------------------------
tune_mongodb() {
    calculate_system_specs
    local mem_mb="${MEM_TOTAL_MB}"

    # WiredTiger cache: 50% of (RAM - 512MB), minimum 0.25GB
    local avail_mb=$(( mem_mb - 512 ))
    if [ "${avail_mb}" -lt 256 ]; then avail_mb=256; fi
    local cache_gb=$(awk "BEGIN {printf \"%.2f\", (${avail_mb} * 0.5) / 1024}")

    export TUNED_MONGO_CACHE_GB="${cache_gb}"
}
