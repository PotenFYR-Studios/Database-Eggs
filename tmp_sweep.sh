#!/usr/bin/env bash
fail_count=0
for f in entrypoint.sh run.sh scripts/*.sh tests/*.sh; do
    [ -f "$f" ] || continue
    if ! bash -n "$f" 2>/tmp/synerr; then echo "SYNTAX FAIL: $f"; cat /tmp/synerr; fail_count=$((fail_count+1)); fi
done
echo "syntax failures: $fail_count"
python3 -c "import json; d=json.load(open('egg-database-multi.json')); print('egg valid, vars:', len(d['variables']))"
# smoke: tuning math at 1024MB/4core
bash -c '
source scripts/performance-tuning.sh
SERVER_MEMORY=1024 CPU_CORES=4 tune_postgresql
echo "pg: sb=$TUNED_PG_SHARED_BUFFERS wal=$TUNED_PG_MIN_WAL-$TUNED_PG_MAX_WAL av=$TUNED_PG_AV_WORKERS"
SERVER_MEMORY=2048 CPU_CORES=4 tune_redis_family
echo "redis: max=$TUNED_REDIS_MAXMEMORY defrag=$TUNED_REDIS_ACTIVE_DEFRAG backlog=$TUNED_REDIS_TCP_BACKLOG"
'
