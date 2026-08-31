#!/usr/bin/env bash
# =============================================================================
#  Panel-behavior test suite for Database Eggs.
#  Simulates the daemon lifecycle: start, stop (SIGTERM), kill (SIGKILL),
#  restart, console-text stop, Feather-style TTY stop, signal stop, orphan
#  sweep, crash journal, version-contract fallbacks, launcher isolation and
#  PANEL_STOP_WATCHER override - all under Pterodactyl-identical conditions
#  (uid 988, volume mounts, variable injection).
# =============================================================================
set -u
cd "$(dirname "$0")/.."

# Git Bash on Windows mangles POSIX paths in command args - disable that here.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"

IMG=database-eggs-panel-test
VOL=db-test-ws
PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

cleanup() {
    docker rm -f db-t1 db-t5c db-t7 db-t9 db-t11 db-cst >/dev/null 2>&1
    docker volume rm -f "$VOL" >/dev/null 2>&1
}
trap cleanup EXIT

echo "== building test image =="
if ! docker build -q -t "$IMG" -f tests/Dockerfile.test . >/dev/null 2>&1; then
    echo "docker build failed:"; docker build -t "$IMG" -f tests/Dockerfile.test . | tail -20; exit 1
fi
echo "  image ready"

# ---------------------------------------------------------------- T1: START
echo "== T1: start (panel env, redis 7.0 series) =="
docker rm -f db-t1 >/dev/null 2>&1; docker volume rm -f "$VOL" >/dev/null 2>&1
docker run -d --name db-t1 -v "$VOL:/home/container" \
    -e P_SERVER_UUID=11111111-2222-3333-4444-555555555555 \
    -e DATABASE_TYPE=redis -e DB_VERSION=7.0 \
    -e SERVER_PORT=16379 -e SERVER_MEMORY=512 -e AUTO_UPDATE_EGG=0 \
    -e DB_PASSWORD=TestPassword123!Secure -e DB_ROOT_PASSWORD=RootPassword123!Secure \
    "$IMG" >/dev/null
booted=0
for i in $(seq 1 90); do
    docker logs db-t1 2>&1 | grep -q "Ready to accept connections" && { booted=1; break; }
    sleep 1
done
[ "$booted" = "1" ] && ok "redis booted and listening on 16379" || { bad "redis never became ready"; docker logs db-t1 2>&1 | tail -40; }
docker logs db-t1 2>&1 | grep -aq "panel=pelican" && ok "panel family detected (Pelican via P_SERVER_UUID)" || { bad "panel detection"; docker logs db-t1 2>&1 | grep -aiE "panel" | head -3; }
docker logs db-t1 2>&1 | grep -q "database-eggs" && ok "agent theme active" || bad "theme prefix"
docker logs db-t1 2>&1 | grep -q "DATABASES\|Multi-Database" && ok "banner rendered" || bad "banner name"
docker exec db-t1 redis-cli -h 127.0.0.1 -p 16379 -a 'TestPassword123!Secure' ping 2>/dev/null | grep -q PONG \
    && ok "authenticated PONG response" || bad "redis not answering auth ping"
docker exec db-t1 grep -q "database-eggs" /home/container/.logs/console.log 2>/dev/null \
    && ok "console mirror .logs/console.log active" || bad "console mirror missing"
docker exec db-t1 grep -q "boot @" /home/container/.logs/console.log 2>/dev/null \
    && ok "boot header in mirror" || bad "boot header missing"
docker logs db-t1 2>&1 | grep -q "Detected Panel" && ok "boot card shows detected panel row" || bad "boot card panel row"

# ---------------------------------------------------------------- T2: STOP
echo "== T2: stop from panel (SIGTERM to PID 1) =="
t0=$(date +%s)
docker stop -t 25 db-t1 >/dev/null
t1=$(date +%s); elapsed=$((t1-t0))
[ "$elapsed" -lt 15 ] && ok "graceful stop in ${elapsed}s (<15s before daemon SIGKILL)" || bad "stop took ${elapsed}s"
docker logs db-t1 2>&1 | grep -q "Gracefully stopping\|Shutdown event" && ok "shutdown log line present" || bad "no shutdown log"
docker logs db-t1 2>&1 | grep -q "stopped cleanly" && ok "clean stop confirmation" || bad "no clean-stop confirmation"

