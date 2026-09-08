#!/bin/bash
# Unit tests for scripts/db-init-users.sh plan logic (no database required)
set -u
cd "$(dirname "$0")/.." || exit 1

log()  { printf '[log] %s\n' "$*"; }
ok()   { printf '[ok] %s\n' "$*"; }
warn() { printf '[warn] %s\n' "$*" >&2; }
info() { printf '[info] %s\n' "$*"; }
error() { printf '[error] %s\n' "$*" >&2; }
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
phase() { :; }
_egg_error_log() { :; }
gen_rand() { echo "RANDOMSECRET$1${RANDOM}${RANDOM}"; }

source scripts/db-init-users.sh
PASS=0; FAILED=0
check() { # check <desc> <expected> <actual>
    if [ "$2" = "$3" ]; then PASS=$((PASS+1)); ok "PASS: $1";
    else FAILED=$((FAILED+1)); printf '[FAIL] %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2; fi
}

SANDBOX=$(mktemp -d)
export SERVER_DIR="${SANDBOX}"

echo "== T1: parse - normalization, dedupe, invalid, reserved =="
out="$(pf_users_parse "Alice, bob,,BOB,char lie,root,_sys,x1,x1")"
check "T1 content" "alice,bob,_sys,x1" "$(printf '%s' "$out" | tr '\n' ',')"

echo "== T2: plan - first boot, two users, one password slot =="
rm -rf "${SANDBOX:?}"/*
pf_users_plan "alice,bob" "SecretAlice," "dbuser" ""
check "T2 users" "alice,bob" "${PF_USERS}"
check "T2 primary" "alice" "${PF_USERS_PRIMARY}"
check "T2 mode" "multi" "${PF_USERS_MODE}"
check "T2 new list" "alice,bob" "${PF_USERS_NEW}"
check "T2 provided pw" "SecretAlice" "$(pf_users_stored_password alice)"
bobpw="$(pf_users_stored_password bob)"
[ -n "$bobpw" ] && PASS=$((PASS+1)) && ok "PASS: T2 bob got generated pw" || { FAILED=$((FAILED+1)); echo "[FAIL] T2 bob pw empty"; }
check "T2 csv" "SecretAlice,${bobpw}" "$(pf_users_passwords_csv)"

echo "== T3: plan - existing users keep credentials even when passwords provided =="
rm -rf "${SANDBOX:?}"/*
mkdir -p "${SERVER_DIR}/.db-users"
printf 'alice\nbob\n' > "${SERVER_DIR}/.db-users/managed"
printf 'alice=OldSecretA\nbob=OldSecretB\n' > "${SERVER_DIR}/.db-users/credentials"
pf_users_plan "alice,bob" "NewPwA,NewPwB" "dbuser" ""
check "T3 alice keeps pw" "OldSecretA" "$(pf_users_stored_password alice)"
check "T3 bob keeps pw" "OldSecretB" "$(pf_users_stored_password bob)"
check "T3 primary pw var" "OldSecretA" "$(pf_users_primary_password)"

echo "== T4: plan - add user (dave) generates password, existing untouched =="
pf_users_plan "alice,bob,dave" ",," "dbuser" ""
check "T4 new list" "dave" "${PF_USERS_NEW}"
davepw="$(pf_users_stored_password dave)"
[ -n "$davepw" ] && PASS=$((PASS+1)) && ok "PASS: T4 dave generated pw recorded" || { FAILED=$((FAILED+1)); echo "[FAIL] T4 dave pw empty"; }
check "T4 alice kept" "OldSecretA" "$(pf_users_stored_password alice)"

echo "== T5: plan - remove user (bob) -> drop list; credentials pruned on commit =="
PF_USERS="alice,dave"
drops="$(pf_users_to_drop)"
check "T5 drop bob" "bob" "$drops"
pf_users_commit_managed "${PF_USERS}"
check "T5 managed" "alice,dave" "$(tr '\n' ',' < "${SERVER_DIR}/.db-users/managed" | sed 's/,$//')"
check "T5 bob pruned" "" "$(pf_users_stored_password bob)"
check "T5 alice kept" "OldSecretA" "$(pf_users_stored_password alice)"

echo "== T6: plan - empty usernames -> legacy dbuser mode =="
rm -rf "${SANDBOX:?}"/*
pf_users_plan "" "" "dbuser" "LegacyPw"
check "T6 mode" "legacy" "${PF_USERS_MODE}"
check "T6 user" "dbuser" "${PF_USERS_PRIMARY}"
check "T6 pw" "LegacyPw" "$(pf_users_primary_password)"

echo "== T7: root credential tracked once, preserved by commit_managed =="
rm -rf "${SANDBOX:?}"/*
DB_ROOT_PASSWORD="RootPw1" pf_users_plan "" "" "dbuser" "" "RootPw1"
check "T7 root stored" "RootPw1" "$(pf_users_stored_root)"
DB_ROOT_PASSWORD="RootPw2" pf_users_plan "" "" "dbuser" "" "RootPw2"
check "T7 root NOT overwritten by plan" "RootPw1" "$(pf_users_stored_root)"
pf_users_store_root "RootPw2"
check "T7 root rotated via store" "RootPw2" "$(pf_users_stored_root)"
pf_users_commit_managed "dbuser"
check "T7 root survives commit" "RootPw2" "$(pf_users_stored_root)"

echo "== T8: user var name export (case upper) =="
rm -rf "${SANDBOX:?}"/*
pf_users_plan "carol" "CarolPw" "dbuser" ""
check "T8 PF_USER_PW_CAROL" "CarolPw" "${PF_USER_PW_CAROL:-}"

rm -rf "${SANDBOX:?}"
printf '\nRESULTS: %d passed, %d failed\n' "$PASS" "$FAILED"
[ "$FAILED" = "0" ]
