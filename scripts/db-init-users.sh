#!/bin/bash
# =============================================================================
#  PotenFYR Studios - Multi-User Account Engine (db-init-users.sh)
# =============================================================================
# Manages database application users declared via startup variables:
#
#   DB_USERNAMES  - comma-separated usernames (e.g. "alice,bob,carol").
#                   Empty/invalid -> legacy single user 'dbuser' is
#                   created/maintained exactly like previous egg versions.
#   DB_PASSWORDS  - comma-separated passwords, positionally mapped to
#                   DB_USERNAMES. Empty slot -> a fresh random secret is
#                   generated for that user. A password is applied exactly
#                   ONCE, at user creation; existing users' credentials are
#                   never changed by restarts or variable edits.
#
# Multi-user semantics (DB_USERNAMES explicitly set):
#   * every user owns their private database '<user>_db' (full owner rights)
#   * every user also gets full rights on the shared DB_NAME database
#   * removing a username DELETES the account; their '<user>_db' database is
#     PRESERVED (data safety) and is re-adopted if the user is re-added
#   * no artificial limit on the number of users
#
# State (under ${SERVER_DIR}/.db-users/, mode 700):
#   managed      - newline list of users this engine created (drives drops)
#   credentials  - "user=password" lines for every managed user (mode 600)
# =============================================================================

_PF_USERS_RESERVED='root
postgres
mysql
mariadb
admin
mongodb
redis
valkey
nobody'

