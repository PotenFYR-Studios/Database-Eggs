#!/usr/bin/env bash
fail_count=0
for f in entrypoint.sh run.sh scripts/*.sh tests/*.sh; do
    [ -f "$f" ] || continue
    if ! bash -n "$f" 2>/tmp/synerr; then echo "SYNTAX FAIL: $f"; cat /tmp/synerr; fail_count=$((fail_count+1)); fi
done
echo "syntax failures: $fail_count"
# mongo floor smoke
bash -c '
source scripts/performance-tuning.sh
SERVER_MEMORY=1024 CPU_CORES=2 tune_mongodb
echo "mongo cache @1GB: $TUNED_MONGO_CACHE_GB (expect >= 0.25)"
SERVER_MEMORY=8192 CPU_CORES=8 tune_mongodb
echo "mongo cache @8GB: $TUNED_MONGO_CACHE_GB"
'
# redis conf gen smoke: system binary path must NOT emit activedefrag
bash -c '
export PROJECT_TYPE=redis SERVER_DIR=/tmp/rdtest SERVER_PORT=6399 DATA_DIR=/tmp/rdtest/data
source scripts/performance-tuning.sh
tune_redis_family
source scripts/db-init-redis.sh
init_redis_family
grep -c "^activedefrag" /tmp/rdtest/config/redis.conf || echo "no activedefrag (correct for system binary)"
grep -n "tcp-backlog" /tmp/rdtest/config/redis.conf
'
