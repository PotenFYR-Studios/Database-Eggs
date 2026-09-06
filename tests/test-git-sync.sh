#!/bin/bash
# Sandbox test for scripts/db-init-git.sh (run on Git Bash / Linux)
set -u
cd "$(dirname "$0")/.." || exit 1

SANDBOX=$(mktemp -d)
export SERVER_DIR="${SANDBOX}/server"
mkdir -p "${SERVER_DIR}"

# Minimal logging stubs (mirror lib-diagnostics names used by the sync engine)
log()  { printf '[log] %s\n' "$*"; }
ok()   { printf '[ok] %s\n' "$*"; }
warn() { printf '[warn] %s\n' "$*" >&2; }
info() { printf '[info] %s\n' "$*"; }
error() { printf '[error] %s\n' "$*" >&2; }
phase() { printf '\n== %s ==\n' "$*"; }
_egg_error_log() { :; }

source scripts/db-init-git.sh

echo "--- T1: no repo configured (must be a silent no-op) ---"
sync_git_repo && echo "T1 PASS" || echo "T1 FAIL"

echo "--- T2: first sync of a public repo (owner/repo shorthand) ---"
GIT_REPO_URL="octocat/Hello-World"
sync_git_repo || echo "T2 sync returned nonzero"
[ -f "${SERVER_DIR}/README" ] && echo "T2 PASS (README synced)" || echo "T2 FAIL (no README)"
ls -A "${SERVER_DIR}"
cat "${SERVER_DIR}/.git-sync/commit" 2>/dev/null | head -c 12; echo " <- recorded commit"

echo "--- T3: second run with no new commit (must be 'up to date', no re-download) ---"
sync_git_repo && echo "T3 PASS" || echo "T3 FAIL"

echo "--- T4: protected paths must never be created/overwritten by repo content ---"
mkdir -p "${SERVER_DIR}/data" "${SERVER_DIR}/logs"
echo "precious" > "${SERVER_DIR}/data/keep.txt"
echo "secret" > "${SERVER_DIR}/.env"
sync_git_repo
grep -q precious "${SERVER_DIR}/data/keep.txt" && grep -q secret "${SERVER_DIR}/.env" && echo "T4 PASS" || echo "T4 FAIL"

echo "--- T5: simulate upstream change via branch switch (repo same, commit differs) ---"
GIT_BRANCH="test"
sync_git_repo || echo "T5 sync returned nonzero"
cat "${SERVER_DIR}/.git-sync/branch" 2>/dev/null; echo " <- recorded branch"
ls -A "${SERVER_DIR}"

echo "--- T6: unreachable repo must keep existing code ---"
GIT_REPO_URL="https://github.com/definitely-not-a-real-user-xyz-987654/nope.git"
GIT_BRANCH=""
sync_git_repo && echo "T6 PASS (non-fatal)" || echo "T6 FAIL (fatal)"
grep -q secret "${SERVER_DIR}/.env" && echo "T6 env intact" || echo "T6 FAIL env lost"

rm -rf "${SANDBOX}"
echo "DONE"
