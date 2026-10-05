#!/usr/bin/env bash
# Hermetic (offline) tests for pf_mariadb_restore_dump and its wiring.
# Extracts the function from scripts/db-init-mariadb.sh, stubs the database
# client on PATH and asserts marker / stdin / exit-code behaviour without ever
# touching a real server. No network access is performed.
set -u
cd "$(dirname "$0")/.."

INST=scripts/db-init-mariadb.sh
ENTRY=entrypoint.sh
EGG=egg-database-multi.json

pass=0
failed=0
PASS() { pass=$((pass + 1)); printf 'PASS: %s\n' "$*"; }
FAIL() { failed=$((failed + 1)); printf 'FAIL: %s\n' "$*"; }
expect() { # expect <description> <command...>
    local desc="$1"
    shift
    if "$@"; then PASS "$desc"; else FAIL "$desc"; fi
}

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

# ---- extract the function under test (heredoc-safe python extractor) -------
PY=""
for c in python3 python; do
    # A Windows "App execution alias" can make command -v python3 succeed
    # while the interpreter is not actually installed; probe it for real.
    if command -v "$c" >/dev/null 2>&1 && "$c" -c 'pass' >/dev/null 2>&1; then
        PY="$c"
        break
    fi
done
if [ -z "$PY" ]; then
    echo "FAIL: no python interpreter found for function extraction"
    exit 1
fi
FUNC=$("$PY" tests/extract_funcs.py "$INST" 2>/dev/null \
    | tr -d '\r' \
    | awk '/^pf_mariadb_restore_dump\(\)/{p=1} p{print} p && /^}$/{exit}')
case "$FUNC" in
    *'pf_mariadb_restore_dump()'*) : ;;
    *)
        echo "FAIL: could not extract pf_mariadb_restore_dump from ${INST}"
        exit 1
        ;;
esac

# Stubs the extracted function expects from the live entrypoint.
log() { :; }
ok() { :; }
warn() { :; }
eval "$FUNC"

# ---- stub client -----------------------------------------------------------
STUB_DIR="$SANDBOX/stub"
mkdir -p "$STUB_DIR"
cat > "$STUB_DIR/client" <<'STUB'
#!/bin/sh
dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cat > "$dir/stdin"
printf '%s\n' "$@" > "$dir/args"
printf 'call\n' >> "$dir/calls"
rc=$(cat "$dir/rc" 2>/dev/null || printf 0)
exit "$rc"
STUB
chmod +x "$STUB_DIR/client" 2>/dev/null || true
CLIENT="$STUB_DIR/client"
stub_reset() { rm -f "$STUB_DIR/stdin" "$STUB_DIR/args" "$STUB_DIR/calls"; printf '0\n' > "$STUB_DIR/rc"; }
stub_calls() { wc -l < "$STUB_DIR/calls" 2>/dev/null | tr -d '[:space:]'; }

# ---- wired globals ---------------------------------------------------------
SERVER_DIR="$SANDBOX/server"
mkdir -p "$SERVER_DIR/logs"
SERVER_PORT=3306
DB_ROOT_PASSWORD="s3cret"
RESTORE_DUMP=1
DUMP_DIR="$SERVER_DIR/dump"
MARKER="$DUMP_DIR/.restored.sha256"

new_dump_dir() { rm -rf "$DUMP_DIR"; mkdir -p "$DUMP_DIR"; }
run_restore() { pf_mariadb_restore_dump "$CLIENT"; }
hash_of() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

# ===========================================================================
# 1. plain .sql success: marker written, content == dump checksum, SQL fed in
# ===========================================================================
new_dump_dir
printf 'CREATE TABLE t (id int);\nINSERT INTO t VALUES (1);\n' > "$DUMP_DIR/sample.sql"
stub_reset
run_restore; rc=$?
hash=$(hash_of "$DUMP_DIR/sample.sql")
expect "1a .sql success: marker exists" test -f "$MARKER"
expect "1b .sql success: marker == sha256(dump)" test "$(cat "$MARKER" 2>/dev/null)" = "$hash"
expect "1c .sql success: client received the SQL" \
    grep -q 'INSERT INTO t VALUES (1);' "$STUB_DIR/stdin"
