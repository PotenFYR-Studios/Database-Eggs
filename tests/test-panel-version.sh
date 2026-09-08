#!/usr/bin/env bash
# Deterministic, offline opt-in version fallback and console-stop regression.
# Uses a cached Redis binary, not an assertion about upstream availability.
set -uo pipefail
IMAGE_NAME="${IMAGE_NAME:-database-eggs-panel-test:latest}"
name="pf-panel-version-$$"
cleanup() { docker rm -f "$name" >/dev/null 2>&1 || true; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

docker run -di --name "$name" --network none \
    -e DATABASE_TYPE=redis -e DB_VERSION=9.9.9 -e STRICT_VERSION=0 \
    -e SKIP_VERSION_INSTALL=1 -e SERVER_PORT=16384 -e AUTO_UPDATE_EGG=0 \
    -e DB_PASSWORD=PanelTestPassword -e DB_ROOT_PASSWORD=PanelRootPassword \
    "$IMAGE_NAME" >/dev/null || exit 1
ready=0
for ((i=0; i<30; i++)); do
    if docker exec "$name" redis-cli -p 16384 -a PanelTestPassword ping 2>/dev/null | grep -q '^PONG'; then
        ready=1; break
    fi
    [ "$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null)" = true ] || break
    sleep 1
done
[ "$ready" = 1 ] || { printf 'FAIL: offline fallback did not serve authenticated Redis\n'; exit 1; }
logs=$(docker logs "$name" 2>&1)
[[ "$logs" == *'STRICT_VERSION=0'* ]] || { printf 'FAIL: explicit fallback warning missing\n'; exit 1; }
printf 'PASS: opt-in fallback announced and authenticated PONG received\n'
# Attach only after readiness; otherwise startup may consume or miss stop input.
printf 'stop\n' | timeout --kill-after=2 15 docker attach --sig-proxy=false "$name" >/dev/null 2>&1 || true
for ((i=0; i<10; i++)); do
    [ "$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null)" = false ] && break
    sleep 1
done
[ "$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null)" = false ] || { printf 'FAIL: console stop did not stop container\n'; exit 1; }
[ "$(docker inspect -f '{{.State.ExitCode}}' "$name")" = 0 ] || { printf 'FAIL: nonzero exit after console stop\n'; exit 1; }
logs=$(docker logs "$name" 2>&1)
[[ "$logs" == *"Stop command 'stop' received via console"* ]] || { printf 'FAIL: stop watcher did not receive console command\n'; exit 1; }
printf 'PASS: console stop completed cleanly\n'
