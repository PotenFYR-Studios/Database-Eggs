#!/usr/bin/env bash
# =============================================================================
#  PotenFYR Studios - Central Diagnostics & Crash-Safety Library
#
#  Provides unified logging, deep failure traces (stack, sanitized env,
#  resource snapshot), log rotation, and dual-trap crash safety for every
#  runtime component. Designed to be SOURCEd, never executed directly.
#
#  Safety guarantees:
#    * Works with or without `set -u` / `set -e` in the host script
#    * Never leaks credentials (PASSWORD|PASSWD|SECRET|TOKEN|KEY|CREDENTIAL)
#    * Survives read-only volumes (falls back to $HOME/logs, then /tmp)
#    * Recursion-guarded traps; EXIT hook catches silent abnormal terminations
#    * Zero side effects on success paths beyond one small log line
#
#  Knobs:
#    PF_FAIL_FAST=1      ERR trap terminates process after dumping (default 0)
#    PF_FAIL_SLEEP=N     seconds to linger before exit inside pf_fail (default 3)
#    PF_LOG_MAX_BYTES    rotate threshold (default 1048576)
#    PF_DEBUG=1          extra verbose trace lines to console
# =============================================================================

PF_DIAG_VERSION="1.0"

# ---------------------------------------------------------------- logging dir
_pf_log_dir() {
    if [ -n "${_PF_LOG_DIR_CACHE:-}" ]; then printf '%s' "${_PF_LOG_DIR_CACHE}"; return 0; fi
    local d picked=""
    for d in "${SERVER_DIR:-}/logs" "${SERVER_DIR:-}" "${HOME:-}/logs" "/tmp/pf-logs"; do
        [ -n "${d}" ] || continue
        if mkdir -p "${d}" 2>/dev/null && [ -w "${d}" ]; then picked="${d}"; break; fi
    done
    [ -z "${picked}" ] && picked="/tmp"
    case "${picked}" in */logs) : ;; *) mkdir -p "${picked}/logs" 2>/dev/null && picked="${picked}/logs" ;; esac
    _PF_LOG_DIR_CACHE="${picked}"
    printf '%s' "${picked}"
}

PF_LOG_FILE="${PF_LOG_FILE:-$(_pf_log_dir)/startup_error.log}"
PF_INSTALLER_LOG="${PF_INSTALLER_LOG:-$(_pf_log_dir)/installer.log}"

# --------------------------------------------------------------- sanitization
pf_sanitize() {
    local input="$1" out=""
    out=$(printf '%s' "${input}" | sed -E \
        -e 's/(PASSWORD|PASSWD|PASS|SECRET|TOKEN|API[_-]?KEY|MASTER[_-]?KEY|AUTH|CREDENTIALS?)([A-Za-z0-9_]*[=:])[^ ]+/\1\2<masked>/gI' \
        -e 's|(://[^:/@?#]+):[^@/?#]{4,}@|\1:<masked>@|g' \
        -e 's/(-p|--password)[ ]+[^ ]+/\1 <masked>/gI' 2>/dev/null)
    # Never swallow messages if the sanitizer itself fails
    if [ -n "${input}" ] && [ -z "${out}" ]; then
        printf '%s' "${input}"
    else
        printf '%s' "${out}"
    fi
}

# ------------------------------------------------------------------ rotation
_pf_rotate() { # _pf_rotate <file>
    local f="$1" max="${PF_LOG_MAX_BYTES:-1048576}"
    [ -f "${f}" ] || return 0
    local sz
    sz=$(wc -c < "${f}" 2>/dev/null || echo 0)
    [ "${sz}" -gt "${max}" ] || return 0
    tail -c $((max / 2)) "${f}" > "${f}.tmp" 2>/dev/null && mv -f "${f}.tmp" "${f}"
}

# -------------------------------------------------------------- core plumbing
_ts() { date -u +'%Y-%m-%dT%H:%M:%SZ'; }

_pf_prompt() {
    local name="${PANEL_NAME:-${PANEL_TYPE:-panel}}"
    printf 'container@%s' "${name}"
}

_diag() { # _diag <message> <level> [logfile]
    local msg="$1" lvl="$2" dest="${3:-${PF_LOG_FILE}}"
    _pf_rotate "${dest}"
    printf '[%s] [%-5s] %s\n' "$(date -u +'%Y-%m-%d %H:%M:%SZ')" "${lvl}" "$(pf_sanitize "${msg}")" >> "${dest}" 2>/dev/null || true
    [ "${PF_DEBUG:-0}" = "1" ] && printf '[trace][%s] %s\n' "${lvl}" "$(pf_sanitize "${msg}")" >&2
    return 0
}

# Console formatters (house style; degrade gracefully without color vars)
_c() { eval "printf '%s' \"\${${1}:-}\""; }

log()   { printf '\033[36m\033[1m%s~\033[0m \033[1m%s\033[0m\n'     "$(_pf_prompt)" "$(pf_sanitize "$*")"; _diag "$*" INFO; }
ok()    { printf '\033[36m\033[1m%s~\033[0m \033[32m\033[1m[ok]\033[0m %s\n'    "$(_pf_prompt)" "$(pf_sanitize "$*")"; _diag "$*" OK; }
warn()  { printf '\033[36m\033[1m%s~\033[0m \033[33m\033[1m[warn]\033[0m %s\n'  "$(_pf_prompt)" "$(pf_sanitize "$*")" >&2; _diag "$*" WARN; }
error() { printf '\033[36m\033[1m%s~\033[0m \033[31m\033[1m[error]\033[0m %s\n' "$(_pf_prompt)" "$(pf_sanitize "$*")" >&2; _diag "$*" ERROR; }

