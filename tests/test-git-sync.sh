#!/bin/bash
# Sandbox test for scripts/db-init-git.sh (run on Git Bash / Linux / CI).
# Fully hermetic: exercises the engine against local file:// repositories, so
# no network access and no credential helpers are ever involved.
set -u
cd "$(dirname "$0")/.." || exit 1

# Never let a host credential helper pop a dialog or hang the suite.
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=/bin/true
export GCM_INTERACTIVE=never
export GIT_CONFIG_SYSTEM=/dev/null

SANDBOX=$(mktemp -d)
export SERVER_DIR="${SANDBOX}/server"
mkdir -p "${SERVER_DIR}"
REPO="${SANDBOX}/repo.git"
WT="${SANDBOX}/wt"
PASS=0; FAIL=0
t_pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
t_fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
G="git -c user.email=test@potenfyr.in -c user.name=SyncTest -c commit.gpgsign=false"

# Minimal logging stubs (mirror lib-diagnostics names used by the sync engine)
log()  { printf '[log] %s\n' "$*"; }
ok()   { printf '[ok] %s\n' "$*"; }
warn() { printf '[warn] %s\n' "$*" >&2; }
info() { printf '[info] %s\n' "$*"; }
error() { printf '[error] %s\n' "$*" >&2; }
phase() { printf '\n== %s ==\n' "$*"; }
_egg_error_log() { :; }

source scripts/db-init-git.sh

commit() { # commit FILE CONTENT MSG
    printf '%s\n' "$2" > "${WT}/$1"
    ${G} -C "${WT}" add -A >/dev/null
    ${G} -C "${WT}" commit -qm "$3" >/dev/null
    git -C "${WT}" push -q origin HEAD >/dev/null
}

echo "== DB git sync engine tests (hermetic) =="

${G} init -q --bare -b main "${REPO}"
${G} clone -q "${REPO}" "${WT}" 2>/dev/null
commit app-config.yml "key: value" "c1"
commit install.sql "SELECT 1;" "c1"

echo "--- T1: no repo configured (must be a silent no-op) ---"
sync_git_repo && t_pass "no-op returns zero" || t_fail "no-op failed"

echo "--- T2: first sync via file:// URL (local repo) ---"
GIT_REPO_URL="file://${REPO}"
sync_git_repo || t_fail "sync returned nonzero"
[ -f "${SERVER_DIR}/app-config.yml" ] && t_pass "files synced" || t_fail "files missing"
[ -f "${SERVER_DIR}/install.sql" ] && t_pass "second file synced" || t_fail "second file missing"
[ -s "${SERVER_DIR}/.git-sync/manifest" ] && t_pass "manifest written" || t_fail "manifest missing"

echo "--- T3: second run with no new commit (up to date, no re-download) ---"
out=$(sync_git_repo 2>&1)
printf '%s' "${out}" | grep -qi "up to date" && t_pass "reports up to date" || t_fail "no up-to-date message: ${out}"

echo "--- T4: protected paths must never be created/overwritten by repo content ---"
mkdir -p "${SERVER_DIR}/data" "${SERVER_DIR}/logs"
echo "precious" > "${SERVER_DIR}/data/keep.txt"
echo "secret" > "${SERVER_DIR}/.env"
commit data/steal.txt "stolen" "try to write into data/"
sync_git_repo || t_fail "sync failed on protected-content repo"
grep -q precious "${SERVER_DIR}/data/keep.txt" && t_pass "data/ preserved" || t_fail "data/ overwritten"
[ ! -f "${SERVER_DIR}/data/steal.txt" ] && t_pass "repo content into data/ blocked" || t_fail "repo wrote into data/"
grep -q secret "${SERVER_DIR}/.env" && t_pass ".env preserved" || t_fail ".env overwritten"

echo "--- T5: new upstream commit is picked up and archive is kept ---"
${G} -C "${WT}" rm -q install.sql >/dev/null 2>&1   # upstream deletion
commit app-config.yml "key: value2" "c2"
sync_git_repo || t_fail "update sync failed"
grep -q "value2" "${SERVER_DIR}/app-config.yml" && t_pass "new commit applied" || t_fail "stuck on old commit"
ls "${SERVER_DIR}/archive/git-sync"/code-*.tar.gz >/dev/null 2>&1 && t_pass "previous code archived" || t_fail "no archive"
[ ! -e "${SERVER_DIR}/install.sql" ] && t_pass "upstream deletion propagated" || t_fail "deleted file still present"

echo "--- T6: unreachable repo keeps existing code, returns non-zero (watcher quiet) ---"
GIT_REPO_URL="https://127.0.0.1:1/nope.git"
sync_git_repo >/dev/null 2>&1 && t_fail "unreachable repo reported success" || t_pass "failure signalled (non-zero)"
grep -q "value2" "${SERVER_DIR}/app-config.yml" && t_pass "existing code kept" || t_fail "code lost"

echo "--- T7: token'd sync still works against a repo that ignores tokens ---"
commit app-config.yml "key: value3" "c3"
GIT_REPO_URL="file://${REPO}"
GIT_TOKEN="ghp_faketoken123456"
sync_git_repo || t_fail "token'd sync failed against local repo"
grep -q "value3" "${SERVER_DIR}/app-config.yml" && t_pass "sync works with token set" || t_fail "token'd sync stuck"
unset GIT_TOKEN

echo "--- T8: manifest files wiped externally -> re-downloaded (no false up-to-date) ---"
rm -f "${SERVER_DIR}/app-config.yml" "${SERVER_DIR}/.git-sync/manifest"
sync_git_repo || t_fail "re-download failed"
[ -f "${SERVER_DIR}/app-config.yml" ] && t_pass "missing synced files restored" || t_fail "false up-to-date, files still gone"

echo "--- T9: branch switch ---"
${G} -C "${WT}" checkout -qb test
commit branch-file.txt "branch data" "branch c1"
${G} -C "${WT}" checkout -q main
GIT_BRANCH="test"
sync_git_repo || t_fail "branch switch failed"
[ -f "${SERVER_DIR}/branch-file.txt" ] && t_pass "switched to branch content" || t_fail "branch switch failed"
GIT_BRANCH=""

echo "--- T10: bad owner/repo shorthand keeps code, is non-fatal ---"
GIT_REPO_URL="definitely-not-a-real-user-xyz-987654/nope"
sync_git_repo >/dev/null 2>&1 && t_fail "bad shorthand reported success" || t_pass "bad shorthand signalled"
[ -f "${SERVER_DIR}/app-config.yml" ] && t_pass "code kept after bad shorthand" || t_fail "code lost"

rm -rf "${SANDBOX}"
echo
echo "Results: $PASS passed, $FAIL failed"
[ "${FAIL}" -eq 0 ]
