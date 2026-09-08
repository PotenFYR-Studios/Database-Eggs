#!/bin/bash
# =============================================================================
#  Multi-User Account Engine - Integration Tests (mariadb / postgresql / mongo)
#  Requires docker. Uses the full production image (RUNTIME_VARIANT=all layout).
#   IMAGE_NAME="database-eggs:test" ./tests/test-users.sh
#   SKIP_VERSION_INSTALL=1 MARIADB_VERSION=10.11 POSTGRESQL_VERSION=15 \
#       bash tests/test-users.sh mariadb postgresql
# Select via arguments or TEST_ENGINES (space/comma separated). Version knobs:
# MARIADB_VERSION, POSTGRESQL_VERSION, MONGODB_VERSION. READY_TIMEOUT is seconds.
# =============================================================================
set -u
cd "$(dirname "$0")/.." || exit 1

IMAGE_NAME="${IMAGE_NAME:-database-eggs:test}"
ROOTPW="RootPassword123!Secure"
PASS=0; FAILED=0
check() { # check <desc> <expected> <actual>
    if [ "$2" = "$3" ]; then PASS=$((PASS+1)); printf '[ok] PASS: %s\n' "$1";
    else FAILED=$((FAILED+1)); printf '[FAIL] %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2; fi
}
READY_TIMEOUT="${READY_TIMEOUT:-90}"
READY_INTERVAL="${READY_INTERVAL:-1}"
DOCKER_TIMEOUT="${DOCKER_TIMEOUT:-10}"
SKIP_VERSION_INSTALL="${SKIP_VERSION_INSTALL:-0}"
CONTAINERS=()
# Bound Docker itself, including exec probes whose clients can hang.
docker_bounded() { timeout --kill-after=2 "$DOCKER_TIMEOUT" docker "$@"; }
save_logs() {
    [ -n "${RESULT_DIR:-}" ] || return 0
    (umask 077; docker_bounded logs "$1" >> "$RESULT_DIR/$1.log" 2>&1) || true
}
cleanup() { save_logs "$1"; docker_bounded rm -f "$1" >/dev/null 2>&1 || true; }
cleanup_all() {
    local name
    for name in "${CONTAINERS[@]}"; do cleanup "$name"; done
    # Preserve private data/logs for diagnosis; never print credentials.
}
select_engines() {
    local engine
    ENGINES=" ${*:-${TEST_ENGINES:-mariadb postgresql mongodb}} "
    ENGINES="${ENGINES//,/ }"
    for engine in $ENGINES; do
        case "$engine" in mariadb|postgresql|mongodb) ;; *) echo "Unknown engine: $engine" >&2; return 1;; esac
    done
    [[ "$ENGINES" =~ [a-z] ]] || { echo 'No engines selected' >&2; return 1; }
}
selected() { [[ "$ENGINES" == *" $1 "* ]]; }

boot() { # boot <name> <volume> <engine> <port> <usernames> <passwords> [extra envs]
    local name="$1" vol="$2" engine="$3" port="$4" users="$5" pws="$6"; shift 6
    local version
    case "$engine" in
        mariadb) version="${MARIADB_VERSION:-latest}";;
        postgresql) version="${POSTGRESQL_VERSION:-16}";;
        mongodb) version="${MONGODB_VERSION:-7.0}";;
        *) return 1;;
    esac
    CONTAINERS+=("$name")
    cleanup "$name"
    docker_bounded run -d --name "$name" -u 988:988 -m 1024m \
        -e DATABASE_TYPE="$engine" -e DB_VERSION="$version" -e SKIP_VERSION_INSTALL="$SKIP_VERSION_INSTALL" \
        -e SERVER_PORT="$port" -e SERVER_MEMORY=1024 -e AUTO_UPDATE_EGG=0 \
        -e DB_NAME="database" -e DB_ROOT_PASSWORD="$ROOTPW" -e AUTO_GENERATE_CREDENTIALS=1 \
        -e DB_USERNAMES="$users" -e DB_PASSWORDS="$pws" "$@" \
        -v "$(cygpath -w "$vol" 2>/dev/null || echo "$vol"):/home/container" "$IMAGE_NAME" >/dev/null 2>&1 || { echo "FATAL: $engine container creation failed" >&2; exit 1; }
}

