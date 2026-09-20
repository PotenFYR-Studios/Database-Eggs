#!/bin/bash
# =============================================================================
#  PotenFYR Studios - Git Repository Sync Engine (db-init-git.sh)
# =============================================================================
# Clones/updates a user Git repository into the server workspace on startup.
#
# Startup variables (defined in egg-database-multi.json):
#   GIT_REPO_URL          - https GitHub URL or 'owner/repo' shorthand (user)
#   GIT_BRANCH            - branch to track (empty = repo default)          (user)
#   GIT_TOKEN             - access token; injected by admins only          (admin)
#   GIT_ARCHIVE_ON_UPDATE - 1 = snapshot old code into ./archive/git-sync/
#                           before applying new commits (default 1)
#
# Behaviour:
#   * First boot  : repo is cloned (git) or downloaded (tarball) fresh.
#   * New commits : previous code is archived, the tracked files are replaced,
#                   and the console states exactly what happened.
#   * No changes  : one cheap metadata lookup, nothing is touched.
#   * Never touches database data: .env, data/, bin/, logs/, config/, run/,
#     .logs/, archive/, .runtimes/, .profile, .bashrc are always preserved.
#   * Failure of any step is non-fatal: previously synced code keeps running.
# =============================================================================

# Directories/files the sync engine must never create, overwrite, or delete.
_PF_SYNC_PROTECTED='.env
.profile
.bashrc
data
bin
logs
config
run
archive
.logs
.runtimes
.git-sync'

_pf_sync_is_protected() { # _pf_sync_is_protected <relative-path>
    local seg="${1%%/*}" rest
    case "${seg}" in
        .|..|"") return 0 ;;
    esac
    while IFS= read -r rest; do
        [ "${seg}" = "${rest}" ] && return 0
    done <<EOF
${_PF_SYNC_PROTECTED}
EOF
    return 1
}

# ---------------------------------------------------------------------------
# GIT_PRESERVE_ENV (default 1): credentials must survive repo updates. Every
# .env currently in the workspace is snapshotted before the new tree lands
# and copied back to its original location afterwards, so a repo-shipped .env
# can never clobber or wipe live credentials and the database project keeps
# working. Set GIT_PRESERVE_ENV=0 to let the repository's .env files win.
_pf_sync_preserve_env_enabled() {
    [ "${GIT_PRESERVE_ENV:-1}" = "1" ]
}

_pf_sync_snapshot_env() { # _pf_sync_snapshot_env <workspace> <backup-dir>
    _pf_sync_preserve_env_enabled || return 0
    rm -rf "$2" 2>/dev/null || true
    mkdir -p "$2" 2>/dev/null || return 0
    ( cd "$1" 2>/dev/null || exit 0
      find . -type f -name .env -not -path './archive/*' -not -path './.git-sync/*' \
             -not -path './.runtimes/*' -not -path './node_modules/*' 2>/dev/null | sed 's#^\./##'
    ) 2>/dev/null | while IFS= read -r _rel; do
        [ -n "${_rel}" ] || continue
        mkdir -p "$2/$(dirname "${_rel}")" 2>/dev/null || true
        cp -f "$1/${_rel}" "$2/${_rel}" 2>/dev/null || true
    done
}

_pf_sync_restore_env() { # _pf_sync_restore_env <workspace> <backup-dir>
    _pf_sync_preserve_env_enabled || return 0
    [ -d "$2" ] || return 0
    local _restored=0 _rel
    while IFS= read -r _rel; do
        [ -n "${_rel}" ] || continue
        mkdir -p "$1/$(dirname "${_rel}")" 2>/dev/null || true
        if cp -f "$2/${_rel}" "$1/${_rel}" 2>/dev/null; then
            _restored=$((_restored + 1))
        fi
    done < <( cd "$2" 2>/dev/null && find . -type f 2>/dev/null | sed 's#^\./##' )
    if [ "${_restored}" -gt 0 ]; then
        ok "Preserved ${_restored} existing .env file(s) across the update (GIT_PRESERVE_ENV)."
    fi
    rm -rf "$2" 2>/dev/null || true
    return 0
}

