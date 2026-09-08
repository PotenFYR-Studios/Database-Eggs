#!/usr/bin/env bash
# =============================================================================
#  Version resolver, suggestion engine & architecture matrix - unit tests.
#  Fast, offline (also runnable in Docker): validates version input, that
#  wrong-but-close pins produce "Did you mean" output, and that the arch
#  mapping covers amd64/arm64/arm/s390x/ppc64le/riscv64/386.
#  Upstream responses are fixtures, not claims of current release availability.
# =============================================================================
set -u
cd "$(dirname "$0")/.." || exit 1

PASS=0; FAILED=0
ok()   { PASS=$((PASS+1));  printf '[ok] PASS: %s\n' "$1"; }
bad()  { FAILED=$((FAILED+1)); printf '[FAIL] %s\n' "$1" >&2; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: expected [$2] got [$3]"; fi; }

INST=scripts/install-db-version.sh
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT

# --- helpers extracted verbatim from the installer (no side effects) --------
extract_fn() { # extract_fn <name>... -> prints function bodies
    local fn
    for fn in "$@"; do
        awk -v fn="$fn" '
            $0 ~ "^"fn"\\(\\)" { ingest=1 }
            ingest { print }
            ingest && /^}/ { ingest=0 }
        ' "$INST"
    done
}

# Stub the diagnostics library the installer expects
log()  { printf '[log] %s\n' "$*"; }
ok2()  { :; }
warn() { printf '[warn] %s\n' "$*" >&2; }
err()  { printf '[err] %s\n' "$*" >&2; }
fail() { printf '[fail] %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
export -f log warn err fail have 2>/dev/null || true

RESOLVER_FNS=$(extract_fn _pf_numeric_core _pf_ver_triple pf_ver_score pf_eol_product pf_suggest_repo pf_version_catalog pf_suggest_versions)
[ -n "${RESOLVER_FNS}" ] || { echo "FATAL: could not extract resolver functions"; exit 1; }

# ===========================================================================
echo "== V1: version-input acceptance (valid forms must resolve, not reject) =="
RESOLVE_FNS=$(extract_fn validate_version_input resolve_version pf_warn_unpublished_major eofl_resolve)
run_resolver() ( # real resolver functions; deterministic upstream boundary
    eval "$RESOLVER_FNS"
    eval "$RESOLVE_FNS"
    ENGINE="$1"; VERSION="$2"
    pf_cache_get() { return 1; }
    pf_cache_put() { :; }
    gh_latest_tag() {
        [ "${FIXTURE_NO_TAG:-0}" != 1 ] || return 0
        if [ "${2:-0}" = 1 ]; then printf 'v8.3.0-rc1'; else printf 'v8.2.2'; fi
    }
    pf_version_catalog() { printf '8.2.2\n7.0.15\n6.2.17\n'; }
    eofl_resolve() {
        case "$2" in '') printf '8.2.2' ;; 7|7.0) printf '7.0.15' ;; esac
    }
    resolve_version >/dev/null || return
    printf '%s\n' "$RESOLVED"
)

for form in latest stable beta alpha nightly snapshot edge dev default 18 11.4 8.0.45 v2.1.0 7 7.2 16; do
    out=$(run_resolver redis "$form") && rc=0 || rc=$?
    if [ "$rc" = "0" ]; then ok "redis accepts DB_VERSION=${form} (-> ${out})"; else bad "redis rejected DB_VERSION=${form}"; fi
done

# Assert outcomes, not just successful exit codes. Fixtures are deliberately
# independent of today's upstream versions.
check "latest resolves a concrete fixture version" "8.2.2" "$(run_resolver redis latest 2>/dev/null)"
check "snapshot preserves the prerelease suffix" "8.3.0-rc1" "$(run_resolver pocketbase snapshot 2>/dev/null)"
check "unresolved snapshot falls back to stable metadata" "8.2.2" "$(FIXTURE_NO_TAG=1 run_resolver valkey snapshot 2>/dev/null)"
check "obsolete exact pin is preserved" "6.0.1" "$(run_resolver redis 6.0.1 2>/dev/null)"
check "download URL remains byte-for-byte unchanged" "https://example.invalid/DB.TGZ?Key=AbC" "$(run_resolver custom 'https://example.invalid/DB.TGZ?Key=AbC' 2>/dev/null)"

github_channel_fixture() (
    eval "$(extract_fn gh_latest_tag _json_tags)"
    pf_cache_get() { return 1; }
    pf_cache_put() { :; }
    PF_CURL_UA=test
    [ "$2" != nojq ] || have() { [ "$1" != jq ] && command -v "$1" >/dev/null 2>&1; }
    fetch() {
        case "$1" in
            */releases/latest) return 1 ;;
            */releases\?*) printf '%s' '[{"tag_name":"v9.0.0-rc1","prerelease":true},{"tag_name":"v8.2.2","prerelease":false}]' ;;
        esac
    }
    curl() { printf 'https://github.com/example/db/releases/tag/v8.2.2'; }
    gh_latest_tag example/db "$1"
)
for parser in jq nojq; do
    check "$parser latest fallback must not select a prerelease" "v8.2.2" "$(github_channel_fixture 0 "$parser")"
    check "$parser snapshot can select a prerelease" "v9.0.0-rc1" "$(github_channel_fixture 1 "$parser")"