wait_ready() { # wait_ready <name> <ready-cmd> [timeout-seconds]
    local name="$1" cmd="$2" deadline=$((SECONDS + ${3:-$READY_TIMEOUT}))
    while (( SECONDS < deadline )); do
        [ "$(docker_bounded inspect -f '{{.State.Running}}' "$name" 2>/dev/null)" = true ] || {
            echo "FATAL: $name stopped before readiness" >&2; return 1;
        }
        docker_bounded exec "$name" bash -c "$cmd" >/dev/null 2>&1 && return 0
        sleep "$READY_INTERVAL"
    done
    echo "FATAL: $name readiness timed out" >&2
    return 1
}

select_engines "$@" || exit 2
for value in "$READY_TIMEOUT" "$DOCKER_TIMEOUT"; do
    [[ "$value" =~ ^[1-9][0-9]*$ ]] || { echo 'Timeouts must be positive integers' >&2; exit 2; }
done
[[ "$SKIP_VERSION_INSTALL" =~ ^[01]$ ]] || { echo 'SKIP_VERSION_INSTALL must be 0 or 1' >&2; exit 2; }
trap cleanup_all EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [ "$SKIP_VERSION_INSTALL" = 1 ]; then
    echo 'MODE: cached distro binaries only; NOT latest/pinned version verification'
fi
RESULT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/database-users.XXXXXXXX") || exit 1
echo "Private logs and data: $RESULT_DIR"
VOL="$RESULT_DIR/data"; mkdir "$VOL"; chmod 777 "$VOL" 2>/dev/null || true
# Git Bash/MSYS mangles colon-separated docker -v args into path lists; hand
# docker an explicit Windows path and exclude the args from conversion.
VOL_WIN="$(cygpath -w "$VOL" 2>/dev/null || echo "$VOL")"
export MSYS2_ARG_CONV_EXCL='*'

# ===========================================================================
if selected mariadb; then
echo "== M1: mariadb - invalid/reserved skipped, users + own dbs created =="
boot users-m1 "$VOL" mariadb 13306 "Alice, bob,char lie,root" "AlicePw1,bobpw"
wait_ready users-m1 "mysql -h 127.0.0.1 -P 13306 -u root -p'${ROOTPW}' -NBe 'SELECT 1'" || { echo "FATAL: mariadb never became ready (see private logs)"; exit 1; }
sleep 3
check "M1 alice auth" "1" "$(docker exec users-m1 bash -c "mysql -h 127.0.0.1 -P 13306 -u alice -p'AlicePw1' -NBe 'SELECT 1' 2>/dev/null | tail -1")"
check "M1 bob auth" "1" "$(docker exec users-m1 bash -c "mysql -h 127.0.0.1 -P 13306 -u bob -p'bobpw' -NBe 'SELECT 1' 2>/dev/null | tail -1")"
check "M1 alice_db exists" "alice_db" "$(docker exec users-m1 bash -c "mysql -h 127.0.0.1 -P 13306 -u root -p'${ROOTPW}' -NBe 'SHOW DATABASES LIKE \"alice_db\"' 2>/dev/null")"
check "M1 bob_db exists" "bob_db" "$(docker exec users-m1 bash -c "mysql -h 127.0.0.1 -P 13306 -u root -p'${ROOTPW}' -NBe 'SHOW DATABASES LIKE \"bob_db\"' 2>/dev/null")"
docker exec users-m1 bash -c "mysql -h 127.0.0.1 -P 13306 -u alice -p'AlicePw1' alice_db -e 'CREATE TABLE t1(id INT)' 2>/dev/null" && check "M1 alice owns alice_db (DDL)" "ok" "ok" || check "M1 alice owns alice_db (DDL)" "ok" "failed"
docker exec users-m1 bash -c "mysql -h 127.0.0.1 -P 13306 -u alice -p'AlicePw1' database -e 'CREATE TABLE shared1(id INT)' 2>/dev/null" && check "M1 alice writes shared db" "ok" "ok" || check "M1 alice writes shared db" "ok" "failed"
docker exec users-m1 bash -c "mysql -h 127.0.0.1 -P 13306 -u bob -p'bobpw' alice_db -e 'SELECT 1' 2>/dev/null" >/dev/null 2>&1
[ $? -ne 0 ] && check "M1 bob denied on alice_db" "ok" "ok" || check "M1 bob denied on alice_db" "ok" "leaked"