# ---------------------------------------------------------------- T3: RESTART
echo "== T3: restart from panel (data instance reuse) =="
docker start db-t1 >/dev/null
restarted=0
for i in $(seq 1 90); do
    docker logs --since 120s db-t1 2>&1 | grep -q "Ready to accept connections" && { restarted=1; break; }
    sleep 1
done
[ "$restarted" = "1" ] && ok "redis restarted and ready again" || bad "restart failed"
docker exec db-t1 test -f /home/container/.logs/console.log.1 2>/dev/null \
    && ok "previous boot mirror rotated to console.log.1" || bad "mirror rotation"
docker kill db-t1 >/dev/null 2>&1; docker rm -f db-t1 >/dev/null 2>&1

# ------------------------------------------------------- T5: CONSOLE-TEXT STOP
echo "== T5: stop via console text (pipe stdin daemon) =="
out=$( (sleep 12; echo stop) | docker run -i --rm \
    -e DATABASE_TYPE=redis -e DB_VERSION=7.0 -e SERVER_PORT=16380 \
    -e DB_PASSWORD=TestPassword123!Secure -e DB_ROOT_PASSWORD=RootPassword123!Secure \
    -e AUTO_UPDATE_EGG=0 "$IMG" 2>&1 )
echo "$out" | grep -q "Stop command 'stop' received via console" \
    && ok "watcher caught console stop text" || bad "watcher missed stop text"
echo "$out" | grep -q "stopped cleanly" && ok "text-stop ended cleanly (exit 0)" || bad "text-stop exit"
echo "$out" | grep -q "Ready to accept connections" && ok "redis was serving before text-stop" || bad "redis never served in T5"

# ------------------------------------------- T5b: FEATHER-STYLE TTY TEXT STOP
echo "== T5b: stop via '^C' text on a TTY stdin (Feather Panel style) =="
tty_out=$(timeout 280 docker run -i --rm \
    -e DATABASE_TYPE=redis -e DB_VERSION=7.0 -e SERVER_PORT=16381 \
    -e DB_PASSWORD=TestPassword123!Secure -e DB_ROOT_PASSWORD=RootPassword123!Secure \
    -e AUTO_UPDATE_EGG=0 "$IMG" \
    python3 /t5b-driver.py 2>&1)
echo "$tty_out" | grep -aq "Stop command '\^C' received via console" \
    && ok "watcher caught '^C' text on TTY stdin" || { bad "watcher missed '^C' on tty"; echo "$tty_out" | tail -25; }
echo "$tty_out" | grep -aq "stopped cleanly" && ok "tty text-stop ended cleanly (exit 0)" || bad "tty text-stop exit"
echo "$tty_out" | grep -aq "Ready to accept connections" && ok "redis was serving before tty stop" || bad "redis never served in T5b"

# ---------------------------------------------------- T5c: SIGNAL STOP (SIGINT)
echo "== T5c: stop via SIGINT signal to PID 1 (daemon ContainerKill branch) =="
docker rm -f db-t5c >/dev/null 2>&1
docker run -d --name db-t5c -e DATABASE_TYPE=redis -e DB_VERSION=7.0 \
    -e SERVER_PORT=16382 -e DB_PASSWORD=TestPassword123!Secure \
    -e DB_ROOT_PASSWORD=RootPassword123!Secure -e AUTO_UPDATE_EGG=0 "$IMG" >/dev/null
sig_booted=0
for i in $(seq 1 60); do
    docker logs db-t5c 2>&1 | grep -q "Ready to accept connections" && { sig_booted=1; break; }
    sleep 1
done
[ "$sig_booted" = "1" ] && ok "redis booted before signal stop" || bad "redis never booted before signal stop"
docker kill --signal=SIGINT db-t5c >/dev/null 2>&1
sig_stopped=0
for i in $(seq 1 30); do
    state=$(docker inspect -f '{{.State.Running}}' db-t5c 2>/dev/null)
    [ "$state" = "false" ] && { sig_stopped=1; break; }
    sleep 1