done

# Invalid forms must be refused (injection protection)
for form in "not a version; rm -rf /" "../../etc/passwd" "\$(reboot)" "'; DROP TABLE x; --"; do
    out=$(run_resolver redis "$form" 2>&1) && rc=0 || rc=$?
    if [ "$rc" = "0" ]; then bad "redis ACCEPTED invalid DB_VERSION='${form}'"; else ok "redis refused invalid DB_VERSION='${form}'"; fi
done

# ===========================================================================
echo "== V2: suggestion scoring (pure functions, no network) =="
body=$(mktemp)
{ echo 'have() { command -v "$1" >/dev/null 2>&1; }'; echo "${RESOLVER_FNS}"; } > "$body"
score() { bash -c 'source "'"$body"'"; pf_ver_score "$1" "$2"' _ "$1" "$2"; }
check "same series patch distance"  "14" "$(score 7.0 7.0.14)"
check "minor distance x2"           "22" "$(score 11.6 11.4)"
check "major distance dominates"    "210" "$(score 9.9.9 8.2.2)"
check "no numeric core"             "9999" "$(score abc 1.2.3)"
core() { bash -c 'source "'"$body"'"; _pf_numeric_core "$1"' _ "$1"; }
check "core strips prefix/suffix"   "7.2.4" "$(core 7.2.4-alpine)"
check "core of garbage is empty"    "" "$(core 'not a version; rm -rf /')"
check "core of tag"                 "11.8.1" "$(core mariadb-11.8.1)"
rm -f "$body"

# ===========================================================================
echo "== V3: 'Did you mean' suggestions =="
# V3a (fixture catalog): missing majors warn before any download attempt.
sugg() { run_resolver "$1" "$2" 2>&1 | grep -i "did you mean" | head -1; }
line=$(sugg redis "9.9.9")
[ -n "${line}" ] && ok "redis 9.9.9 (no such major) warns: ${line}" || bad "no resolve-time suggestion for redis 9.9.9"
line=$(sugg postgresql "19")
[ -n "${line}" ] && ok "postgresql 19 (no such major) warns: ${line}" || bad "no resolve-time suggestion for postgresql 19"
# Obsolete-but-real series must NOT warn when present in the catalog.
line=$(sugg redis "7.0")
[ -z "${line}" ] && ok "redis 7.0 (obsolete but real) boots without suggestion noise" || bad "redis 7.0 falsely flagged: ${line}"

# V3b (offline): wrong-but-close MINOR pins produce ranked suggestions via the
# failure-site path (synthetic catalog, no network).
body2=$(mktemp)
{
    echo 'have() { command -v "$1" >/dev/null 2>&1; }'
    echo "${RESOLVER_FNS}"
    echo 'pf_version_catalog() { printf "11.4.5\n11.8.1\n12.0.1\n10.11.14\n"; }'
    echo 'ENGINE=mariadb'
    echo 'pf_suggest_versions 11.6'
} > "$body2"
out=$(bash "$body2" 2>&1)
printf '%s\n' "${out}" | grep -q "11.4.5" && printf '%s\n' "${out}" | grep -q "11.8.1" \
    && ok "mariadb 11.6 ranks nearest real series first ($(printf '%s' "${out}" | grep -i 'did you mean'))" \
    || bad "synthetic suggestion failed: ${out}"
rm -f "$body2"

suggest_fixture() (
    eval "$RESOLVER_FNS"
    ENGINE=redis
    pf_version_catalog() { printf 'v9.0.0-rc1\n8.2.2\n'; }
    pf_suggest_versions "$1"
)
out=$(suggest_fixture 9.0.1 2>&1)
[[ "$out" == *"Did you mean: v9.0.0-rc1,8.2.2 ?"* ]] \
    && ok "suggestions preserve published prerelease tags" || bad "suggestion invented a stable release: $out"
out=$(suggest_fixture 8.2.2 2>&1)
[[ "$out" != *"your request '8.2.2' is not"* ]] && ok "failed provisioning does not imply unpublished version" \
    || bad "published pin falsely declared nonexistent: $out"
out=$(run_resolver redis 1.0.0 2>&1)
[[ "$out" != *"No published redis release has major"* ]] \
    && ok "limited recent catalog cannot disprove an obsolete major" \
    || bad "limited catalog falsely proves obsolete major never existed: $out"