# Normalize + validate the requested username list.
# Prints one normalized username per line. Invalid / reserved tokens are
# warned about and skipped (never fatal - valid users still provision).
pf_users_parse() { # pf_users_parse <raw-list>
    local raw="$1" tok
    local -a out=()
    raw="${raw//;/,}"
    local IFS=','
    for tok in ${raw}; do
        tok="${tok#"${tok%%[![:space:]]*}"}"   # ltrim
        tok="${tok%"${tok##*[![:space:]]}"}"   # rtrim
        [ -n "${tok}" ] || continue
        tok="${tok,,}"
        if ! printf '%s' "${tok}" | grep -qE '^[a-z_][a-z0-9_]{0,31}$'; then
            warn "Username '${tok}' is invalid (use letters, digits, underscore; max 32 chars, start with a letter) - skipped."
            continue
        fi
        local reserved=0 _r
        while IFS= read -r _r; do
            if [ "${tok}" = "${_r}" ]; then
                warn "Username '${tok}' is a reserved system account - skipped."
                reserved=1
                break
            fi
        done <<__RESERVED
${_PF_USERS_RESERVED}
__RESERVED
        [ "${reserved}" = "0" ] || continue
        local dup=0 u
        for u in ${out[@]+"${out[@]}"}; do
            if [ "${u}" = "${tok}" ]; then dup=1; break; fi
        done
        [ "${dup}" = "0" ] || { warn "Duplicate username '${tok}' - ignored."; continue; }
        out+=("${tok}")
    done
    for u in ${out[@]+"${out[@]}"}; do
        printf '%s\n' "${u}"
    done
    return 0
}

pf_users_state_dir() { printf '%s/.db-users' "${SERVER_DIR}"; }

pf_users_prev_list() { # previously managed users (one per line)
    cat "$(pf_users_state_dir)/managed" 2>/dev/null || true
}

pf_users_stored_password() { # pf_users_stored_password <user>
    grep -m1 "^$1=" "$(pf_users_state_dir)/credentials" 2>/dev/null | cut -d= -f2-
}

# Plan + persist: fills password gaps for NEW users, aligns DB_PASSWORDS to
# the final user list, and exports PF_USERS / PF_USERS_PRIMARY / PF_USER_PW_*.
# Must run in the entrypoint (before .env is written) so restarts see a
# truthful .env. Never touches the credentials of already-managed users.
pf_users_plan() { # pf_users_plan <raw-usernames> <raw-passwords> <legacy-user> <legacy-password>
    local raw_users="$1" raw_passwords="$2" legacy_user="$3" legacy_password="$4" legacy_root_password="${5:-}"

    local -a users=() pws=()
    local u pw prev

    if [ -n "${raw_users//[,[:space:]]/}" ]; then
        # --- explicit multi-user mode ------------------------------------
        local -a parsed=() slots=()
        while IFS= read -r u; do
            [ -n "${u}" ] && parsed+=("${u}")
        done < <(pf_users_parse "${raw_users}")
        if [ "${#parsed[@]}" = "0" ]; then
            warn "No valid usernames in DB_USERNAMES - falling back to legacy single user '${legacy_user}'."
        else
            local IFS=','
            for pw in ${raw_passwords}; do
                pw="${pw#"${pw%%[![:space:]]*}"}"; pw="${pw%"${pw##*[![:space:]]}"}"
                slots+=("${pw}")
            done
            unset IFS
            local i=0
            for u in ${parsed[@]+"${parsed[@]}"}; do
                pw="${slots[${i}]:-}"
                users+=("${u}"); pws+=("${pw}")
                i=$((i + 1))
            done
        fi
    fi

    if [ "${#users[@]}" = "0" ]; then
        # --- legacy single-user mode (unchanged historical behaviour) ----
        users+=("${legacy_user:-dbuser}")
        pws+=("${legacy_password}")
    fi

    local state_dir; state_dir=$(pf_users_state_dir)
    mkdir -p "${state_dir}" 2>/dev/null || true
    chmod 700 "${state_dir}" 2>/dev/null || true

    # Resolve each user's effective password:
    #   new user  -> provided slot or fresh random secret (recorded once)
    #   known user-> stored secret; a newly provided password is IGNORED
    local -a final_users=() final_pws=() new_users=() ignore_pws=()
    local -i idx=0
    for u in ${users[@]+"${users[@]}"}; do
        pw="${pws[${idx}]:-}"
        local is_new=1
        while IFS= read -r prev; do
            if [ "${prev}" = "${u}" ]; then is_new=0; break; fi
        done < <(pf_users_prev_list)
        local stored; stored=$(pf_users_stored_password "${u}")
        if [ "${is_new}" = "1" ]; then
            if [ -z "${pw}" ]; then
                pw=$(gen_rand 32 urlsafe 2>/dev/null || echo "Pf_$(head -c 24 /dev/urandom 2>/dev/null | tr -dc 'A-Za-z0-9' | head -c 24)_$(date +%s)")
            fi
            new_users+=("${u}")
        else
            if [ -n "${pw}" ]; then
                ignore_pws+=("${u}")
                _egg_error_log "users" "password provided for existing user '${u}' ignored (credentials are never changed)" >/dev/null 2>&1 || true
            fi
            if [ -n "${stored}" ]; then pw="${stored}"; fi
        fi
        if [ -n "${pw}" ]; then
            printf '%s=%s\n' "${u}" "${pw}" >> "${state_dir}/.credentials.new"
        fi
        final_users+=("${u}"); final_pws+=("${pw}")
        idx=$((idx + 1))
    done

    # Track the root credential on first sight only; rotation of an already
    # known root password happens inside the engine reconcilers.
    if ! grep -q '^root=' "${state_dir}/credentials" 2>/dev/null; then
        if [ -n "${DB_ROOT_PASSWORD:-}" ] && [ "${DB_ROOT_PASSWORD}" != "auto" ] && [ "${DB_ROOT_PASSWORD}" != "generate" ]; then
            printf 'root=%s\n' "${DB_ROOT_PASSWORD}" >> "${state_dir}/.credentials.new"
        elif [ -n "${legacy_root_password:-}" ]; then
            printf 'root=%s\n' "${legacy_root_password}" >> "${state_dir}/.credentials.new"
        fi
    fi

    # Commit credentials atomically: merge with stored entries, then keep the
    # union aligned to the final plan (entries for users being dropped are
    # pruned later by pf_users_commit_managed, after the engine drop succeeds).
    if [ -f "${state_dir}/.credentials.new" ]; then
        { cat "${state_dir}/credentials" 2>/dev/null || true; cat "${state_dir}/.credentials.new" 2>/dev/null || true; } \
            | awk -F= '!seen[$1]++ { print }' > "${state_dir}/.credentials.merged"
        mv -f "${state_dir}/.credentials.merged" "${state_dir}/credentials" 2>/dev/null || true
        rm -f "${state_dir}/.credentials.new"
        chmod 600 "${state_dir}/credentials" 2>/dev/null || true
    fi

    # Export the plan for the engine reconcilers + banner + .env writer.
    PF_USERS="$(printf '%s,' ${final_users[@]+"${final_users[@]}"})"; PF_USERS="${PF_USERS%,}"
    PF_USERS_PRIMARY="${final_users[0]}"
    PF_USERS_MODE="legacy"
    if [ "${PF_USERS_PRIMARY}" != "${legacy_user:-dbuser}" ] || [ "${#final_users[@]}" -gt 1 ]; then
        PF_USERS_MODE="multi"
    fi
    export PF_USERS PF_USERS_PRIMARY PF_USERS_MODE
    local -i n=0
    for u in ${final_users[@]+"${final_users[@]}"}; do
        printf -v "PF_USER_PW_${u^^}" '%s' "${final_pws[${n}]}"
        export "PF_USER_PW_${u^^}"
        n=$((n + 1))
    done
    PF_USERS_NEW="$(printf '%s,' ${new_users[@]+"${new_users[@]}"})"; PF_USERS_NEW="${PF_USERS_NEW%,}"
    export PF_USERS_NEW
    if [ "${#ignore_pws[@]}" -gt 0 ]; then
        warn "Existing users keep their credentials; provided passwords for $(printf '%s, ' ${ignore_pws[@]+"${ignore_pws[@]}"} | sed 's/, $//') were ignored."
    fi
    return 0
}

pf_users_primary_password() {
    local var="PF_USER_PW_${PF_USERS_PRIMARY^^}"
    printf '%s' "${!var:-}"
}

# Aligned "pw1,pw2,..." for .env persistence (double quotes doubled so the
# line stays valid shell when sourced).
pf_users_passwords_csv() {
    local u pw out=""
    local IFS=','
    for u in ${PF_USERS}; do
        pw=$(eval "printf '%s' \"\${PF_USER_PW_${u^^}:-}\"")
        pw="${pw//\"/\\\"}"
        out+="${pw},"
    done
    printf '%s' "${out%,}"
}

# Read/update the root credential tracked in the state file.
pf_users_stored_root() {
    pf_users_stored_password root
}

pf_users_store_root() { # pf_users_store_root <password>
    local state_dir; state_dir=$(pf_users_state_dir)
    local tmp="${state_dir}/.credentials.root"
    { grep -v '^root=' "${state_dir}/credentials" 2>/dev/null || true
      printf 'root=%s\n' "$1"
    } > "${tmp}" 2>/dev/null || true
    mv -f "${tmp}" "${state_dir}/credentials" 2>/dev/null || true
    chmod 600 "${state_dir}/credentials" 2>/dev/null || true
}

# Users present in the previously managed state but missing from the current
# plan -> their accounts must be dropped (databases are preserved).
pf_users_to_drop() { # pf_users_to_drop -> prints users to delete, one per line
    local want prev drop
    while IFS= read -r prev; do
        [ -n "${prev}" ] || continue
        drop=1
        while IFS= read -r want; do
            if [ "${prev}" = "${want}" ]; then drop=0; break; fi
        done <<< "${PF_USERS//,/$'
'}"
        if [ "${drop}" = "1" ]; then printf '%s\n' "${prev}"; fi
    done < <(pf_users_prev_list)
    return 0
}

pf_users_commit_managed() { # pf_users_commit_managed <PF_USERS>
    local state_dir; state_dir=$(pf_users_state_dir)
    printf '%s\n' "${PF_USERS//,/$'\n'}" > "${state_dir}/managed" 2>/dev/null || true
    chmod 600 "${state_dir}/managed" 2>/dev/null || true
    if [ -f "${state_dir}/credentials" ]; then
        local keep tmpc="${state_dir}/.credentials.keep"
        : > "${tmpc}"
        # The root credential line is runtime-managed and always preserved.
        grep -m1 '^root=' "${state_dir}/credentials" >> "${tmpc}" 2>/dev/null || true
        while IFS= read -r keep; do
            [ -n "${keep}" ] || continue
            [ "${keep}" = "root" ] && continue
            grep -m1 "^${keep}=" "${state_dir}/credentials" >> "${tmpc}" 2>/dev/null || true
        done <<< "${PF_USERS//,/$'
'}"
        mv -f "${tmpc}" "${state_dir}/credentials" 2>/dev/null || true
        chmod 600 "${state_dir}/credentials" 2>/dev/null || true
    fi
}

# -----------------------------------------------------------------------------
# Engine reconcilers (called on EVERY boot, after the real server is ready).
# They are additive and idempotent: create missing users/databases, drop
# removed accounts, never touch existing credentials. Failures warn and are
# retried on the next boot - they never block the database from serving.
# -----------------------------------------------------------------------------

_pf_sql_quote() { # single-quote escape for SQL string literals
    printf '%s' "$1" | sed "s/'/''/g"
}

_pf_users_retry() { # _pf_users_retry <max-tries> <cmd...>
    local tries="$1"; shift
    local n=0
    while [ "${n}" -lt "${tries}" ]; do
        if "$@" >/dev/null 2>&1; then return 0; fi
        n=$((n + 1))
        sleep 2
    done
    return 1
}

pf_users_note_unsupported() { # engines without per-user account models
    if [ "${PF_USERS_MODE:-legacy}" = "multi" ]; then
        warn "${PROJECT_TYPE} serves a single admin account: only the primary user '${PF_USERS_PRIMARY}' is provisioned; DB_USERNAMES entries beyond the first are not applicable on this engine."
    fi
    return 0
}

pf_users_is_new() { # pf_users_is_new <user> -> 0 when in PF_USERS_NEW
    printf ',%s,' "${PF_USERS_NEW:-}," | grep -q ",${1},"
}

# --- MariaDB / MySQL ---------------------------------------------------------
pf_users_reconcile_mysql() { # pf_users_reconcile_mysql <client-bin>
    command -v pf_users_plan >/dev/null 2>&1 || return 0
    local client="${1:-mysql}"
    local rootpw="${DB_ROOT_PASSWORD:-}"
    [ -n "${rootpw}" ] || { warn "User reconciliation skipped (no root password available)."; return 0; }

    local -a MYSQL_AUTH=(--protocol=tcp -h 127.0.0.1 -P "${SERVER_PORT:-3306}" -u root -p"${rootpw}" -N)
    if ! _pf_users_retry 15 "${client}" "${MYSQL_AUTH[@]}" -e "SELECT 1"; then
        # The stored root credential may differ (operator rotated the variable).
        local stored_root; stored_root=$(pf_users_stored_root)
        if [ -n "${stored_root}" ] && [ "${stored_root}" != "${rootpw}" ] \
           && "${client}" --protocol=tcp -h 127.0.0.1 -P "${SERVER_PORT:-3306}" -u root -p"${stored_root}" -N -e "SELECT 1" >/dev/null 2>&1; then
            if [ -n "${rootpw}" ]; then
                local qrp; qrp=$(_pf_sql_quote "${rootpw}")
                if "${client}" --protocol=tcp -h 127.0.0.1 -P "${SERVER_PORT:-3306}" -u root -p"${stored_root}" -N -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${qrp}'; ALTER USER IF EXISTS 'root'@'%' IDENTIFIED BY '${qrp}'; FLUSH PRIVILEGES;" >/dev/null 2>&1; then
                    pf_users_store_root "${rootpw}"
                    ok "Root password updated to match the DB_ROOT_PASSWORD startup variable."
                else
                    warn "Could not update the root password (check DB_ROOT_PASSWORD)."
                fi
            else
                rootpw="${stored_root}"
                MYSQL_AUTH=(--protocol=tcp -h 127.0.0.1 -P "${SERVER_PORT:-3306}" -u root -p"${rootpw}" -N)
            fi
        else
            warn "Could not reach ${PROJECT_TYPE^^} as root - user reconciliation skipped this boot."
            return 0
        fi
    fi

    local u pw udb qpw
    if [ "${PF_USERS_MODE:-legacy}" = "multi" ]; then
        local IFS=','
        for u in ${PF_USERS}; do
            pw=$(eval "printf '%s' \"\${PF_USER_PW_${u^^}:-}\"")
            qpw=$(_pf_sql_quote "${pw}")
            udb="${u}_db"
            if "${client}" "${MYSQL_AUTH[@]}" 2>/dev/null <<__EOSQL
CREATE USER IF NOT EXISTS '${u}'@'%' IDENTIFIED BY '${qpw}';
CREATE USER IF NOT EXISTS '${u}'@'localhost' IDENTIFIED BY '${qpw}';
CREATE DATABASE IF NOT EXISTS \`${udb}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON \`${udb}\`.* TO '${u}'@'%';
GRANT ALL PRIVILEGES ON \`${udb}\`.* TO '${u}'@'localhost';
GRANT ALL PRIVILEGES ON \`${DB_NAME:-database}\`.* TO '${u}'@'%';
GRANT ALL PRIVILEGES ON \`${DB_NAME:-database}\`.* TO '${u}'@'localhost';
FLUSH PRIVILEGES;
__EOSQL
            then
                if pf_users_is_new "${u}"; then
                    ok "Created user '${u}' (database: ${udb}, owner)."
                else
                    log "User '${u}' verified (database: ${udb})."
                fi
            else
                warn "Could not provision user '${u}'."
            fi
        done
        unset IFS
    fi

    # Drop removed accounts (their <user>_db database is deliberately kept).
    local dropped
    dropped=$(pf_users_to_drop)
    if [ -n "${dropped}" ]; then
        for u in ${dropped}; do
            if "${client}" "${MYSQL_AUTH[@]}" -e "DROP USER IF EXISTS '${u}'@'%'; DROP USER IF EXISTS '${u}'@'localhost'; FLUSH PRIVILEGES;" >/dev/null 2>&1; then
                warn "Removed user '${u}' (credentials deleted; their database '${u}_db' is preserved for manual review)."
            else
                warn "Could not drop user '${u}' - will retry next boot."
            fi
        done
    fi
    pf_users_commit_managed "${PF_USERS}"
    return 0
}

# --- PostgreSQL --------------------------------------------------------------
pf_users_reconcile_pgsql() { # pf_users_reconcile_pgsql <superuser>
    command -v pf_users_plan >/dev/null 2>&1 || return 0
    local super="${1:-postgres}"
    local rootpw="${DB_ROOT_PASSWORD:-}"
    [ -n "${rootpw}" ] || { warn "User reconciliation skipped (no superuser password available)."; return 0; }

    local -a PG_AUTH=(-w -h 127.0.0.1 -p "${SERVER_PORT:-5432}" -U "${super}" -d postgres -v ON_ERROR_STOP=0)
    export PGPASSWORD="${rootpw}"
    if ! _pf_users_retry 15 psql "${PG_AUTH[@]}" -Atc "SELECT 1"; then
        # The stored root credential may differ (operator rotated the variable).
        local stored_root; stored_root=$(pf_users_stored_root)
        if [ -n "${stored_root}" ] && [ "${stored_root}" != "${rootpw}" ]; then
            PGPASSWORD="${stored_root}"
            if _pf_users_retry 5 psql "${PG_AUTH[@]}" -Atc "SELECT 1"; then
                if [ -n "${rootpw}" ]; then
                    local qrp; qrp=$(_pf_sql_quote "${rootpw}")
                    if psql "${PG_AUTH[@]}" -c "ALTER ROLE \"${super}\" WITH PASSWORD '${qrp}';" >/dev/null 2>&1; then
                        pf_users_store_root "${rootpw}"
                        ok "Root password updated to match the DB_ROOT_PASSWORD startup variable."
                    else
                        warn "Could not update the root password (check DB_ROOT_PASSWORD)."
                    fi
                fi
                PGPASSWORD="${rootpw}"
            else
                unset PGPASSWORD
                warn "Could not reach PostgreSQL as '${super}' - user reconciliation skipped this boot."
                return 0
            fi
        else
            unset PGPASSWORD
            warn "Could not reach PostgreSQL as '${super}' - user reconciliation skipped this boot."
            return 0
        fi
    fi

    local u pw udb qpw
    if [ "${PF_USERS_MODE:-legacy}" = "multi" ]; then
        local IFS=','
        for u in ${PF_USERS}; do
            pw=$(eval "printf '%s' \"\${PF_USER_PW_${u^^}:-}\"")
            qpw=$(_pf_sql_quote "${pw}")
            udb="${u}_db"
            local exists
            exists=$(psql "${PG_AUTH[@]}" -Atc "SELECT 1 FROM pg_roles WHERE rolname='${u}'" 2>/dev/null)
            if [ "${exists}" != "1" ]; then
                if psql "${PG_AUTH[@]}" -c "CREATE ROLE \"${u}\" LOGIN PASSWORD '${qpw}';" >/dev/null 2>&1; then
                    ok "Created user '${u}' (database: ${udb}, owner)."
                else
                    warn "Could not provision user '${u}'."
                fi
            else
                log "User '${u}' verified (database: ${udb})."
            fi
            if ! psql "${PG_AUTH[@]}" -Atc "SELECT 1 FROM pg_database WHERE datname='${udb}'" 2>/dev/null | grep -q 1; then
                psql "${PG_AUTH[@]}" -c "CREATE DATABASE \"${udb}\" OWNER \"${u}\" ENCODING 'UTF8';" >/dev/null 2>&1 || true
            fi
            psql "${PG_AUTH[@]}" -c "GRANT ALL PRIVILEGES ON DATABASE \"${DB_NAME:-postgres}\" TO \"${u}\";" >/dev/null 2>&1 || true
            psql -h 127.0.0.1 -p "${SERVER_PORT:-5432}" -U "${super}" -d "${DB_NAME:-postgres}" \
                -c "GRANT ALL ON SCHEMA public TO \"${u}\";" >/dev/null 2>&1 || true
        done
        unset IFS
    fi

    local dropped
    dropped=$(pf_users_to_drop)
    if [ -n "${dropped}" ]; then
        for u in ${dropped}; do
            udb="${u}_db"
            psql "${PG_AUTH[@]}" -c "ALTER DATABASE \"${udb}\" OWNER TO \"${super}\";" >/dev/null 2>&1 || true
            psql -h 127.0.0.1 -p "${SERVER_PORT:-5432}" -U "${super}" -d "${udb}" \
                -c "REASSIGN OWNED BY \"${u}\" TO \"${super}\"; DROP OWNED BY \"${u}\";" >/dev/null 2>&1 || true
            psql -h 127.0.0.1 -p "${SERVER_PORT:-5432}" -U "${super}" -d "${DB_NAME:-postgres}" \
                -c "REASSIGN OWNED BY \"${u}\" TO \"${super}\"; DROP OWNED BY \"${u}\";" >/dev/null 2>&1 || true
            if psql "${PG_AUTH[@]}" -c "DROP ROLE IF EXISTS \"${u}\";" >/dev/null 2>&1; then
                warn "Removed user '${u}' (credentials deleted; their database '${udb}' is preserved for manual review)."
            else
                warn "Could not drop user '${u}' - will retry next boot."
            fi
        done
    fi
    unset PGPASSWORD
    pf_users_commit_managed "${PF_USERS}"
    return 0
}

# --- MongoDB -----------------------------------------------------------------
pf_users_reconcile_mongo() { # pf_users_reconcile_mongo <mongosh-bin>
    command -v pf_users_plan >/dev/null 2>&1 || return 0
    local msh="${1:-mongosh}"
    local rootpw="${DB_ROOT_PASSWORD:-}"
    [ -n "${rootpw}" ] || { warn "User reconciliation skipped (no root password available)."; return 0; }

    local -a M_AUTH=(--quiet --port "${SERVER_PORT:-27017}" -u root -p "${rootpw}" --authenticationDatabase admin)
    if ! _pf_users_retry 15 "${msh}" "${M_AUTH[@]}" admin --eval "db.adminCommand('ping')"; then
        # The stored root credential may differ (operator rotated the variable).
        local stored_root; stored_root=$(pf_users_stored_root)
        if [ -n "${stored_root}" ] && [ "${stored_root}" != "${rootpw}" ] \
           && "${msh}" --quiet --port "${SERVER_PORT:-27017}" -u root -p "${stored_root}" --authenticationDatabase admin --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
            if [ -n "${rootpw}" ]; then
                if "${msh}" --quiet --port "${SERVER_PORT:-27017}" -u root -p "${stored_root}" --authenticationDatabase admin --eval "db.changeUserPassword('root', '${rootpw}')" >/dev/null 2>&1; then
                    pf_users_store_root "${rootpw}"
                    ok "Root password updated to match the DB_ROOT_PASSWORD startup variable."
                else
                    warn "Could not update the root password (check DB_ROOT_PASSWORD)."
                fi
            else
                rootpw="${stored_root}"
                M_AUTH=(--quiet --port "${SERVER_PORT:-27017}" -u root -p "${rootpw}" --authenticationDatabase admin)
            fi
        else
            warn "Could not reach MongoDB as root - user reconciliation skipped this boot."
            return 0
        fi
    fi

    local u pw udb
    if [ "${PF_USERS_MODE:-legacy}" = "multi" ]; then
        local IFS=','
        for u in ${PF_USERS}; do
            pw=$(eval "printf '%s' \"\${PF_USER_PW_${u^^}:-}\"")
            udb="${u}_db"
            local exists
            exists=$("${msh}" "${M_AUTH[@]}" "${udb}" --eval "db.getUser('${u}') ? '1' : '0'" 2>/dev/null | tail -n1)
            if [ "${exists}" != "1" ]; then
                if "${msh}" "${M_AUTH[@]}" "${udb}" >/dev/null 2>&1 <<__EOSCRIPT
db.createUser({
  user: "${u}",
  pwd: "${pw}",
  roles: [ { role: "dbOwner", db: "${udb}" }, { role: "readWrite", db: "${DB_NAME:-database}" }, { role: "dbAdmin", db: "${DB_NAME:-database}" } ]
});
__EOSCRIPT
                then
                    ok "Created user '${u}' (database: ${udb}, owner)."
                else
                    warn "Could not provision user '${u}'."
                fi
            else
                log "User '${u}' verified (database: ${udb})."
            fi
        done
        unset IFS
    fi

    local dropped
    dropped=$(pf_users_to_drop)
    if [ -n "${dropped}" ]; then
        for u in ${dropped}; do
            udb="${u}_db"
            if "${msh}" "${M_AUTH[@]}" "${udb}" --eval "db.dropUser('${u}')" >/dev/null 2>&1; then
                warn "Removed user '${u}' (credentials deleted; their database '${udb}' is preserved for manual review)."
            else
                warn "Could not drop user '${u}' - will retry next boot."
            fi
        done
    fi
    pf_users_commit_managed "${PF_USERS}"
    return 0
}