done
[ "$sig_stopped" = "1" ] && ok "SIGINT to PID 1 stopped the container" || bad "container survived SIGINT"
[ "$(docker inspect -f '{{.State.ExitCode}}' db-t5c 2>/dev/null)" = "0" ] \
    && ok "SIGINT stop exit code 0" || bad "SIGINT stop exit code not 0"
docker logs db-t5c 2>&1 | grep -q "stopped cleanly" && ok "clean confirmation after SIGINT" || bad "no clean-stop confirmation"
docker rm -f db-t5c >/dev/null 2>&1

# --------------------------------------------------- T6: MULTI-PROCESS SWEEP
echo "== T6: orphan sweep (detached daemon alongside main process) =="
mp_out=$( (sleep 18; echo stop) | docker run -i --rm \
    -e DATABASE_TYPE=custom \
    -e CUSTOM_COMMAND="sh -c 'setsid python3 -m http.server 16390 >/dev/null 2>&1 </dev/null & exec python3 -m http.server 16391'" \
    -e SERVER_PORT=16391 -e AUTO_UPDATE_EGG=0 "$IMG" 2>&1 )
echo "$mp_out" | grep -q "stopped cleanly" && ok "clean stop with detached daemon present" || bad "stop not clean with daemon"
echo "$mp_out" | grep -qE "Swept [0-9]+ stray process" && ok "stray daemon swept on stop" || { bad "no stray sweep log"; echo "$mp_out" | grep -aiE "sweep|stray" | head -3; }

# ---------------------------------------------------------------- T7: JOURNAL
echo "== T7: failure journal (.logs/launcher-errors.log) =="
j_out=$(docker run --rm -v "$VOL:/home/container" \
    -e DATABASE_TYPE=notarealengine -e AUTO_UPDATE_EGG=0 -e SERVER_PORT=16383 "$IMG" 2>&1)
echo "$j_out" | grep -q "Unsupported database engine" && ok "unsupported engine surfaced" || bad "unsupported engine hidden"
sleep 1
docker run --rm -v "$VOL:/home/container" "$IMG" bash -c 'grep -q "notarealengine\|Unsupported" /home/container/.logs/launcher-errors.log 2>/dev/null' \
    && ok "failure recorded in .logs/launcher-errors.log" || bad "failure not journalled"

# ------------------------------------------- T8: VERSION-CONTRACT RESILIENCE
echo "== T8: pinned version that cannot be provisioned degrades loudly, never silently =="
v_out=$( (sleep 20; echo stop) | docker run -i --rm \
    -e DATABASE_TYPE=redis -e DB_VERSION=9.9.9 -e SERVER_PORT=16384 \
    -e DB_PASSWORD=TestPassword123!Secure -e DB_ROOT_PASSWORD=RootPassword123!Secure \
    -e AUTO_UPDATE_EGG=0 "$IMG" 2>&1 )
echo "$v_out" | grep -q "system-fallback\|could not be provisioned" \
    && ok "system fallback substitution announced" || bad "silent version substitution"
echo "$v_out" | grep -q "Ready to accept connections" && ok "server still boots under fallback" || bad "fallback broke boot"

# ------------------------------------------------- T9: FEATHER PANEL DETECTION
echo "== T9: Feather Panel detection (P_SERVER_UUID + P_SERVER_UUID_SHORT) =="
docker rm -f db-t9 >/dev/null 2>&1
docker run -d --name db-t9 \
    -e P_SERVER_UUID=530617d9-f5fa-411b-9fea-d2cf3c6286d4 -e P_SERVER_UUID_SHORT=530617d9 \
    -e DATABASE_TYPE=redis -e DB_VERSION=7.0 \
    -e SERVER_PORT=16385 -e DB_PASSWORD=TestPassword123!Secure \
    -e DB_ROOT_PASSWORD=RootPassword123!Secure -e AUTO_UPDATE_EGG=0 "$IMG" >/dev/null
