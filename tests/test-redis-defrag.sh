#!/usr/bin/env bash
# =============================================================================
#  Redis-family activedefrag capability probe - unit tests.
#  Fast, offline. Guards the regression where a MALLOC=libc redis build was
#  fed 'activedefrag yes' (FATAL CONFIG FILE ERROR -> REDIS engine down,
#  CI red on 2026-09-20): the conf generator must verify the exact binary
#  that will run before emitting the directive, and must strip stale
#  directives from previously generated configs.
# =============================================================================
set -u
cd "$(dirname "$0")/.." || exit 1

PASS=0; FAILED=0
t_pass() { PASS=$((PASS+1));  printf '[ok] PASS: %s\n' "$1"; }
t_fail() { FAILED=$((FAILED+1)); printf '[FAIL] %s\n' "$1" >&2; }
t_check(){ if [ "$2" = "$3" ]; then t_pass "$1"; else t_fail "$1: expected [$2] got [$3]"; fi; }
rc_of()  { "$@" >/dev/null 2>&1; echo $?; }

TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT

# Stubs for the launcher environment the db-init scripts expect (run.sh
# provides these at runtime).
log()   { :; }
ok()    { :; }
error() { :; }
fail()  { printf '[fail-stub] %s\n' "$*" >&2; exit 1; }
warn()  { printf '%s\n' "$*" >> "${TEST_TMP}/warn.log"; }

# Both scripts are pure function definitions - safe to source wholesale.
. scripts/performance-tuning.sh
. scripts/db-init-redis.sh

make_fake() { # make_fake <path> <libc|jemalloc>
    local path="$1" mode="$2"
    mkdir -p "$(dirname "${path}")"
    if [ "${mode}" = "jemalloc" ]; then
        cat > "${path}" <<'EOF'
#!/usr/bin/env bash
# Defrag-capable build: parses the directive and serves until killed.
exec sleep 30
EOF
    else
        cat > "${path}" <<'EOF'
#!/usr/bin/env bash
# MALLOC=libc build: FATAL at config parse, before binding any port.
printf '%s\n' "*** FATAL CONFIG FILE ERROR ***" >&2
printf '%s\n' ">>> 'activedefrag yes'" >&2
printf '%s\n' "Active defragmentation cannot be enabled: it requires a Redis server compiled with a modified Jemalloc" >&2
exit 1
EOF
    fi
    chmod +x "${path}"
}

gen_conf() { # gen_conf <scenario-dir> <libc|jemalloc>
    local dir="$1" mode="$2"
    rm -f "${TEST_TMP}/warn.log"
    make_fake "${dir}/bin/redis-server" "${mode}"
    PROJECT_TYPE=redis SERVER_DIR="${dir}" SERVER_PORT=6379 SERVER_MEMORY=1024 \
        DB_PASSWORD='TestPassword123!Secure' DB_ROOT_PASSWORD='' \
        REDIS_DATABASES=16 init_redis_family
}

# --- probe unit -------------------------------------------------------------
make_fake "${TEST_TMP}/libc/redis-server" libc
make_fake "${TEST_TMP}/jemalloc/redis-server" jemalloc
SERVER_DIR="${TEST_TMP}/probe-home"
mkdir -p "${SERVER_DIR}"

t_check 'probe rejects libc-malloc build' 1 "$(rc_of pf_redis_supports_defrag "${TEST_TMP}/libc/redis-server")"
t_check 'probe accepts jemalloc build'    0 "$(rc_of pf_redis_supports_defrag "${TEST_TMP}/jemalloc/redis-server")"
t_check 'probe rejects missing binary'    1 "$(rc_of pf_redis_supports_defrag "${TEST_TMP}/nope/redis-server")"
t_check 'probe cleans its scratch dirs'   0 "$(ls "${SERVER_DIR}" 2>/dev/null | grep -c 'defrag-probe' || true)"

# --- conf generation: auto-tuned (SERVER_MEMORY=1024 -> defrag auto yes) ----
gen_conf "${TEST_TMP}/s1" libc
t_check 'libc build: generated conf omits activedefrag' 0 "$(grep -c '^activedefrag' "${TEST_TMP}/s1/config/redis.conf" || true)"

gen_conf "${TEST_TMP}/s2" jemalloc
t_check 'jemalloc build: generated conf enables activedefrag' 1 "$(grep -c '^activedefrag yes' "${TEST_TMP}/s2/config/redis.conf" || true)"
t_check 'jemalloc build: tuning thresholds present' 1 "$(grep -c '^active-defrag-threshold-lower 10$' "${TEST_TMP}/s2/config/redis.conf" || true)"

# --- conf sync: stale directives from older boots must be stripped ----------
gen_conf "${TEST_TMP}/s3" jemalloc
make_fake "${TEST_TMP}/s3/bin/redis-server" libc
PROJECT_TYPE=redis SERVER_DIR="${TEST_TMP}/s3" SERVER_PORT=6379 SERVER_MEMORY=1024 \
    DB_PASSWORD='TestPassword123!Secure' DB_ROOT_PASSWORD='' REDIS_DATABASES=16 init_redis_family
t_check 'sync path strips stale activedefrag on libc build' 0 "$(grep -c '^activedefrag' "${TEST_TMP}/s3/config/redis.conf" || true)"

# --- explicit request that cannot be honored: skip + warn -------------------
rm -f "${TEST_TMP}/warn.log"
make_fake "${TEST_TMP}/s4/bin/redis-server" libc
PROJECT_TYPE=redis SERVER_DIR="${TEST_TMP}/s4" SERVER_PORT=6379 SERVER_MEMORY=1024 \
    DB_PASSWORD='TestPassword123!Secure' DB_ROOT_PASSWORD='' REDIS_DATABASES=16 \
    REDIS_ACTIVE_DEFRAG=yes init_redis_family
t_check 'explicit request on libc build: directive skipped' 0 "$(grep -c '^activedefrag' "${TEST_TMP}/s4/config/redis.conf" || true)"
t_check 'explicit request on libc build: operator warned' 1 "$(grep -c 'FATAL' "${TEST_TMP}/warn.log" || true)"

# --- auto-tuned degradation must stay silent --------------------------------
gen_conf "${TEST_TMP}/s5" libc
t_check 'auto-tuned libc build: no operator warning spam' 0 "$( [ -f "${TEST_TMP}/warn.log" ] && wc -l < "${TEST_TMP}/warn.log" || echo 0)"

printf '\n%s\n' "=============================="
printf 'Total: %d, Passed: %d, Failed: %d\n' "$((PASS + FAILED))" "${PASS}" "${FAILED}"
[ "${FAILED}" -eq 0 ]
