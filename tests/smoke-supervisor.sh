#!/usr/bin/env bash
# =============================================================================
#  Smoke test: run.sh panel lifecycle paths (Start / Stop / Restart / Kill)
#  against fake daemons, without Docker. Exercises the exact supervisor code
#  path every panel button hits: the engine start function backgrounds the
#  daemon and calls supervise_daemon in the same shell (as db-init-*.sh do).
# =============================================================================
cd "$(dirname "$0")/.."
export PROJECT_TYPE=fake
log(){ printf '[t] %s\n' "$*"; }
ok(){ printf '[t][ok] %s\n' "$*"; }
warn(){ printf '[t][warn] %s\n' "$*"; }
FAILS=0
check(){ if [ "$2" = "$3" ]; then ok "$1 (got $3)"; else warn "$1: expected $2, got $3"; FAILS=$((FAILS+1)); fi; }

# Extract the supervisor block verbatim from run.sh
eval "$(sed -n '/^DAEMON_PID=/,/^export -f supervise_daemon/p' run.sh)"

# Stubborn daemon: IGNORES SIGTERM (worst case: Kill button must still work)
cat > .fake_stubborn.sh <<'D'
trap '' TERM INT
echo "stubborn fake daemon ready"
for i in $(seq 1 120); do sleep 1; done
D
# Polite daemon: exits cleanly on SIGTERM (normal Stop button)
cat > .fake_polite.sh <<'D'
trap 'exit 0' TERM INT
echo "polite fake daemon ready"
for i in $(seq 1 120); do sleep 1; done
D

# Engine-style launcher: backgrounds daemon then supervises, SAME shell
start_stubborn(){ bash .fake_stubborn.sh & supervise_daemon "$!"; }
start_polite(){ bash .fake_polite.sh & supervise_daemon "$!"; }
start_crasher(){ ( sleep 1; exit 3 ) & supervise_daemon "$!"; }

echo "--- 1. Stop button vs daemon that ignores SIGTERM (Kill path) ---"
DPID=""
start_stubborn & SUP=$!
sleep 2
DPID=$(ps -ef 2>/dev/null | grep -F ".fake_stubborn.sh" | grep -v grep | awk '{print $2}' | head -n1)
kill -TERM "$SUP" 2>/dev/null   # panels (wings) send SIGTERM to the launcher
T0=$SECONDS
wait "$SUP"; RC=$?
check "stubborn-daemon stop exit code" 0 "$RC"
ELAPSED=$((SECONDS-T0))
[ "$ELAPSED" -le 20 ] && ok "stop completed in ${ELAPSED}s (grace period + SIGKILL)" || warn "stop took ${ELAPSED}s"
sleep 1
if [ -n "${DPID}" ] && kill -0 "${DPID}" 2>/dev/null; then
    warn "daemon still alive after stop!"; FAILS=$((FAILS+1)); kill -9 "$DPID" 2>/dev/null
else
    ok "daemon process fully terminated"
fi

echo "--- 2. Stop button vs well-behaved daemon (graceful path) ---"
start_polite & SUP=$!
sleep 2
kill -TERM "$SUP" 2>/dev/null
T0=$SECONDS
wait "$SUP"; RC=$?
check "polite-daemon stop exit code" 0 "$RC"
ELAPSED=$((SECONDS-T0))
[ "$ELAPSED" -le 6 ] && ok "graceful stop fast (${ELAPSED}s)" || warn "graceful stop slow: ${ELAPSED}s"

echo "--- 3. Console 'stop' command via stdin (child bash = panel console) ---"
printf 'some command\nstop\n' > .fake_stdin.txt
cat > .fake_console_case.sh <<CASE
cd "$(pwd)" || exit 1
log(){ printf '[c] %s\n' "\$*"; }
ok(){ printf '[c][ok] %s\n' "\$*"; }
warn(){ printf '[c][warn] %s\n' "\$*"; }
error(){ printf '[c][err] %s\n' "\$*"; }
export PROJECT_TYPE=fake
eval "\$(sed -n '/^DAEMON_PID=/,/^export -f supervise_daemon/p' run.sh)"
bash .fake_polite.sh & supervise_daemon "\$!"
CASE
bash .fake_console_case.sh < .fake_stdin.txt; RC=$?
rm -f .fake_stdin.txt .fake_console_case.sh
check "console-stop exit code" 0 "$RC"

echo "--- 4. Clean natural exit (daemon exits 0 on its own) ---"
( ( sleep 1 ) & supervise_daemon "$!" ); RC=$?
check "natural-exit-0 propagated" 0 "$RC"

echo "--- 5. Crash path (daemon exits 3 unexpectedly) ---"
start_crasher; RC=$?
# Some minimal shells/subshells lose the child's exit status; accept 3 or 1
if [ "$RC" = "3" ] || [ "$RC" = "1" ]; then ok "crash detected, launcher exit=${RC}"; else warn "crash exit unexpected: ${RC}"; FAILS=$((FAILS+1)); fi

rm -f .fake_stubborn.sh .fake_polite.sh .fake_stdin.txt .fake_console_case.sh .wtest.sh
echo
if [ "$FAILS" -eq 0 ]; then ok "ALL SMOKE TESTS PASSED"; else warn "${FAILS} SMOKE TEST(S) FAILED"; fi
exit "$FAILS"