fw_seen=0
card_seen=0
for i in $(seq 1 90); do
    docker logs db-t9 2>&1 | grep -aq "panel=feather" && fw_seen=1
    docker logs db-t9 2>&1 | grep -a "Detected Panel" | grep -aq "feather" && { card_seen=1; break; }
    sleep 1
done
[ "$fw_seen" = "1" ] && ok "Feather Panel detected via P_SERVER_UUID_SHORT" || { bad "panel detection (Feather)"; docker logs db-t9 2>&1 | grep -aiE "panel=" | head -3; }
[ "$card_seen" = "1" ] && ok "boot card shows Detected Panel: feather" || { bad "card Detected Panel"; docker logs db-t9 2>&1 | grep -a "Detected Panel" | head -2; }
docker rm -f db-t9 >/dev/null 2>&1

# ------------------------------------- T10: LAUNCHER FILE ISOLATION
echo "== T10: egg scripts isolated out of the user workspace =="
docker run --rm -v "$VOL:/home/container" "$IMG" bash -c '
    mkdir -p /home/container/.potenfyr
    cp /usr/local/bin/run.sh /home/container/.potenfyr/run.sh
    sha256sum /home/container/.potenfyr/run.sh | cut -d" " -f1 > /home/container/.potenfyr/launcher-hash
    echo "# PotenFYR Studios stray" > /home/container/run.sh
' >/dev/null 2>&1
iso_out=$(docker run --rm -v "$VOL:/home/container" \
    -e DATABASE_TYPE=redis -e DB_VERSION=7.0 -e AUTO_UPDATE_EGG=0 -e SERVER_PORT=16386 \
    -e DB_PASSWORD=TestPassword123!Secure -e DB_ROOT_PASSWORD=RootPassword123!Secure \
    "$IMG" bash -c 'timeout 40 bash /entrypoint.sh >/dev/null 2>&1
        echo "potenfyr-dir: $([ -d /home/container/.potenfyr ] && echo present || echo gone)"
        echo "stray-runsh: $([ -f /home/container/run.sh ] && echo present || echo gone)"
        echo done' 2>&1)
echo "$iso_out" | grep -aq "potenfyr-dir: gone" && ok ".potenfyr migrated out of user workspace" || bad ".potenfyr still in workspace"
echo "$iso_out" | grep -aq "stray-runsh: gone" && ok "stray egg launcher removed from workspace" || bad "stray egg launcher kept"

# ------------------------------------- T11: PANEL_STOP_WATCHER=0
echo "== T11: PANEL_STOP_WATCHER=0 keeps stdin exclusive =="
docker rm -f db-t11 >/dev/null 2>&1
docker run -d --name db-t11 \
    -e DATABASE_TYPE=redis -e DB_VERSION=7.0 -e SERVER_PORT=16387 \
    -e DB_PASSWORD=TestPassword123!Secure -e DB_ROOT_PASSWORD=RootPassword123!Secure \
    -e PANEL_STOP_WATCHER=0 -e AUTO_UPDATE_EGG=0 "$IMG" >/dev/null
w_booted=0
for i in $(seq 1 60); do
    docker logs db-t11 2>&1 | grep -q "Ready to accept connections" && { w_booted=1; break; }
    sleep 1
done
[ "$w_booted" = "1" ] && ok "redis booted with watcher disabled" || bad "boot failed with watcher disabled"
docker logs db-t11 2>&1 | grep -q "Stop command" && bad "watcher ran despite PANEL_STOP_WATCHER=0" || ok "watcher disabled (no stop-command log)"
docker rm -f db-t11 >/dev/null 2>&1

# ------------------------------------- T12: INVALID VERSION REJECTED
echo "== T12: invalid version input rejected with actionable error =="
iv_out=$(docker run --rm -e DATABASE_TYPE=redis -e DB_VERSION="not a version; rm -rf /" \
    -e AUTO_UPDATE_EGG=0 -e SERVER_PORT=16388 "$IMG" 2>&1)
echo "$iv_out" | grep -q "Invalid DB_VERSION" && ok "invalid DB_VERSION rejected" || bad "invalid version accepted"

echo
echo "=========================================="
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "=========================================="
[ "$FAIL" = "0" ]