# Real EOL parser with an isolated fixture product (no global cache pollution).
eol_fixture() (
    eval "$(extract_fn eofl_resolve)"
    pf_cache_get() { return 1; }
    pf_cache_put() { :; }
    fetch() { return 1; }
    [ "$2" != nojq ] || have() { [ "$1" != jq ] && command -v "$1" >/dev/null 2>&1; }
    product="pf-test-$$-$BASHPID"
    fixture="/tmp/.eofl-cache-${product}.json"
    trap 'rm -f "$fixture"' EXIT
    printf '%s' '[{"cycle":"11.8","latest":"11.8.1"},{"cycle":"11.4","latest":"11.4.5"},{"cycle":"10.11","latest":"10.11.14"},{"cycle":"1.0","latest":"1.0.9"}]' > "$fixture"
    eofl_resolve "$product" "$1"
)
for parser in jq nojq; do
    check "$parser major matches component, not digit prefix" "1.0.9" "$(eol_fixture 1 "$parser")"
    check "$parser nonexistent series stays unresolved" "" "$(eol_fixture 11.1 "$parser")"
    check "$parser obsolete series remains resolvable" "10.11.14" "$(eol_fixture 10.11 "$parser")"
done

# ===========================================================================
echo "== V4: architecture matrix maps every known uname -m =="
arch_matrix() { # arch_matrix <uname-m> -> "ARCH_TYPE ARCH_ALT"
    # Execute the production block, substituting only the uname boundary.
    local matrix
    matrix=$(awk '/^ARCH=\$\(uname -m\)/ {read_arch=1} read_arch {print} read_arch && /^esac$/ {exit}' "$INST")
    bash -c '
        mocked_arch="$1"
        uname() { printf "%s\n" "$mocked_arch"; }
        warn() { :; }
        eval "$2"
        printf "%s %s" "$ARCH_TYPE" "$ARCH_ALT"
    ' _ "$1" "$matrix"
}
check "x86_64"     "amd64 x86_64" "$(arch_matrix x86_64)"
check "aarch64"    "arm64 aarch64" "$(arch_matrix aarch64)"
check "armv7l"     "arm arm" "$(arch_matrix armv7l)"
check "s390x"      "s390x s390x" "$(arch_matrix s390x)"
check "ppc64le"    "ppc64le ppc64le" "$(arch_matrix ppc64le)"
check "riscv64"    "riscv64 riscv64" "$(arch_matrix riscv64)"
check "i686"       "386 i686" "$(arch_matrix i686)"
check "big-endian ppc64 must not select little-endian assets" "ppc64 ppc64" "$(arch_matrix ppc64)"
check "unknown must not select amd64 assets" "loongarch64 loongarch64" "$(arch_matrix loongarch64)"

echo "== V5: actual dispatcher identifiers and CLI pin coverage =="
# Count only case labels, never words in handler bodies. Exercise the actual
# installer CLI for every distinct label; this is resolver, NOT startup coverage.
mapfile -t engines < <(awk '/^    [a-z0-9_|]+\)/ {sub(/^    /, ""); sub(/\).*/, ""); print}' run.sh | tr '|' '\n' | sort -u)
[ "${#engines[@]}" -ge 50 ] && ok "${#engines[@]} distinct dispatcher identifiers (including aliases)" || bad "dispatcher coverage shrank (${#engines[@]})"
cli_resolver() (
    # Only transport is stubbed; production initialization, validation and
    # resolution all execute. No network or writes to the repository.
    curl() { return 1; }
    wget() { return 1; }
    export -f curl wget
    SERVER_DIR="$TEST_TMP" PF_RESOLVE_ONLY=1 \
        bash "$INST" "$1" 6.0.1 "$TEST_TMP/bin" 2>/dev/null
)
for engine in "${engines[@]}"; do
    out=$(cli_resolver "$engine") && rc=0 || rc=$?
    if [ "$rc" = 0 ] && [ "$out" = 6.0.1 ]; then
        ok "$engine CLI preserves explicit pin (not an availability assertion)"
    else
        bad "$engine CLI explicit pin: rc=$rc output=$out"
    fi
done
grep -q "prometheus|consul|loki|sqlite" run.sh && ok "new engines (prometheus/consul/loki/sqlite) dispatched" || bad "new engines missing from run.sh"
grep -q "kafka" run.sh && ok "kafka dispatched" || bad "kafka missing from run.sh"
grep -q "    kafka)" scripts/install-db-version.sh && ok "kafka installer present" || bad "kafka installer missing"
grep -q "    prometheus)" scripts/install-db-version.sh && ok "prometheus installer present" || bad "prometheus installer missing"
grep -q "    consul)" scripts/install-db-version.sh && ok "consul installer present" || bad "consul installer missing"
grep -q "    loki)" scripts/install-db-version.sh && ok "loki installer present" || bad "loki installer missing"

printf '\nRESULTS: %d passed, %d failed\n' "$PASS" "$FAILED"
[ "$FAILED" = "0" ]