expect "1d .sql success: function returned 0" test "$rc" -eq 0

# 1e. compressed .sql.gz success (gzip is always present)
new_dump_dir
printf 'CREATE TABLE gz (id int);\nGZ_SUCCESS_LINE;\n' > "$SANDBOX/gz.src"
gzip -c "$SANDBOX/gz.src" > "$DUMP_DIR/sample.sql.gz"
stub_reset
run_restore; rc=$?
hash=$(hash_of "$DUMP_DIR/sample.sql.gz")
expect "1e .sql.gz success: marker == sha256(archive)" test "$(cat "$MARKER" 2>/dev/null)" = "$hash"
expect "1f .sql.gz success: client received decompressed SQL" \
    grep -q 'GZ_SUCCESS_LINE;' "$STUB_DIR/stdin"
expect "1g .sql.gz success: function returned 0" test "$rc" -eq 0

# 1h. compressed .sql.xz success (skip when xz is unavailable OR cannot read
# the sandbox path, e.g. a native mingw xz on Windows that rejects MSYS /tmp).
xz_usable=0
if command -v xz >/dev/null 2>&1; then
    printf 'probe\n' > "$SANDBOX/xz.probe"
    if xz -c "$SANDBOX/xz.probe" >/dev/null 2>&1; then xz_usable=1; fi
fi
if [ "$xz_usable" -eq 1 ]; then
    new_dump_dir
    printf 'CREATE TABLE xz (id int);\nXZ_SUCCESS_LINE;\n' > "$SANDBOX/xz.src"
    xz -c "$SANDBOX/xz.src" > "$DUMP_DIR/sample.sql.xz"
    stub_reset
    run_restore; rc=$?
    hash=$(hash_of "$DUMP_DIR/sample.sql.xz")
    expect "1h .sql.xz success: marker == sha256(archive)" test "$(cat "$MARKER" 2>/dev/null)" = "$hash"
    expect "1i .sql.xz success: client received decompressed SQL" \
        grep -q 'XZ_SUCCESS_LINE;' "$STUB_DIR/stdin"
    expect "1j .sql.xz success: function returned 0" test "$rc" -eq 0
else
    printf 'SKIP: .sql.xz live case (xz unavailable or cannot read the sandbox path)\n'
fi

# 1k. compressed .sql.zst success (skip when zstd is unavailable)
zstd_usable=0
if command -v zstd >/dev/null 2>&1; then
    printf 'probe\n' > "$SANDBOX/zst.probe"
    if zstd -q -c "$SANDBOX/zst.probe" >/dev/null 2>&1; then zstd_usable=1; fi
fi
if [ "$zstd_usable" -eq 1 ]; then
    new_dump_dir
    printf 'CREATE TABLE zst (id int);\nZST_SUCCESS_LINE;\n' > "$SANDBOX/zst.src"
    zstd -q -c "$SANDBOX/zst.src" > "$DUMP_DIR/sample.sql.zst"
    stub_reset
    run_restore; rc=$?
    hash=$(hash_of "$DUMP_DIR/sample.sql.zst")
    expect "1k .sql.zst success: marker == sha256(archive)" test "$(cat "$MARKER" 2>/dev/null)" = "$hash"
    expect "1l .sql.zst success: client received decompressed SQL" \
        grep -q 'ZST_SUCCESS_LINE;' "$STUB_DIR/stdin"
    expect "1m .sql.zst success: function returned 0" test "$rc" -eq 0
else
    printf 'SKIP: .sql.zst live case (zstd unavailable)\n'
fi