# ---------------------------------------------------------------------------
# GIT_EXCLUDE: user-configurable, whitespace/comma-separated glob patterns
# (matched against repo-relative paths) that git sync must never install or
# overwrite - e.g. GIT_EXCLUDE="config/custom/* secrets". Everything else is
# synced normally.
_pf_sync_is_user_excluded() { # _pf_sync_is_user_excluded <relative-path>
    local _pat
    local _list="${GIT_EXCLUDE:-}"
    for _pat in ${_list//,/ }; do
        case "${1}" in
            ${_pat}|${_pat}/*) return 0 ;;
        esac
    done
    return 1
}

# Accepts 'owner/repo', 'https://github.com/owner/repo(.git)', with optional
# 'git@github.com:owner/repo.git' SSH form rewritten to https. Prints the
# normalized https URL and host kind ('github'|'generic') separated by a space.
# file:// and loopback http(s) URLs pass through untouched (kind=generic) so
# self-hosted GitLab/Gitea instances and hermetic tests work.
_pf_sync_normalize_url() {
    local raw="$1" url kind="generic" host
    raw="${raw%%#*}"; raw="${raw%%\?*}"
    raw="${raw%.git}"
    case "${raw}" in
        file://*)
            printf '%s generic\n' "${raw}"; return 0 ;;
        http://localhost[:/]*|http://127.0.0.1[:/]*|https://localhost[:/]*|https://127.0.0.1[:/]*)
            printf '%s generic\n' "${raw}"; return 0 ;;
        http://*)  raw="${raw#http://}" ;;
        https://*) raw="${raw#https://}" ;;
        ssh://*)   raw="${raw#ssh://}" ;;
        git@*)     raw="${raw#git@}"; raw="${raw/://}" ;;   # git@host:o/r -> host/o/r
    esac
    host="${raw%%/*}"
    case "${host}" in
        *.*|*:*|localhost) : ;;              # already a hostname
        *) raw="github.com/${raw}" ;;        # bare owner/repo shorthand
    esac
    url="https://${raw}"
    case "${url}" in
        https://github.com/*) kind="github" ;;
    esac
    printf '%s %s\n' "${url}" "${kind}"
}

_pf_sync_auth_header() { # prints curl-style auth header args when a token is set
    if [ -n "${GIT_TOKEN:-}" ]; then
        printf 'Authorization: Bearer %s\n' "${GIT_TOKEN}"
    fi
}

# Isolated global git config for every git call we make: marks arbitrary
# staging dirs safe (git >= 2.35.2 refuses repos owned by a different uid,
# which silently blocked updates on root-installed/panel-booted servers) and
# pins a sane default branch for inits. MERGES the user's real global config.
_pf_sync_git_env() {
    if [ -z "${GIT_CONFIG_GLOBAL:-}" ]; then
        local _cfg
        _cfg="$(mktemp 2>/dev/null || echo "/tmp/potenfyr-gitconfig.$$")"
        {
            [ -f "${HOME}/.gitconfig" ] && cat "${HOME}/.gitconfig" 2>/dev/null
            printf '[safe]\n\tdirectory = *\n'
            printf '[init]\n\tdefaultBranch = main\n'
        } > "${_cfg}" 2>/dev/null || true
        export GIT_CONFIG_GLOBAL="${_cfg}"
    fi
}

# git auth args from GIT_TOKEN. When $1 is "anon" an EMPTY array is printed
# usage path - callers retry anonymously so a revoked/expired token cannot
# take PUBLIC repositories down with it (a 401 challenge recovers, a 404
# "not found" for token-less repos does not).
_pf_sync_git_auth() { # prints "-c key=value" args; pass "anon" to skip auth
    if [ "${1:-}" != "anon" ] && [ -n "${GIT_TOKEN:-}" ]; then
        printf '%s\n' "-c" "http.extraheader=Authorization: Basic $(printf 'x-access-token:%s' "${GIT_TOKEN}" | base64 2>/dev/null | tr -d '\n')"
    fi
}

# Latest remote commit sha for the tracked branch. Prints the sha on stdout.
_pf_sync_remote_head() { # _pf_sync_remote_head <url> <kind> <branch>
    local url="$1" kind="$2" branch="$3" sha=""
    if command -v git >/dev/null 2>&1; then
        local reflist auth_args
        _pf_sync_git_env
        auth_args=($(_pf_sync_git_auth))
        local ref="HEAD"
        [ -n "${branch}" ] && ref="refs/heads/${branch}"
        reflist=$(git "${auth_args[@]}" ls-remote "${url}" "${ref}" 2>/dev/null)
        if [ -z "${reflist}" ] && [ -n "${GIT_TOKEN:-}" ]; then
            # Authenticated ls-remote failed - retry anonymously so a
            # revoked/expired token cannot break PUBLIC repositories.
            reflist=$(git $(_pf_sync_git_auth anon) ls-remote "${url}" "${ref}" 2>/dev/null)
        fi
        sha=$(printf '%s' "${reflist}" | awk 'NR==1{print $1}')
        if [ -z "${sha}" ] && [ -z "${branch}" ]; then
            # Some servers do not resolve symref HEAD; fall back to refs/heads/*
            sha=$(git $(_pf_sync_git_auth) ls-remote "${url}" 2>/dev/null | awk '/refs\/heads\//{print $1; exit}')
        fi
        [ -n "${sha}" ] && { printf '%s' "${sha}"; return 0; }
    fi
    case "${kind}" in
        github)
            local repo_path="${url#https://github.com/}" api commit_body
            api="https://api.github.com/repos/${repo_path}"
            [ -n "${branch}" ] && api="${api}/commits/${branch}" || api="${api}/commits/HEAD"
            commit_body=$(_pf_fetch "${api}") || return 1
            sha=$(printf '%s' "${commit_body}" | _json_field '"sha"')
            [ -n "${sha}" ] || return 1
            printf '%s' "${sha}"
            return 0
            ;;
    esac
    return 1
}

_pf_fetch() { # _pf_fetch <url> [outfile] - authenticated fetch via curl or wget
    local url="$1" out="${2:--}"
    local hdr
    hdr=$(_pf_sync_auth_header)
    if command -v curl >/dev/null 2>&1; then
        if [ "${out}" = "-" ]; then
            [ -n "${hdr}" ] && curl -fsSL --retry 2 --max-time 60 -H "${hdr}" "${url}" 2>/dev/null \
                || curl -fsSL --retry 2 --max-time 60 "${url}" 2>/dev/null
        else
            { [ -n "${hdr}" ] && curl -fsSL --retry 2 --max-time 120 -H "${hdr}" -o "${out}" "${url}" 2>/dev/null \
                || curl -fsSL --retry 2 --max-time 120 -o "${out}" "${url}" 2>/dev/null; } && [ -s "${out}" ]
        fi
    elif command -v wget >/dev/null 2>&1; then
        if [ "${out}" = "-" ]; then
            [ -n "${hdr}" ] && wget -qO- --header "${hdr}" "${url}" 2>/dev/null || wget -qO- "${url}" 2>/dev/null
        else
            { [ -n "${hdr}" ] && wget -qO "${out}" --header "${hdr}" "${url}" 2>/dev/null \
                || wget -qO "${out}" "${url}" 2>/dev/null; } && [ -s "${out}" ]
        fi
    else
        return 127
    fi
}

# Extract a JSON string field without jq (first match).
_json_field() {
    grep -oE "${1}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -n1 | sed -E "s/.*\"[^\"]*\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/"
}

# Fetch repo tree as tarball into <dest-dir> (files land directly in dest-dir).
_pf_sync_tarball() { # _pf_sync_tarball <url> <kind> <branch> <dest-dir>
    local url="$1" kind="$2" branch="$3" dest="$4" tmp turl
    tmp=$(mktemp 2>/dev/null) || return 1
    case "${kind}" in
        github)
            local repo_path="${url#https://github.com/}"
            if [ -n "${branch}" ]; then
                turl="https://codeload.github.com/${repo_path}/tar.gz/refs/heads/${branch}"
            else
                turl="https://codeload.github.com/${repo_path}/tar.gz"
            fi
            ;;
        *)
            rm -f "${tmp}"; return 1 ;;   # generic hosts require the git binary
    esac
    if ! _pf_fetch "${turl}" "${tmp}"; then
        rm -f "${tmp}"; return 1
    fi
    mkdir -p "${dest}"
    if ! tar -xzf "${tmp}" -C "${dest}" --strip-components=1 2>/dev/null; then
        rm -rf "${dest}" "${tmp}"; return 1
    fi
    rm -f "${tmp}"
    return 0
}

sync_git_repo() {
    [ -n "${GIT_REPO_URL:-}" ] || return 0

    local url kind branch
    { read -r url kind <<< "$(_pf_sync_normalize_url "${GIT_REPO_URL}")"; } || return 0
    [ -n "${url}" ] || return 0
    branch="${GIT_BRANCH:-}"
    branch="${branch//[$'\r\n']/}"
    branch="${branch##refs/heads/}"

    local state_dir="${SERVER_DIR}/.git-sync"
    mkdir -p "${state_dir}" 2>/dev/null || { warn "Git sync: cannot create state dir; skipping."; return 0; }

    local m_repo="${state_dir}/repo" m_branch="${state_dir}/branch" m_commit="${state_dir}/commit" m_manifest="${state_dir}/manifest"
    local last_repo last_branch last_commit
    last_repo="$(cat "${m_repo}" 2>/dev/null || true)"
    last_branch="$(cat "${m_branch}" 2>/dev/null || true)"
    last_commit="$(cat "${m_commit}" 2>/dev/null || true)"
    local has_manifest=0
    [ -s "${m_manifest}" ] && has_manifest=1

    phase "Git Repository Sync"
    log "Checking ${url}$([ -n "${branch}" ] && printf ' (branch: %s)' "${branch}")..."

    local remote_head
    if ! remote_head=$(_pf_sync_remote_head "${url}" "${kind}" "${branch}"); then
        if [ "${has_manifest}" = "1" ]; then
            warn "Could not reach the repository - keeping previously synced code (commit ${last_commit:-unknown})."
        else
            warn "Could not reach the repository and no synced code exists yet - continuing without repo content."
        fi
        return 1
    fi

    # Up to date: same repo, same commit, code actually still present.
    # The manifest is re-verified against the workspace: a panel file-manager
    # deletion or a failed earlier extract must not be mistaken for "current".
    if [ "${has_manifest}" = "1" ] && [ "${last_repo}" = "${url}" ] \
       && [ -n "${remote_head}" ] && [ "${last_commit}" = "${remote_head}" ]; then
        local mf present=0
        while IFS= read -r mf; do
            [ -n "${mf}" ] && [ -e "${SERVER_DIR}/${mf}" ] && { present=1; break; }
        done < "${m_manifest}"
        if [ "${present}" = "1" ]; then
            ok "Repository code is up to date (commit ${remote_head:0:9})."
            return 0
        fi
        warn "Synced files are missing from the workspace although the commit matches - re-downloading."
    fi

    # --- Update path: archive current synced code before replacing it --------
    local f
    if [ "${has_manifest}" = "1" ] && [ -n "${last_commit}" ]; then
        if [ "${last_repo}" != "${url}" ]; then
            warn "Repository changed (${last_repo:-none} -> ${url}) - replacing synced code."
        else
            log "New commits detected (${last_commit:0:9} -> ${remote_head:0:9})."
        fi
        if [ "${GIT_ARCHIVE_ON_UPDATE:-1}" = "1" ]; then
            local adir="${SERVER_DIR}/archive/git-sync" ts out
            mkdir -p "${adir}" 2>/dev/null || true
            ts=$(date -u +%Y%m%d-%H%M%S 2>/dev/null || echo manual)
            out="${adir}/code-${ts}.tar.gz"
            # Archive exactly the files the sync engine manages.
            local -a files=()
            while IFS= read -r f; do
                [ -n "${f}" ] && [ -e "${SERVER_DIR}/${f}" ] && files+=("${f}")
            done < "${m_manifest}"
            if [ "${#files[@]}" -gt 0 ]; then
                if tar -czf "${out}.tmp" -C "${SERVER_DIR}" "${files[@]}" 2>/dev/null && [ -s "${out}.tmp" ]; then
                    mv -f "${out}.tmp" "${out}"
                    ok "Archived previous code -> ${out#"${SERVER_DIR}"/}"
                else
                    rm -f "${out}.tmp" 2>/dev/null || true
                    warn "Could not archive previous code - update aborted (old code kept)."
                    return 0
                fi
            fi
        fi
        # Remove previously synced files so upstream deletions propagate.
        while IFS= read -r f; do
            [ -n "${f}" ] || continue
            _pf_sync_is_protected "${f}" && continue
            rm -rf "${SERVER_DIR:?}/${f}" 2>/dev/null || true
        done < "${m_manifest}"
    fi

    # --- Download fresh tree into a staging dir ------------------------------
    local stage
    stage=$(mktemp -d 2>/dev/null) || { warn "Git sync: mktemp failed - keeping current code."; return 0; }
    local dl_ok=0
    if command -v git >/dev/null 2>&1; then
        _pf_sync_git_env
        local -a clone_args=(--depth 1 --single-branch)
        [ -n "${branch}" ] && clone_args+=(--branch "${branch}")
        if git $(_pf_sync_git_auth) clone "${clone_args[@]}" "${url}" "${stage}/repo" >/dev/null 2>&1; then
            :
        elif [ -n "${GIT_TOKEN:-}" ] \
                && git $(_pf_sync_git_auth anon) clone "${clone_args[@]}" "${url}" "${stage}/repo" >/dev/null 2>&1; then
            # Authenticated clone failed - anonymous clone succeeded: the
            # repository is public and the token is dead/insufficient. The
            # public content still updates (log it so admins notice).
            warn "Authenticated download failed - public repository synced without the token (check GIT_TOKEN)."
        fi
        if [ -d "${stage}/repo" ]; then
            rm -rf "${stage}/repo/.git" 2>/dev/null || true
            # Moving the tree root would hit protected dirs; copy contents instead.
            mkdir -p "${stage}/out"
            if ( cd "${stage}/repo" && shopt -s dotglob nullglob && \
                 items=( * ); [ "${#items[@]}" -eq 0 ] || cp -a -- "${items[@]}" "${stage}/out"/ ); then
                dl_ok=1
            fi
        fi
    fi
    if [ "${dl_ok}" != "1" ]; then
        if _pf_sync_tarball "${url}" "${kind}" "${branch}" "${stage}/out"; then
            dl_ok=1
        else
            rm -rf "${stage}"
            if [ "${has_manifest}" = "1" ]; then
                warn "Download failed - previous code restored/kept (commit ${last_commit})."
            else
                warn "Download failed - continuing without repo content."
            fi
            return 1
        fi
    fi

    # --- Install staged tree into the workspace ------------------------------
    _pf_sync_snapshot_env "${SERVER_DIR}" "${state_dir}/env-backup"
    local new_manifest="${state_dir}/.manifest.new"
    : > "${new_manifest}" 2>/dev/null || true
    local rel
    (
        cd "${stage}/out" 2>/dev/null || exit 1
        find . -mindepth 1 -maxdepth 1 | sed 's#^\./##' | sort
    ) 2>/dev/null | while IFS= read -r rel; do
        [ -n "${rel}" ] || continue
        if _pf_sync_is_protected "${rel}"; then
            warn "Git sync: skipping protected path '${rel}' (managed by the runtime)."
            continue
        fi
        if _pf_sync_is_user_excluded "${rel}"; then
            warn "Git sync: skipping '${rel}' (matched GIT_EXCLUDE)."
            continue
        fi
        rm -rf "${SERVER_DIR:?}/${rel}" 2>/dev/null || true
        if cp -a "${stage}/out/${rel}" "${SERVER_DIR}/${rel}" 2>/dev/null; then
            printf '%s\n' "${rel}" >> "${new_manifest}"
        fi
        # GIT_EXCLUDE sub-path pruning: this engine installs top-level dirs
        # wholesale, so a copied dir may contain paths the user excluded -
        # remove them right after the copy lands.
        if [ -n "${GIT_EXCLUDE:-}" ]; then
            (
                cd "${SERVER_DIR}/${rel}" 2>/dev/null || exit 0
                find . -mindepth 1 2>/dev/null | sed 's#^\./##'
            ) 2>/dev/null | while IFS= read -r _sub; do
                if _pf_sync_is_user_excluded "${rel}/${_sub}"; then
                    rm -rf "${SERVER_DIR:?}/${rel}/${_sub}" 2>/dev/null || true
                fi
            done
        fi
    done
    _pf_sync_restore_env "${SERVER_DIR}" "${state_dir}/env-backup"

    # Roll-forward safety: manifest must exist and be non-empty for a code repo.
    if [ -s "${new_manifest}" ]; then
        mv -f "${new_manifest}" "${m_manifest}" 2>/dev/null || true
        printf '%s\n' "${url}" > "${m_repo}"
        printf '%s\n' "${branch}" > "${m_branch}"
        printf '%s\n' "${remote_head}" > "${m_commit}"
        ok "Repository code installed at commit ${remote_head:0:9} (branch: ${branch:-default})."
    else
        rm -f "${new_manifest}"
        warn "Nothing was extracted from the repository (empty tree?) - workspace left unchanged."
        return 1
    fi
    rm -rf "${stage}" 2>/dev/null || true
    return 0
}

# ---------------------------------------------------------------------------
# Git Auto-Update watcher: keep repo-managed files current while the server
# runs. Database daemons load code/config at start, so new commits are synced
# into the workspace immediately and a one-time console notice tells the
# operator a restart is needed to load them - the running daemon is never
# killed automatically (data safety first). Disable with GIT_AUTO_UPDATE=0;
# cadence via GIT_POLL_SECONDS (30-86400, default 300).
# ---------------------------------------------------------------------------
run_git_update_watcher() {
    local poll="${GIT_POLL_SECONDS:-300}"
    case "${poll}" in ''|*[!0-9]*) poll=300 ;; esac
    [ "${poll}" -lt 30 ] && poll=30
    [ "${poll}" -gt 86400 ] && poll=86400
    local fails=0
    while :; do
        sleep "${poll}"
        if sync_git_repo; then
            fails=0
        else
            fails=$((fails + 1))
            [ "${fails}" = "1" ] && warn "Git Auto-Update: poll failed - will keep retrying quietly (see .logs/launcher-errors.log)."
        fi
    done
}

start_git_update_watcher() {
    [ "${GIT_AUTO_UPDATE:-1}" = "1" ] || return 0
    [ -n "${GIT_REPO_URL:-}" ] || return 0
    command -v git >/dev/null 2>&1 || return 0
    (
        run_git_update_watcher
    ) &
    GIT_AUTO_UPDATE_PID=$!
    local poll="${GIT_POLL_SECONDS:-300}"
    case "${poll}" in ''|*[!0-9]*) poll=300 ;; esac
    [ "${poll}" -lt 30 ] && poll=30
    [ "${poll}" -gt 86400 ] && poll=86400
    ok "Git Auto-Update watcher active (polling every ${poll}s; new commits are synced - restart to load them)."
}
