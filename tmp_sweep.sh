#!/usr/bin/env bash
fail_count=0
for f in entrypoint.sh run.sh scripts/*.sh tests/*.sh; do
    [ -f "$f" ] || continue
    if ! bash -n "$f" 2>/tmp/synerr; then echo "SYNTAX FAIL: $f"; cat /tmp/synerr; fail_count=$((fail_count+1)); fi
done
echo "syntax failures: $fail_count"
grep -c "fallback_to_system" scripts/install-db-version.sh
grep -c "system-fallback" run.sh scripts/install-db-version.sh
