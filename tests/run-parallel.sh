#!/usr/bin/env bash
# =============================================================================
#  Unified test runner - parallel suite execution with a fast default mode.
#
#  Usage:
#    tests/run-parallel.sh                # fast mode (default)
#    tests/run-parallel.sh all            # everything
#    tests/run-parallel.sh <suite>...     # any of: syntax versions smoke
#                                         #         lifecycle users matrix
#
#  Suites:
#    syntax     bash -n over every shell script                 (seconds)
#    versions   resolver / suggestion / arch unit tests         (seconds)
#    smoke      supervisor lifecycle without Docker             (seconds)
#    lifecycle  panel behavior suite (fast Redis test image)    (~1 min)
#    users      multi-user engine (production image)            (~3 min)
#    matrix     engine startup matrix, PARALLEL by default      (~5 min)
#
#  Env knobs:
#    TEST_ENGINES="redis,mariadb"   matrix subset (fast cycles)
#    MAX_JOBS=4                     concurrent engine jobs in the matrix
#    SERIAL=1                       run suites one-by-one instead of parallel
# =============================================================================
set -u
cd "$(dirname "$0")/.." || exit 1

LOGDIR=$(mktemp -d)
trap 'rm -rf "$LOGDIR"' EXIT

SUITES_ALL=(syntax versions smoke lifecycle users matrix)
SUITES_FAST=(syntax versions smoke)

requested=("$@")
[ "${#requested[@]}" = "0" ] && requested=(fast)
case "${requested[0]}" in
    fast) selected=("${SUITES_FAST[@]}") ;;
    all)  selected=("${SUITES_ALL[@]}") ;;
    *)    selected=("${requested[@]}") ;;
esac

for s in "${selected[@]}"; do
    case "${s}" in syntax|versions|smoke|lifecycle|users|matrix) ;; *)
        echo "Unknown suite '${s}'. Valid: ${SUITES_ALL[*]} fast all"; exit 2 ;;
    esac
done

echo "== PotenFYR test runner: suites: ${selected[*]} (logs: ${LOGDIR}) =="

run_syntax() {
    local rc=0 f
    for f in entrypoint.sh run.sh run-scenario.sh scripts/*.sh tests/*.sh; do
        bash -n "$f" 2>>"$LOGDIR/syntax.log" || { echo "syntax error in $f"; rc=1; }
    done
    [ "$rc" = 0 ] && echo "all shell scripts parse cleanly"
    return "$rc"
}

run_suite() {
    case "$1" in
        syntax)    run_syntax ;;
        versions)  bash tests/test-versions.sh ;;
        smoke)     bash tests/smoke-supervisor.sh ;;
        lifecycle) bash tests/panel-test.sh ;;
        users)     bash tests/test-users.sh ;;
        matrix)    PARALLEL="${PARALLEL:-1}" MAX_JOBS="${MAX_JOBS:-4}" \
                   BUILD_IMAGE="${BUILD_IMAGE:-1}" bash tests/test-docker.sh ;;
    esac
}

declare -A RC=()
pids=()
for s in "${selected[@]}"; do
    if [ "${SERIAL:-0}" = "1" ]; then
        echo "--- suite: ${s} ---"
        run_suite "$s" >"$LOGDIR/${s}.log" 2>&1
        RC[$s]=$?
    else
        run_suite "$s" >"$LOGDIR/${s}.log" 2>&1 &
        pids+=("$s:$!")
    fi
done

if [ "${SERIAL:-0}" != "1" ]; then
    for entry in "${pids[@]}"; do
        s="${entry%%:*}"; pid="${entry##*:}"
        wait "$pid"; RC[$s]=$?
    done
fi

echo
echo "================= RESULTS ================="
overall=0
for s in "${selected[@]}"; do
    if [ "${RC[$s]:-1}" = "0" ]; then
        printf '  PASS  %-10s\n' "$s"
    else
        printf '  FAIL  %-10s  (tail of %s/%s.log)\n' "$s" "$LOGDIR" "$s"
        tail -n 25 "$LOGDIR/${s}.log" 2>/dev/null | sed 's/^/    /'
        overall=1
    fi
done
echo "==========================================="
exit "$overall"