# ===========================================================================
echo "== M2: mariadb - restart adds dave with generated password, existing untouched =="
boot users-m1 "$VOL" mariadb 13306 "alice,bob,dave" ","
wait_ready users-m1 "mysql -h 127.0.0.1 -P 13306 -u root -p'${ROOTPW}' -NBe 'SELECT 1'" || { echo "FATAL: mariadb not ready on M2"; exit 1; }
sleep 3
check "M2 alice pw unchanged" "1" "$(docker exec users-m1 bash -c "mysql -h 127.0.0.1 -P 13306 -u alice -p'AlicePw1' -NBe 'SELECT 1' 2>/dev/null | tail -1")"
check "M2 bob pw unchanged" "1" "$(docker exec users-m1 bash -c "mysql -h 127.0.0.1 -P 13306 -u bob -p'bobpw' -NBe 'SELECT 1' 2>/dev/null | tail -1")"
davepw="$(tr -d '\r' < "$VOL/.db-users/credentials" | grep '^dave=' | cut -d= -f2-)"
[ -n "$davepw" ] && PASS=$((PASS+1)) && printf '[ok] PASS: M2 dave generated pw recorded in .db-users/credentials\n' || { FAILED=$((FAILED+1)); echo '[FAIL] M2 dave pw missing'; }
check "M2 dave auth" "1" "$(docker exec users-m1 bash -c "mysql -h 127.0.0.1 -P 13306 -u dave -p'${davepw}' -NBe 'SELECT 1' 2>/dev/null | tail -1")"

# ===========================================================================
echo "== M3: mariadb - removing dave deletes account, preserves his database =="
boot users-m1 "$VOL" mariadb 13306 "alice,bob" ""
wait_ready users-m1 "mysql -h 127.0.0.1 -P 13306 -u root -p'${ROOTPW}' -NBe 'SELECT 1'" || { echo "FATAL: mariadb not ready on M3"; exit 1; }
sleep 3
check "M3 dave auth rejected" "" "$(docker exec users-m1 bash -c "mysql -h 127.0.0.1 -P 13306 -u dave -p'${davepw}' -NBe 'SELECT 1' 2>/dev/null | tail -1")"
check "M3 dave_db preserved" "dave_db" "$(docker exec users-m1 bash -c "mysql -h 127.0.0.1 -P 13306 -u root -p'${ROOTPW}' -NBe 'SHOW DATABASES LIKE \"dave_db\"' 2>/dev/null")"
check "M3 alice still works" "1" "$(docker exec users-m1 bash -c "mysql -h 127.0.0.1 -P 13306 -u alice -p'AlicePw1' -NBe 'SELECT 1' 2>/dev/null | tail -1")"

# ===========================================================================
cleanup users-m1
echo "== M4: mariadb - root password rotation via DB_ROOT_PASSWORD =="
boot users-m4 "$VOL" mariadb 13307 "alice" "AlicePw1" -e "DB_ROOT_PASSWORD=NewRootPw456!" -e AUTO_GENERATE_CREDENTIALS=0
wait_ready users-m4 "mysql -h 127.0.0.1 -P 13307 -u root -p'NewRootPw456!' -NBe 'SELECT 1'" || { echo "FATAL: mariadb not ready on M4 (see private logs)"; exit 1; }
check "M4 root rotated to new pw" "1" "$(docker exec users-m4 bash -c "mysql -h 127.0.0.1 -P 13307 -u root -p'NewRootPw456!' -NBe 'SELECT 1' 2>/dev/null | tail -1")"
check "M4 alice unaffected" "1" "$(docker exec users-m4 bash -c "mysql -h 127.0.0.1 -P 13307 -u alice -p'AlicePw1' -NBe 'SELECT 1' 2>/dev/null | tail -1")"
cleanup users-m4
fi