# ===========================================================================
# 2. client exit 1 -> no marker, function still returns 0
# ===========================================================================
new_dump_dir
printf 'FAILME_LINE;\n' > "$DUMP_DIR/fail.sql"
stub_reset
printf '1\n' > "$STUB_DIR/rc"
run_restore; rc=$?
expect "2a client failure: no marker written" test ! -f "$MARKER"
expect "2b client failure: function returned 0" test "$rc" -eq 0

# ===========================================================================
# 3. corrupt .sql.gz -> decompressor stage is non-zero -> no marker, rc=0
# ===========================================================================
new_dump_dir
printf 'this is not a valid gzip stream' > "$DUMP_DIR/corrupt.sql.gz"
stub_reset
run_restore; rc=$?
expect "3a corrupt .sql.gz: no marker written" test ! -f "$MARKER"
expect "3b corrupt .sql.gz: function returned 0" test "$rc" -eq 0

# ===========================================================================
# 4. RESTORE_DUMP=0 -> client never invoked
# ===========================================================================
new_dump_dir
printf 'CREATE TABLE off (id int);\n' > "$DUMP_DIR/off.sql"
stub_reset
RESTORE_DUMP=0
run_restore; rc=$?
RESTORE_DUMP=1
expect "4a RESTORE_DUMP=0: client not called" test ! -e "$STUB_DIR/stdin"
expect "4b RESTORE_DUMP=0: function returned 0" test "$rc" -eq 0

# ===========================================================================
# 5. system-schema skip: mysql section dropped, application section kept
# ===========================================================================
new_dump_dir
cat > "$DUMP_DIR/skip.sql" <<'SQL'
USE mysql;
INSERT INTO mysql.user VALUES ('PLANTED_SYSTEM_LINE');
USE mydb;
INSERT INTO mydb.t VALUES ('KEEP_APP_LINE');
SQL
stub_reset
run_restore; rc=$?
expect "5a system-schema skip: application line kept" grep -q 'KEEP_APP_LINE' "$STUB_DIR/stdin"
expect "5b system-schema skip: planted system line dropped" \
    bash -c '! grep -q "PLANTED_SYSTEM_LINE" "$1"' _ "$STUB_DIR/stdin"
expect "5c system-schema skip: function returned 0" test "$rc" -eq 0

# ===========================================================================
# 6. marker already correct -> idempotent, client never invoked
# ===========================================================================
new_dump_dir
printf 'CREATE TABLE idem (id int);\n' > "$DUMP_DIR/idem.sql"
printf '%s\n' "$(hash_of "$DUMP_DIR/idem.sql")" > "$MARKER"
stub_reset
run_restore; rc=$?
expect "6a idempotent: client not called when marker matches" test ! -e "$STUB_DIR/stdin"
expect "6b idempotent: function returned 0" test "$rc" -eq 0

# ===========================================================================
# 7. preamble-only dump (no USE header) -> every line is forwarded
# ===========================================================================
new_dump_dir
printf 'SET NAMES utf8mb4;\nCREATE DATABASE IF NOT EXISTS foo;\n' > "$DUMP_DIR/preamble.sql"
stub_reset
run_restore; rc=$?
expect "7a preamble dump: SET NAMES line forwarded" grep -q 'SET NAMES utf8mb4;' "$STUB_DIR/stdin"
expect "7b preamble dump: CREATE DATABASE line forwarded" \
    grep -q 'CREATE DATABASE IF NOT EXISTS foo;' "$STUB_DIR/stdin"

# ===========================================================================
# 8. no dump file and empty root password -> client never invoked, rc=0
# ===========================================================================
new_dump_dir
stub_reset
run_restore; rc=$?
expect "8a no dump file: client not called" test ! -e "$STUB_DIR/stdin"
expect "8b no dump file: function returned 0" test "$rc" -eq 0