# ------------------------------------------------------------ trace dumper
pf_stack_lines() { # prints numbered call stack; safe under any bash
    local i depth
    depth=${#FUNCNAME[@]}
    [ "${depth}" -le 1 ] && { printf '  (top-level)\n'; return 0; }
    i=1
    while [ "${i}" -lt "${depth}" ]; do
        printf '  #%d %s (line %s)\n' \
            "$((i - 1))" \
            "${FUNCNAME[${i}]:-main}" \
            "${BASH_LINENO[$((i - 1))]:-?}" 2>/dev/null || break
        i=$((i + 1))
    done
}

pf_dump_diagnostics() { # pf_dump_diagnostics <reason> <exit_code> [logfile]
    local reason="$1" ec="${2:-1}" dest="${3:-${PF_LOG_FILE}}"
    {
        printf '\n=== FAILURE REPORT (%s) ===\n' "$(_ts)"
        printf 'Component   : %s v%s\n' "${PF_COMPONENT:-$(basename "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")}" "${PF_DIAG_VERSION}"
        printf 'Panel       : %s (%s)\n' "${PANEL_NAME:-unknown}" "${PANEL_TYPE:-unknown}"
        printf 'Reason      : %s\n' "$(pf_sanitize "${reason}")"
        printf 'Exit Code   : %s\n' "${ec}"
        printf 'Engine      : %s (requested v%s)\n' "${PROJECT_TYPE:-${DB_TYPE:-${DATABASE_TYPE:-?}}}" "${DB_VERSION:-latest}"
        printf 'Port/Mem    : %s / %s MB | Bind %s\n' "${SERVER_PORT:-?}" "${SERVER_MEMORY:-?}" "${BIND_ADDRESS:-0.0.0.0}"
        printf 'Identity    : uid=%s gid=%s arch=%s root=%s\n' \
            "$(id -u 2>/dev/null || echo '?')" "$(id -g 2>/dev/null || echo '?')" \
            "$(uname -m 2>/dev/null || echo '?')" \
            "$([ "$(id -u 2>/dev/null || echo 1)" = "0" ] && echo yes || echo no)"
        printf 'Workdir     : %s\n' "$(pwd 2>/dev/null || echo '?')"
        printf 'Disk Free   : %s\n' "$(df -h . 2>/dev/null | awk 'NR==2{print $4}')"
        command -v curl >/dev/null 2>&1 && \
            printf 'Network     : %s\n' "$(curl -fsIL --connect-timeout 5 --max-time 8 -o /dev/null https://api.github.com 2>/dev/null && echo reachable || echo unreachable)"
        printf 'Stack Trace :\n'
        pf_stack_lines
        printf 'Last Command: %s\n' "$(pf_sanitize "${BASH_COMMAND:-?}")"
        printf 'Env Snapshot (sanitized):\n'
        env 2>/dev/null | sort | grep -viE 'PASSWORD|PASSWD|SECRET|TOKEN|_KEY|CREDENTIAL|PRIVATE' | sed 's/^/  /'
        printf 'Recent Logs:\n'
        local lf
        for lf in "$(_pf_log_dir)"/*.log; do
            [ -f "${lf}" ] && [ "${lf}" != "${dest}" ] && {
                printf -- '--- %s ---\n' "$(basename "${lf}")"
                tail -n 15 "${lf}" 2>/dev/null
            }
        done
        printf '==============================\n'
    } >> "${dest}" 2>/dev/null || true
}

# ------------------------------------------------------------------- failure
pf_fail() { # pf_fail <message...>  => console box + trace + exit 1
    error "$*"
    printf '\n\033[31m\033[1m[fatal error]\033[0m %s\n\n' "$(pf_sanitize "$*")" >&2
    pf_dump_diagnostics "$*" 1
    local sleep_s="${PF_FAIL_SLEEP:-3}"
    [ "${sleep_s}" -gt 0 ] 2>/dev/null && sleep "${sleep_s}"
    exit 1
}
# House-compatible alias (all existing call sites keep working)
fail() { pf_fail "$@"; }

# ------------------------------------------------------------------- traps
_pf_reported=0

pf_err_trap() {
    local ec=$?
    # Preserve caller flow unless fast-fail requested; still record everything.
    if [ "${ec}" -eq 0 ]; then return 0; fi
    trap - ERR
    _pf_reported=1
    pf_dump_diagnostics "Unhandled ERR trap (exit ${ec}) at ${BASH_SOURCE[1]:-?}:${BASH_LINENO[0]:-?}" "${ec}"
    if [ "${PF_FAIL_FAST:-0}" = "1" ]; then
        error "Unhandled failure (exit ${ec}); see $(basename "${PF_LOG_FILE}")"
        exit "${ec}"
    fi
    warn "Recovered from internal error (exit ${ec}); details logged."
    return "${ec}"
}

pf_exit_hook() {
    local ec=$?
    [ "${ec}" -eq 0 ] && return 0
    [ "${_pf_reported}" -eq 1 ] && return 0
    _pf_reported=1
    pf_dump_diagnostics "Abnormal termination (exit ${ec}, no explicit failure path)" "${ec}"
}

trap 'pf_err_trap' ERR
trap 'pf_exit_hook' EXIT
