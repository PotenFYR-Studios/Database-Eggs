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

# Accepts 'owner/repo', 'https://github.com/owner/repo(.git)', with optional
# 'git@github.com:owner/repo.git' SSH form rewritten to https. Prints the
# normalized https URL and host kind ('github'|'generic') separated by a space.
_pf_sync_normalize_url() {
    local raw="$1" url kind="generic" host
    raw="${raw%%#*}"; raw="${raw%%\?*}"
    raw="${raw%.git}"
    case "${raw}" in
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

# Latest remote commit sha for the tracked branch. Prints the sha on stdout.
_pf_sync_remote_head() { # _pf_sync_remote_head <url> <kind> <branch>
    local url="$1" kind="$2" branch="$3" sha=""
    if command -v git >/dev/null 2>&1; then
        local reflist
        local -a git_auth=()
        if [ -n "${GIT_TOKEN:-}" ]; then
            git_auth=(-c "http.extraheader=Authorization: Basic $(printf 'x-access-token:%s' "${GIT_TOKEN}" | base64 2>/dev/null | tr -d '\n')")
        fi
        local ref="HEAD"
        [ -n "${branch}" ] && ref="refs/heads/${branch}"
        reflist=$(git "${git_auth[@]}" ls-remote "${url}" "${ref}" 2>/dev/null)
        sha=$(printf '%s' "${reflist}" | awk 'NR==1{print $1}')
        if [ -z "${sha}" ] && [ -z "${branch}" ]; then
            # Some servers do not resolve symref HEAD; fall back to refs/heads/*
            sha=$(git "${git_auth[@]}" ls-remote "${url}" 2>/dev/null | awk '/refs\/heads\//{print $1; exit}')
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
        return 0
    fi

    # Up to date: same repo, same commit, code actually present.
    if [ "${has_manifest}" = "1" ] && [ "${last_repo}" = "${url}" ] \
       && [ -n "${remote_head}" ] && [ "${last_commit}" = "${remote_head}" ]; then
        ok "Repository code is up to date (commit ${remote_head:0:9})."
        return 0
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
        local -a git_auth=()
        if [ -n "${GIT_TOKEN:-}" ]; then
            git_auth=(-c "http.extraheader=Authorization: Basic $(printf 'x-access-token:%s' "${GIT_TOKEN}" | base64 2>/dev/null | tr -d '\n')")
        fi
        local -a clone_args=(--depth 1 --single-branch)
        [ -n "${branch}" ] && clone_args+=(--branch "${branch}")
        if git "${git_auth[@]}" clone "${clone_args[@]}" "${url}" "${stage}/repo" >/dev/null 2>&1; then
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
            return 0
        fi
    fi

    # --- Install staged tree into the workspace ------------------------------
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
        rm -rf "${SERVER_DIR:?}/${rel}" 2>/dev/null || true
        if cp -a "${stage}/out/${rel}" "${SERVER_DIR}/${rel}" 2>/dev/null; then
            printf '%s\n' "${rel}" >> "${new_manifest}"
        fi
    done

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
    fi
    rm -rf "${stage}" 2>/dev/null || true
    return 0
}