new_dump_dir
printf 'CREATE TABLE np (id int);\n' > "$DUMP_DIR/nopw.sql"
stub_reset
DB_ROOT_PASSWORD=""
run_restore; rc=$?
DB_ROOT_PASSWORD="s3cret"
expect "8c empty DB_ROOT_PASSWORD: client not called" test ! -e "$STUB_DIR/stdin"
expect "8d empty DB_ROOT_PASSWORD: function returned 0" test "$rc" -eq 0

# ===========================================================================
# 9. static wiring assertions (no execution)
# ===========================================================================
expect "9a function body wraps client in 'timeout 3600'" \
    bash -c 'printf "%s" "$1" | grep -q "timeout 3600"' _ "$FUNC"
expect "9b function body sets marker permissions (chmod 600)" \
    bash -c 'printf "%s" "$1" | grep -q "chmod 600"' _ "$FUNC"
expect "9c RESTORE_DUMP is in the entrypoint persisted-vars list" \
    grep -q 'CUSTOM_COMMAND RESTORE_DUMP' "$ENTRY"
expect "9d entrypoint creates the dump directory in its mkdir line" \
    grep -q '"${SERVER_DIR}/dump"' "$ENTRY"
egg_default=$(jq -r '.variables[] | select(.env_variable == "RESTORE_DUMP") | .default_value' "$EGG" 2>/dev/null | tr -d '\r')
expect "9e egg RESTORE_DUMP default_value is 0" test "$egg_default" = "0"
expect "9f egg exports exactly one RESTORE_DUMP variable" \
    test "$(jq '[.variables[] | select(.env_variable == "RESTORE_DUMP")] | length' "$EGG" 2>/dev/null | tr -d '\r')" = "1"

# ===========================================================================
# 10. call-site order: restore dump before reconcile before supervise
# ===========================================================================
restore_line=$(grep -n 'pf_mariadb_restore_dump "' "$INST" | head -n1 | cut -d: -f1)
reconcile_line=$(grep -n 'pf_users_reconcile_mysql "' "$INST" | head -n1 | cut -d: -f1)
supervise_line=$(grep -n 'supervise_daemon "' "$INST" | head -n1 | cut -d: -f1)
expect "10a all three call sites were located" \
    test -n "$restore_line" -a -n "$reconcile_line" -a -n "$supervise_line"
expect "10b restore dump called before account reconciliation" \
    test "${restore_line:-0}" -lt "${reconcile_line:-0}"
expect "10c account reconciliation called before supervise_daemon" \
    test "${reconcile_line:-0}" -lt "${supervise_line:-0}"

# ===========================================================================
# 11. first-dump-wins: with two dumps planted at once, the glob-first dump
#     (aa-first.sql) is the only one imported, exactly once; the later dump
#     (zz-last.sql) is never fed to the client. Pins the documented
#     "only one dump is picked per boot" / glob-order selection contract.
# ===========================================================================
new_dump_dir
printf 'AA_FIRST_MARKER_LINE;\n' > "$DUMP_DIR/aa-first.sql"
printf 'ZZ_LAST_MARKER_LINE;\n' > "$DUMP_DIR/zz-last.sql"
stub_reset
run_restore; rc=$?
first_hash=$(hash_of "$DUMP_DIR/aa-first.sql")
expect "11a first-dump-wins: client received only aa-first content" \
    bash -c 'grep -q "AA_FIRST_MARKER_LINE;" "$1" && ! grep -q "ZZ_LAST_MARKER_LINE;" "$1"' _ "$STUB_DIR/stdin"
expect "11b first-dump-wins: marker == sha256(aa-first.sql)" \
    test "$(cat "$MARKER" 2>/dev/null)" = "$first_hash"
expect "11c first-dump-wins: client invoked exactly once" test "$(stub_calls)" = "1"

# ===========================================================================
printf '\n%d passed, %d failed\n' "$pass" "$failed"
[ "$failed" -eq 0 ]