# ===========================================================================
if selected postgresql; then
echo "== P1: postgresql - users + own dbs + removal =="
boot users-p1 "$VOL" postgresql 15432 "carol,dan" "CarolPw1,"
wait_ready users-p1 "PGPASSWORD='RootPassword123!Secure' psql -h 127.0.0.1 -p 15432 -U postgres -d postgres -Atc 'SELECT 1'" || { echo "FATAL: postgres never ready (see private logs)"; exit 1; }
sleep 3
check "P1 carol auth" "1" "$(docker exec users-p1 bash -c "PGPASSWORD='CarolPw1' psql -h 127.0.0.1 -p 15432 -U carol -d carol_db -Atc 'SELECT 1' 2>/dev/null")"
danpw="$(tr -d '\r' < "$VOL/.db-users/credentials" | grep '^dan=' | cut -d= -f2-)"
check "P1 dan auth (own db)" "1" "$(docker exec users-p1 bash -c "PGPASSWORD='${danpw}' psql -h 127.0.0.1 -p 15432 -U dan -d dan_db -Atc 'SELECT 1' 2>/dev/null")"
check "P1 carol_db owned" "carol_db" "$(docker exec users-p1 bash -c "PGPASSWORD='RootPassword123!Secure' psql -h 127.0.0.1 -p 15432 -U postgres -d postgres -Atc \"SELECT datname FROM pg_database WHERE datname='carol_db'\" 2>/dev/null")"
cleanup users-p1
boot users-p1 "$VOL" postgresql 15432 "carol" "CarolPw1"
wait_ready users-p1 "PGPASSWORD='RootPassword123!Secure' psql -h 127.0.0.1 -p 15432 -U postgres -d postgres -Atc 'SELECT 1'" || { echo "FATAL: postgres not ready on P1b"; exit 1; }
sleep 3
check "P1 dan role dropped" "0" "$(docker exec users-p1 bash -c "PGPASSWORD='RootPassword123!Secure' psql -h 127.0.0.1 -p 15432 -U postgres -d postgres -Atc \"SELECT COUNT(*) FROM pg_roles WHERE rolname='dan'\" 2>/dev/null")"
check "P1 dan_db preserved" "dan_db" "$(docker exec users-p1 bash -c "PGPASSWORD='RootPassword123!Secure' psql -h 127.0.0.1 -p 15432 -U postgres -d postgres -Atc \"SELECT datname FROM pg_database WHERE datname='dan_db'\" 2>/dev/null")"
cleanup users-p1
fi

# ===========================================================================
if selected mongodb; then
echo "== G1: mongodb - users + own dbs + removal =="
boot users-g1 "$VOL" mongodb 28017 "erin" "ErinPw1"
wait_ready users-g1 "mongosh --quiet --port 28017 -u root -p '${ROOTPW}' --authenticationDatabase admin --eval 'db.adminCommand(\"ping\")'" || { echo "FATAL: mongo never ready (see private logs)"; exit 1; }
sleep 3
check "G1 erin auth on erin_db" "1" "$(docker exec users-g1 bash -c "mongosh --quiet --port 28017 -u erin -p 'ErinPw1' --authenticationDatabase erin_db erin_db --eval \"db.runCommand({listCollections:1}).ok\" 2>/dev/null | tail -1")"
cleanup users-g1
boot users-g1 "$VOL" mongodb 28017 "" ""
wait_ready users-g1 "mongosh --quiet --port 28017 -u root -p '${ROOTPW}' --authenticationDatabase admin --eval 'db.adminCommand(\"ping\")'" || { echo "FATAL: mongo not ready G1b"; exit 1; }
sleep 3
check "G1 erin dropped" "0" "$(docker exec users-g1 bash -c "mongosh --quiet --port 28017 -u root -p '${ROOTPW}' --authenticationDatabase admin erin_db --eval \"db.getUser('erin') ? 1 : 0\" 2>/dev/null | tail -1")"
cleanup users-g1

fi
printf '\nRESULTS: %d passed, %d failed\n' "$PASS" "$FAILED"
[ "$FAILED" = "0" ]
