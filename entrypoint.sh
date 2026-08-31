#!/bin/bash
# =============================================================================
#  Multi Database - Universal Container Entrypoint
#  By PotenFYR Studios (https://github.com/PotenFYR-Studios/Database-Eggs)
#
#  Multi-Panel Support:
#    - Pterodactyl Panel (Wings Daemon)
#    - Pelican Panel (Pelican Wings)
#    - Feather Panel (feather-panel / renoki-co, detected via P_SERVER_UUID_SHORT)
#    - PufferPanel, Jexactyl / Wisp / Emerald (Wings forks)
#    - Convoy, Cytopanel, AMP
#    - Kubernetes / OpenShift, Railway / Render / Fly.io, plain Docker
# =============================================================================

# --- Security baseline -----------------------------------------------------------
# Files created by the entrypoint are group/other-readable but not writable; core
# dumps are disabled so crashes cannot eat server disk space.
umask 022
ulimit -c 0 2>/dev/null || true

export GOTOOLCHAIN="${GOTOOLCHAIN:-local}"

# -----------------------------------------------------------------------------
# Central Diagnostics Library (logging, traces, crash safety, log rotation)
# -----------------------------------------------------------------------------
PF_COMPONENT="entrypoint"
PF_FAIL_SLEEP=8   # linger so panel consoles capture the fatal message
_src="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/scripts/lib-diagnostics.sh"; [ -f "${_src}" ] && source "${_src}" \
    || source /usr/local/bin/lib-diagnostics.sh \
    || source ./lib-diagnostics.sh \
    || true

# -----------------------------------------------------------------------------
# Universal Panel Detection (Pterodactyl, Pelican, Feather, Wisp, Convoy,
# Cytopanel, Arcadia, Kubernetes/OpenShift, plain Docker, anything else)
# -----------------------------------------------------------------------------
detect_panel() {
    PANEL_TYPE="standalone"
    PANEL_NAME="panel"

    if [ -n "${PANEL_TYPE_OVERRIDE:-}" ]; then
        PANEL_TYPE="${PANEL_TYPE_OVERRIDE}"
    elif [ -n "${KUBERNETES_SERVICE_HOST:-}" ]; then
        if [ -n "${OPENSHIFT_BUILD_NAME:-}" ]; then
            PANEL_TYPE="openshift"
        else
            PANEL_TYPE="kubernetes"
        fi
    elif [ -n "${P_SERVER_UUID:-}" ] || [ -n "${SERVER_UUID:-}" ] || [ -n "${P_SERVER_LOCATION:-}" ] || [ -f "/etc/pterodactyl/config.json" ]; then
        # Wings-family discrimination:
        #   Feather Panel injects P_SERVER_UUID plus a Feather-only short UUID
        #   (P_SERVER_UUID_SHORT). Pelican uses P_SERVER_UUID without it.
        if [ -n "${P_SERVER_UUID_SHORT:-}" ]; then
            PANEL_TYPE="feather"
        elif [ -n "${PELICAN_PANEL_VERSION:-}" ] || { [ -n "${P_SERVER_UUID:-}" ] && [ -z "${SERVER_UUID:-}" ]; }; then
            PANEL_TYPE="pelican"      # Wings v2 environment variables
        elif [ -n "${JEXACTYL_VERSION:-}" ] || [ -f "/etc/jexactyl/config.json" ]; then
            PANEL_TYPE="jexactyl"
        elif [ -n "${WISP_PANEL_VERSION:-}" ] || [ -f "/etc/wisp/config.json" ]; then
            PANEL_TYPE="wisp"
        else
            PANEL_TYPE="pterodactyl"  # classic wings
        fi
    elif [ -n "${EMERALD_SRV_UUID:-}" ]; then
        PANEL_TYPE="emerald"
    elif [ -n "${WISP_SERVER_UUID:-}" ] || [ -d "/.wisp" ]; then
        PANEL_TYPE="wisp"
    elif [ -n "${CONVOY_SERVER_UUID:-}" ]; then
        PANEL_TYPE="convoy"
    elif [ -n "${CYTOPANEL_SERVER_UUID:-}" ] || [ -n "${CYTO_SERVER_UUID:-}" ]; then
        PANEL_TYPE="cytopanel"
    elif [ -n "${FEATHER_SERVER_UUID:-}" ]; then
        PANEL_TYPE="feather"
    elif [ -n "${PUFFER_PANEL_TOKEN:-}" ] || [ -n "${PUFFER_PORT:-}" ] || [ -n "${PP_SERVER_ID:-}" ] || [ -d "/var/lib/pufferpanel/servers" ]; then
        PANEL_TYPE="pufferpanel"
    elif [ -n "${AMP_INSTANCE_ID:-}" ]; then
        PANEL_TYPE="amp"
    elif [ -d /mnt/server ] && [ ! -d /home/container ]; then
        PANEL_TYPE="pterodactyl"      # classic wings mount layout
    elif [ -d /home/container ]; then
        PANEL_TYPE="wings-family"     # Pterodactyl/Pelican/Feather/Cytopanel/Convoy compatible daemon
    fi

    # Any panel can force its identity via PANEL_NAME / PANEL_TYPE_OVERRIDE.
    PANEL_NAME="${PANEL_NAME_ENV:-}"
    case "${PANEL_TYPE}" in
        pelican)  [ -z "${PANEL_NAME}" ] && PANEL_NAME="pelican" ;;
        pterodactyl) [ -z "${PANEL_NAME}" ] && PANEL_NAME="pterodactyl" ;;
        *) [ -z "${PANEL_NAME}" ] && PANEL_NAME="${PANEL_TYPE}" ;;
    esac
    export PANEL_TYPE PANEL_NAME
}
detect_panel

# Cross-panel port compatibility shims for applications that read
# panel-specific port variables. Exported strictly AFTER panel detection -
# exporting them earlier made the Puffer detection branch always match
# (every container reported PufferPanel).
if [ -n "${SERVER_PORT:-}" ]; then
    export FEATHER_PORT="${FEATHER_PORT:-${SERVER_PORT}}"
    export PUFFER_PORT="${PUFFER_PORT:-${SERVER_PORT}}"
fi

# Crash-safety traps are installed by lib-diagnostics.sh (pf_err_trap/pf_exit_hook).
# Signal hygiene: SIGINT/SIGTERM propagate to the exec'd database daemon via tini.

# Universal UID/GID Mapping (Resolves 'initdb: could not look up effective user ID <UID>: user does not exist')
CURRENT_UID=$(id -u 2>/dev/null || echo "988")
CURRENT_GID=$(id -g 2>/dev/null || echo "988")
if ! whoami >/dev/null 2>&1 || ! getent passwd "${CURRENT_UID}" >/dev/null 2>&1; then
    if [ -w /etc/passwd ]; then
        echo "container:x:${CURRENT_UID}:${CURRENT_GID}:container user:${HOME:-/home/container}:/bin/bash" >> /etc/passwd 2>/dev/null || true
    fi
fi
if ! getent group "${CURRENT_GID}" >/dev/null 2>&1; then
    if [ -w /etc/group ]; then
        echo "container:x:${CURRENT_GID}:" >> /etc/group 2>/dev/null || true
    fi
fi

# Universal working directory detection
if [ -d /home/container ]; then
    cd /home/container 2>/dev/null || true
elif [ -d /mnt/server ]; then
    cd /mnt/server 2>/dev/null || true
else
    cd "$(pwd)" 2>/dev/null || true
fi
SERVER_DIR="$(pwd)"

# -----------------------------------------------------------------------------
# 3.5 Production Reliability: Console Mirroring & Safety Checks
# -----------------------------------------------------------------------------
# Mirror the entire boot + runtime console into .logs/console.log so users can
# troubleshoot crashes even after the panel scrollback is gone. Opt out with
# LAUNCHER_LOG=0. Rotates the previous boot's log to .1 automatically.
if [ "${LAUNCHER_LOG:-1}" = "1" ]; then
    _LOGDIR="${SERVER_DIR}/.logs"
    mkdir -p "${_LOGDIR}" 2>/dev/null || true
    if [ -d "${_LOGDIR}" ] && [ -w "${_LOGDIR}" ]; then
        LAUNCH_CONSOLE_LOG="${_LOGDIR}/console.log"
        [ -f "${LAUNCH_CONSOLE_LOG}" ] && mv -f "${LAUNCH_CONSOLE_LOG}" "${LAUNCH_CONSOLE_LOG}.1" 2>/dev/null || true
        exec > >(tee -a "${LAUNCH_CONSOLE_LOG}") 2>&1
        # Boot header written into the mirror so log segments are easy to tell
        # apart when troubleshooting (panel, arch, uid, timestamp).
        printf '\n=== Database Eggs boot @ %s | panel=%s | arch=%s | uid=%s ===\n' \
            "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)" \
            "${PANEL_TYPE}" "$(uname -m 2>/dev/null || echo '?')" "$(id -u 2>/dev/null || echo '?')"
    fi
fi
unset _LOGDIR

# Running as root inside a panel container is a security anti-pattern; warn.
if [ "$(id -u 2>/dev/null || echo 1)" = "0" ]; then
    warn "Container is running as ROOT. Panels should launch images as a non-root user (e.g. uid 988)."
fi

# Image provenance stamp (written at docker build time) for supportability.
if [ -f "/etc/potenfyr-version" ]; then
    info "Image build: $(head -n1 /etc/potenfyr-version 2>/dev/null)"
fi

# Create clean user directory tree
mkdir -p "${SERVER_DIR}/data" "${SERVER_DIR}/config" "${SERVER_DIR}/logs" "${SERVER_DIR}/bin"

# Backward-Compatibility & Cleanup:
# Remove obsolete root scripts copied by previous egg versions so old servers run cleanly on latest image scripts.
# Signature-gated (must contain the studio header) so user files with the same
# name are never touched.
for _egg_script in run.sh entrypoint.sh; do
    if [ -f "${SERVER_DIR}/${_egg_script}" ] && grep -q "PotenFYR Studios" "${SERVER_DIR}/${_egg_script}" 2>/dev/null; then
        rm -f "${SERVER_DIR}/${_egg_script}" 2>/dev/null || true
    fi
done
unset _egg_script
if [ -d "${SERVER_DIR}/scripts" ] && [ -f /usr/local/bin/password-gen.sh ]; then
    rm -rf "${SERVER_DIR}/scripts" 2>/dev/null || true
fi

# Fallback bootstrap for generic images (only when not running the official pre-baked image)
RUNTIME_DIR="/usr/local/bin"
if [ ! -f "${RUNTIME_DIR}/run.sh" ]; then
    RUNTIME_DIR="/tmp/.database-runtime"
    mkdir -p "${RUNTIME_DIR}"
    if [ ! -f "${RUNTIME_DIR}/run.sh" ]; then
        log "Bootstrapping runtime components into isolated runtime space..."
        REPO_BASE="https://raw.githubusercontent.com/PotenFYR-Studios/Database-Eggs/main"
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL --retry 3 "${REPO_BASE}/run.sh" -o "${RUNTIME_DIR}/run.sh" 2>/dev/null || true
            for h in lib-diagnostics.sh companion-loader.sh password-gen.sh performance-tuning.sh install-db-version.sh db-init-mariadb.sh db-init-postgres.sh db-init-redis.sh db-init-mongo.sh db-init-surreal.sh db-init-search.sh db-init-storage.sh db-init-extra.sh; do
                curl -fsSL --retry 2 "${REPO_BASE}/scripts/${h}" -o "${RUNTIME_DIR}/${h}" 2>/dev/null || true
            done
        elif command -v wget >/dev/null 2>&1; then
            wget -qO "${RUNTIME_DIR}/run.sh" "${REPO_BASE}/run.sh" 2>/dev/null || true
            for h in lib-diagnostics.sh companion-loader.sh password-gen.sh performance-tuning.sh install-db-version.sh db-init-mariadb.sh db-init-postgres.sh db-init-redis.sh db-init-mongo.sh db-init-surreal.sh db-init-search.sh db-init-storage.sh db-init-extra.sh; do
                wget -qO "${RUNTIME_DIR}/${h}" "${REPO_BASE}/scripts/${h}" 2>/dev/null || true
            done
        fi
        chmod +x "${RUNTIME_DIR}"/*.sh 2>/dev/null || true
    fi
fi

if [ ! -f "${RUNTIME_DIR}/run.sh" ] && [ ! -f /usr/local/bin/run.sh ] && [ ! -f "${SERVER_DIR}/run.custom.sh" ]; then
    error "Runtime launcher (run.sh) could not be located or downloaded."
    error "Troubleshooting steps:"
    error "1. Ensure your server uses the official image: ghcr.io/potenfyr-studios/database-eggs:latest"
    error "2. Ensure the server node has outbound internet access to githubusercontent.com"
    fail "Fatal: Runtime launcher unavailable."
fi

export PATH="/usr/lib/postgresql/18/bin:/usr/lib/postgresql/17/bin:/usr/lib/postgresql/16/bin:/usr/lib/postgresql/15/bin:${SERVER_DIR}/bin:${RUNTIME_DIR}:/usr/local/bin:${PATH}"

# Source performance and helper scripts safely
[ -f "${RUNTIME_DIR}/performance-tuning.sh" ] && source "${RUNTIME_DIR}/performance-tuning.sh" 2>/dev/null || true
[ -f "${RUNTIME_DIR}/password-gen.sh" ] && source "${RUNTIME_DIR}/password-gen.sh" 2>/dev/null || true

# Default Timezone
TZ="${TZ:-UTC}"
export TZ

# Cross-panel variable normalization
SERVER_PORT="${SERVER_PORT:-${PORT:-${ALLOCATION_PORT:-${SERVER_PORT_0:-3306}}}}"
export SERVER_PORT
SERVER_MEMORY="${SERVER_MEMORY:-${MEMORY:-${MEM_SIZE:-${P_SERVER_MEMORY:-1024}}}}"
export SERVER_MEMORY
SERVER_IP="${SERVER_IP:-${IP:-${P_SERVER_IP:-0.0.0.0}}}"
export SERVER_IP

# Customizable bind address (security: bind to INTERNAL_IP in shared infra)
BIND_ADDRESS="${BIND_ADDRESS:-${LISTEN_HOST:-0.0.0.0}}"
export BIND_ADDRESS

# Security profile: strict (default) enables hardened defaults everywhere
SECURITY_LEVEL="${SECURITY_LEVEL:-strict}"
export SECURITY_LEVEL

INTERNAL_IP=$(ip route get 1 2>/dev/null | awk '{print $(NF-2);exit}' 2>/dev/null || echo "${SERVER_IP}")
export INTERNAL_IP

# --- Persisted Settings & Credentials (.env only) -----------------------------
ENV_FILE="${SERVER_DIR}/.env"

# Clean up any legacy plain-text credential files so sensitive info is strictly in .env
rm -f "${SERVER_DIR}/credentials.txt" "${SERVER_DIR}/.db_credentials" "${SERVER_DIR}/.multi-db.conf" 2>/dev/null || true

read_env_val() {
    local key="$1"
    [ -f "${ENV_FILE}" ] || return 1
    local val
    val=$(grep -E "^${key}=" "${ENV_FILE}" 2>/dev/null | tail -n1 | cut -d= -f2-)
    [ -n "${val}" ] || return 1
    # Strip quotes and whitespace
    printf '%s' "${val}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//"
}

apply_persisted() {
    local key="$1"
    local val
    val=$(read_env_val "${key}") || return 0
    # If the current environment variable is unset, empty, or "auto"/"generate", load persisted value
    if [ -z "${!key-}" ] || [ "${!key}" = "auto" ] || [ "${!key}" = "generate" ]; then
        printf -v "${key}" '%s' "${val}"
        export "${key}"
    fi
}

for _key in DATABASE_TYPE DB_TYPE DB_VERSION DB_NAME DB_USER DB_PASSWORD DB_ROOT_PASSWORD \
            AUTO_GENERATE_CREDENTIALS EXTRA_ARGS DATA_DIR KEEP_BACKUP \
            PERFORMANCE_TUNING SECURITY_HARDENING CUSTOM_DOWNLOAD_URL CUSTOM_BINARY_NAME CUSTOM_COMMAND \
            EGG_UPDATE_URL AUTO_UPDATE_EGG PANEL_STOP_WATCHER CLI_THEME CLI_BANNER_GRADIENT; do
    apply_persisted "${_key}"
done
unset _key

# -----------------------------------------------------------------------------
# 5.5 Egg Self-Update Engine (EGG_UPDATE_URL)
# -----------------------------------------------------------------------------
# On startup the launcher scripts run from the image; to let users pick up
# launcher fixes without rebuilding/reinstalling the image, EGG_UPDATE_URL can
# point at a run.sh (or egg JSON) on GitHub. Default is this repo's own raw
# egg JSON URL. AUTO_UPDATE_EGG=0 disables the check entirely.
#
# Behaviour:
#   * https URLs only - plain http is refused so a tampered update server can
#     never inject launcher code.
#   * URL ending in .sh   -> replaces the launcher directly (staged + sha256
#     recorded; the staged copy is only promoted by the resolution step below
#     if its recorded hash matches, so a planted file is never executed).
#   * URL ending in .json -> compared against the hash file; on change the
#     launcher scripts are refreshed from the same repo branch.
# Failure of any step is non-fatal: the previously installed launcher runs.
# The launcher override lives OUTSIDE the user's data volume (in /opt/potenfyr,
# container-local, or /tmp/.database-runtime) so egg internals are never exposed
# under the workspace the panel file manager can see.
phase "Egg Self-Update"
EGG_UPDATE_URL="${EGG_UPDATE_URL:-https://raw.githubusercontent.com/PotenFYR-Studios/Database-Eggs/main/egg-database-multi.json}"
AUTO_UPDATE_EGG="${AUTO_UPDATE_EGG:-1}"

if [ "${AUTO_UPDATE_EGG}" = "1" ] && [ -n "${EGG_UPDATE_URL}" ]; then
    if ! [[ "${EGG_UPDATE_URL}" =~ ^https:// ]]; then
        warn "EGG_UPDATE_URL must be an https:// URL - self-update disabled for safety."
    elif command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
        # Non-root panels (uid 988 etc.) cannot write /usr/local/bin; fall back
        # to a user-writable override location OUTSIDE the user data volume that
        # launcher resolution below prefers over the image copy.
        _egg_target="/usr/local/bin/run.sh"
        _egg_hashfile="/etc/potenfyr-egg-hash"
        if [ -f /usr/local/bin/run.sh ] && [ -w /usr/local/bin ] && [ "$(id -u 2>/dev/null || echo 1)" = "0" ]; then
            RUNTIME_DIR="/usr/local/bin"
        else
            RUNTIME_DIR="/tmp/.database-runtime"
            mkdir -p "${RUNTIME_DIR}" 2>/dev/null || true
        fi
        _egg_target="${RUNTIME_DIR}/run.sh"
        _egg_hashfile="${RUNTIME_DIR}/.potenfyr-egg-hash"
        _egg_lhash="${RUNTIME_DIR}/.potenfyr-launcher-hash"
        _egg_tmp="$(mktemp 2>/dev/null || echo "/tmp/potenfyr-egg.$$")"
        _egg_fetch_ok=0
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL --retry 2 --max-time 30 "${EGG_UPDATE_URL}" -o "${_egg_tmp}" 2>/dev/null && _egg_fetch_ok=1
        elif command -v wget >/dev/null 2>&1; then
            wget -qO "${_egg_tmp}" "${EGG_UPDATE_URL}" 2>/dev/null && _egg_fetch_ok=1
        fi
        if [ "${_egg_fetch_ok}" = "1" ] && [ -s "${_egg_tmp}" ]; then
            _egg_hash_new="$(sha256sum "${_egg_tmp}" 2>/dev/null | cut -d' ' -f1)"
            _egg_hash_old="$(cat "${_egg_hashfile}" 2>/dev/null || cat /etc/potenfyr-egg-hash 2>/dev/null || true)"
            if [ -n "${_egg_hash_new}" ] && [ "${_egg_hash_new}" != "${_egg_hash_old}" ]; then
                case "${EGG_UPDATE_URL}" in
                    *.sh)
                        # Direct launcher replacement (staged; promoted only on hash match)
                        if cp "${_egg_tmp}" "${_egg_target}.update" 2>/dev/null; then
                            printf '%s\n' "${_egg_hash_new}" > "${RUNTIME_DIR}/.potenfyr-staged-hash" 2>/dev/null || true
                            if [ "$(sha256sum "${_egg_target}.update" 2>/dev/null | cut -d' ' -f1)" = "${_egg_hash_new}" ]; then
                                mv -f "${_egg_target}.update" "${_egg_target}" 2>/dev/null || true
                                chmod +x "${_egg_target}" 2>/dev/null || true
                                printf '%s\n' "${_egg_hash_new}" > "${_egg_hashfile}" 2>/dev/null || true
                                printf '%s\n' "$(_egg_hash_new)" > "${_egg_lhash}" 2>/dev/null || true
                                ok "Launcher self-updated from EGG_UPDATE_URL."
                            else
                                rm -f "${_egg_target}.update" 2>/dev/null || true
                                warn "Staged launcher update failed integrity check - discarded."
                            fi
                        else
                            warn "Launcher self-update failed (target not writable): ${_egg_target}"
                        fi
                        ;;
                    *)
                        # egg JSON changed -> refresh launcher from same branch
                        _base="${EGG_UPDATE_URL%/*}"
                        _launcher_ok=0
                        if curl -fsSL --retry 2 --max-time 30 "${_base}/run.sh" -o "${RUNTIME_DIR}/.run.sh.update" 2>/dev/null \
                           && [ -s "${RUNTIME_DIR}/.run.sh.update" ] \
                           && grep -q "PotenFYR Studios" "${RUNTIME_DIR}/.run.sh.update" 2>/dev/null; then
                            if head -c 2 "${RUNTIME_DIR}/.run.sh.update" | grep -q $'\r'; then
                                sed -i 's/\r$//' "${RUNTIME_DIR}/.run.sh.update" 2>/dev/null || true
                            fi
                            _lhash_new="$(sha256sum "${RUNTIME_DIR}/.run.sh.update" 2>/dev/null | cut -d' ' -f1)"
                            mv -f "${RUNTIME_DIR}/.run.sh.update" "${_egg_target}" 2>/dev/null || true
                            chmod +x "${_egg_target}" 2>/dev/null || true
                            printf '%s\n' "${_lhash_new}" > "${_egg_lhash}" 2>/dev/null || true
                            _launcher_ok=1
                        fi
                        if [ "${_launcher_ok:-0}" = "1" ]; then
                            echo "${_egg_hash_new}" > "${_egg_hashfile}" 2>/dev/null || true
                            ok "Egg update detected - launcher refreshed from ${_base}."
                        else
                            warn "Egg update detected but launcher refresh failed - continuing with installed launcher."
                        fi
                        rm -f "${RUNTIME_DIR}/.run.sh.update" 2>/dev/null || true
                        ;;
                esac
            else
                info "Egg is up to date."
            fi
        else
            warn "EGG_UPDATE_URL fetch failed - continuing with installed launcher."
        fi
        rm -f "${_egg_tmp}" 2>/dev/null || true
        unset _egg_tmp _egg_hash_new _egg_hash_old _egg_target _egg_hashfile _egg_lhash _base _launcher_ok _egg_fetch_ok _lhash_new
    fi
fi
# Tell run.sh the check already ran this boot (skips a second network round-trip).
export EGG_UPDATE_CHECKED=1

# Launcher resolution prefers the user-writable self-update override so
# refreshed launchers (EGG_UPDATE_URL) actually take effect on non-root panels -
# but only after verifying its sha256 against the hash recorded when it was
# written. A user-writable file is never blindly executed.
if [ -f "${RUNTIME_DIR}/.run.sh.update" ] && [ -f "${RUNTIME_DIR}/.potenfyr-staged-hash" ]; then
    _staged_hash="$(sha256sum "${RUNTIME_DIR}/.run.sh.update" 2>/dev/null | cut -d' ' -f1)"
    if [ -n "${_staged_hash}" ] && [ "${_staged_hash}" = "$(cat "${RUNTIME_DIR}/.potenfyr-staged-hash" 2>/dev/null)" ]; then
        mv -f "${RUNTIME_DIR}/.run.sh.update" "${RUNTIME_DIR}/run.sh" 2>/dev/null || true
    else
        warn "Staged launcher update failed integrity check - discarded."
        rm -f "${RUNTIME_DIR}/.run.sh.update" "${RUNTIME_DIR}/.potenfyr-staged-hash" 2>/dev/null || true
    fi
fi
if [ -n "${SERVER_DIR}" ] && [ -d "${SERVER_DIR}/.potenfyr" ]; then
    # Legacy workspace override from old egg versions: migrate out of the user
    # volume when it passes integrity, discard when it does not.
    if [ -f "${SERVER_DIR}/.potenfyr/run.sh" ]; then
        _lh="$(cat "${SERVER_DIR}/.potenfyr/launcher-hash" 2>/dev/null || true)"
        if [ -n "${_lh}" ] && [ "$(sha256sum "${SERVER_DIR}/.potenfyr/run.sh" 2>/dev/null | cut -d' ' -f1)" = "${_lh}" ]; then
            cp "${SERVER_DIR}/.potenfyr/run.sh" "${RUNTIME_DIR}/run.sh.override" 2>/dev/null || true
            printf '%s\n' "${_lh}" > "${RUNTIME_DIR}/.potenfyr-launcher-hash" 2>/dev/null || true
            ok "Launcher override moved out of the user workspace."
        else
            warn "Old .potenfyr launcher override failed integrity check - discarded."
        fi
    fi
    rm -rf "${SERVER_DIR}/.potenfyr" 2>/dev/null || true
fi
if [ -f "${RUNTIME_DIR}/run.sh.override" ]; then
    _rec_hash="$(cat "${RUNTIME_DIR}/.potenfyr-launcher-hash" 2>/dev/null || true)"
    if [ -n "${_rec_hash}" ] && [ "$(sha256sum "${RUNTIME_DIR}/run.sh.override" 2>/dev/null | cut -d' ' -f1)" = "${_rec_hash}" ]; then
        LAUNCHER_OVERRIDE="${RUNTIME_DIR}/run.sh.override"
    else
        warn "User-space launcher override failed integrity check - using image launcher."
        rm -f "${RUNTIME_DIR}/run.sh.override" 2>/dev/null || true
    fi
fi

# Also map common .env variations (DB_DATABASE, DB_USERNAME)
if [ -z "${DB_NAME:-}" ]; then
    DB_NAME=$(read_env_val "DB_DATABASE") || true
fi
if [ -z "${DB_USER:-}" ]; then
    DB_USER=$(read_env_val "DB_USERNAME") || true
fi

DB_TYPE="${DATABASE_TYPE:-${DB_TYPE:-mariadb}}"
PROJECT_TYPE=$(echo "${DB_TYPE}" | tr '[:upper:]' '[:lower:]')
DB_VERSION="${DB_VERSION:-latest}"
export PROJECT_TYPE DB_VERSION

SAVE_TO_ENV="${SAVE_TO_ENV:-${SAVE_ENV:-1}}"

# --- Strong Random Password & Secret Generation -------------------------------
gen_rand() {
    local len="${1:-32}" mode="${2:-urlsafe}"
    if command -v generate_secret >/dev/null 2>&1; then
        generate_secret "${len}" "${mode}"
    elif command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 96 | tr -dc 'A-Za-z0-9._~-' | head -c "${len}"
    else
        head -c 128 /dev/urandom 2>/dev/null | tr -dc 'A-Za-z0-9._~-' | head -c "${len}" || echo "SecuredSecret_$(date +%s)_PotenFYR"
    fi
}

# Auto-generate credentials if empty, auto, or generate (otherwise use user-provided password)
if [ "${AUTO_GENERATE_CREDENTIALS}" = "1" ]; then
    if [ -z "${DB_ROOT_PASSWORD:-}" ] || [ "${DB_ROOT_PASSWORD}" = "auto" ] || [ "${DB_ROOT_PASSWORD}" = "generate" ]; then
        DB_ROOT_PASSWORD=$(gen_rand 32 urlsafe)
    fi
    if [ -z "${DB_PASSWORD:-}" ] || [ "${DB_PASSWORD}" = "auto" ] || [ "${DB_PASSWORD}" = "generate" ]; then
        DB_PASSWORD=$(gen_rand 32 urlsafe)
    fi
    # Production floor: engines like Meilisearch reject master keys < 32 chars.
    # Short user-supplied values are transparently upgraded to strong secrets.
    if [ "${#DB_ROOT_PASSWORD}" -lt 32 ] 2>/dev/null; then
        warn "DB_ROOT_PASSWORD shorter than 32 chars; upgrading to a cryptographically strong secret."
        DB_ROOT_PASSWORD=$(gen_rand 32 urlsafe)
    fi
    if [ "${#DB_PASSWORD}" -lt 32 ] 2>/dev/null; then
        warn "DB_PASSWORD shorter than 32 chars; upgrading to a cryptographically strong secret."
        DB_PASSWORD=$(gen_rand 32 urlsafe)
    fi
fi

DB_USER="${DB_USER:-dbuser}"
DB_NAME="${DB_NAME:-database}"
export DB_ROOT_PASSWORD DB_PASSWORD DB_USER DB_NAME

# Export latest active credentials into process environment for startup command, subshells & CLI tools
export PGPASSWORD="${DB_PASSWORD:-${DB_ROOT_PASSWORD}}"
export MYSQL_PWD="${DB_PASSWORD:-${DB_ROOT_PASSWORD}}"
export REDISCLI_AUTH="${DB_PASSWORD:-${DB_ROOT_PASSWORD}}"
export MONGO_PWD="${DB_PASSWORD:-${DB_ROOT_PASSWORD}}"
export SURREAL_PASS="${DB_PASSWORD:-${DB_ROOT_PASSWORD}}"

# Save and synchronize sensitive credentials into .env if enabled (Optional: SAVE_TO_ENV=1)
if [ "${SAVE_TO_ENV}" = "1" ] || [ "${SAVE_TO_ENV}" = "true" ] || [ "${SAVE_TO_ENV}" = "yes" ]; then
    {
        printf '# Database Configuration & Credentials (Synced by PotenFYR Runtime)\n'
        printf 'DB_CONNECTION=%s\n' "${PROJECT_TYPE}"
        printf 'DB_HOST=127.0.0.1\n'
        printf 'DB_PORT=%s\n' "${SERVER_PORT}"
        printf 'DB_DATABASE=%s\n' "${DB_NAME}"
        printf 'DB_USERNAME=%s\n' "${DB_USER}"
        printf 'DB_PASSWORD="%s"\n' "${DB_PASSWORD}"
        printf 'DB_ROOT_PASSWORD="%s"\n' "${DB_ROOT_PASSWORD}"
        printf 'DB_VERSION=%s\n' "${DB_VERSION}"
    } > "${ENV_FILE}" 2>/dev/null || true
    chmod 600 "${ENV_FILE}" 2>/dev/null || true
fi

# Generate user environment shortcuts for terminal CLI usage (.profile and .bashrc)
{
    printf 'export PATH="/usr/lib/postgresql/18/bin:/usr/lib/postgresql/17/bin:/usr/lib/postgresql/16/bin:/usr/lib/postgresql/15/bin:/usr/lib/postgresql/14/bin:%s/bin:%s:/usr/local/bin:${PATH}"\n' "${SERVER_DIR}" "${RUNTIME_DIR}"
    printf '[ -f "%s/.env" ] && set -a && source "%s/.env" 2>/dev/null && set +a\n' "${SERVER_DIR}" "${SERVER_DIR}"
    printf 'export DB_PASSWORD="%s"\n' "${DB_PASSWORD}"
    printf 'export DB_ROOT_PASSWORD="%s"\n' "${DB_ROOT_PASSWORD}"
    printf 'export PGPASSWORD="%s"\n' "${DB_PASSWORD:-${DB_ROOT_PASSWORD}}"
    printf 'export MYSQL_PWD="%s"\n' "${DB_PASSWORD:-${DB_ROOT_PASSWORD}}"
    printf 'export REDISCLI_AUTH="%s"\n' "${DB_PASSWORD:-${DB_ROOT_PASSWORD}}"
    printf 'export MONGO_PWD="%s"\n' "${DB_PASSWORD:-${DB_ROOT_PASSWORD}}"
    printf 'export SURREAL_PASS="%s"\n' "${DB_PASSWORD:-${DB_ROOT_PASSWORD}}"

    case "${PROJECT_TYPE}" in
        mariadb|mysql)
            printf 'alias db-cli="mysql -h 127.0.0.1 -P %s -u %s -p\"%s\" %s"\n' "${SERVER_PORT}" "${DB_USER:-root}" "${DB_PASSWORD:-${DB_ROOT_PASSWORD}}" "${DB_NAME}"
            ;;
        postgresql|postgres)
            printf 'alias db-cli="psql -h 127.0.0.1 -p %s -U %s -d %s"\n' "${SERVER_PORT}" "${DB_USER:-postgres}" "${DB_NAME:-postgres}"
            ;;
        redis|valkey|keydb|dragonfly)
            printf 'alias db-cli="redis-cli -h 127.0.0.1 -p %s -a \"%s\""\n' "${SERVER_PORT}" "${DB_PASSWORD:-${DB_ROOT_PASSWORD}}"
            ;;
        mongodb|ferretdb)
            printf 'alias db-cli="mongosh \"mongodb://%s:%s@127.0.0.1:%s/%s?authSource=admin\""\n' "${DB_USER:-root}" "${DB_PASSWORD:-${DB_ROOT_PASSWORD}}" "${SERVER_PORT}" "${DB_NAME}"
            ;;
        surrealdb)
            printf 'alias db-cli="surreal sql --endpoint http://127.0.0.1:%s --user %s --pass \"%s\""\n' "${SERVER_PORT}" "${DB_USER:-root}" "${DB_PASSWORD:-${DB_ROOT_PASSWORD}}"
            ;;
    esac
} > "${SERVER_DIR}/.profile" 2>/dev/null || true
cp -f "${SERVER_DIR}/.profile" "${SERVER_DIR}/.bashrc" 2>/dev/null || true
chmod 600 "${SERVER_DIR}/.profile" "${SERVER_DIR}/.bashrc" 2>/dev/null || true

# -----------------------------------------------------------------------------
# Startup banner (block-font art, diagonal 256-color gradient sweeps)
# -----------------------------------------------------------------------------
# Gradient presets: citrus (brand) aurora sunset ocean candy spectrum | none =
# flat lime. CLI_BANNER_GRADIENT picks one; "auto" (default) randomizes per
# boot. Consoles narrower than 78 cols get compact art, < 62 get plain text.
print_banner() {
    printf "\n"
    local _gname _ramp=""
    case "${CLI_BANNER_GRADIENT:-auto}" in
        citrus|aurora|sunset|ocean|candy|spectrum) _gname="${CLI_BANNER_GRADIENT}" ;;
        none|off|plain) _gname="none" ;;
        auto|*)
            case $((RANDOM % 6)) in
                0) _gname="citrus" ;;
                1) _gname="aurora" ;;
                2) _gname="sunset" ;;
                3) _gname="ocean" ;;
                4) _gname="candy" ;;
                5) _gname="spectrum" ;;
            esac ;;
    esac
    case "${_gname}" in
        citrus)   _ramp="22 28 34 40 46 82 118 154 190 220 214 208 202" ;;
        aurora)   _ramp="22 28 34 41 47 48 49 50 51 45 39 33 27 21" ;;
        sunset)   _ramp="52 88 124 160 196 202 208 214 220 226" ;;
        ocean)    _ramp="16 17 18 19 20 26 32 38 44 50 51" ;;
        candy)    _ramp="53 91 128 164 200 206 212 218 224 213 177 141 105" ;;
        spectrum) _ramp="196 202 208 214 220 226 190 154 118 82 46 40 34 21 27 33 39 45 51 93 129 165 201 207 213" ;;
    esac

    if [ "${_gname}" != "none" ]; then
        # Print one row, sweeping the ramp across columns with a slight
        # diagonal offset per row so the gradient flows top-left to
        # bottom-right. Spaces pass through uncolored.
        _banner_grad_row() {
            local row="$1" ridx="$2"
            local -a cs
            read -ra cs <<< "${_ramp}"
            local n=${#cs[@]} w=${#row} out="" i ci ch span
            span=$(( (w > 1 ? w : 2) - 1 + 30 ))
            for ((i = 0; i < w; i++)); do
                ch="${row:i:1}"
                if [ "${ch}" = " " ]; then out+=" "; continue; fi
                ci=$(( (i + ridx * 6) * (n - 1) / span ))
                (( ci >= n )) && ci=$(( n - 1 ))
                out+="\e[38;5;${cs[$ci]}m${ch}"
            done
            printf '%b%b\n' "${out}" "${C_RESET}"
        }
        # "DATABASE" in ANSI Shadow font, 72 columns wide (fits 80-col panels
        # without wrapping - wrapped rows would smear escape codes into the art).
        local -a _art=(
'██████╗   █████╗  ████████╗  █████╗  ██████╗   █████╗  ███████╗ ███████╗'
'██╔══██╗ ██╔══██╗ ╚══██╔══╝ ██╔══██╗ ██╔══██╗ ██╔══██╗ ██╔════╝ ██╔════╝'
'██║  ██║ ███████║    ██║    ███████║ ██████╔╝ ███████║ ███████║ █████╗  '
'██║  ██║ ██╔══██║    ██║    ██╔══██║ ██╔══██╗ ██╔══██║ ╚════██║ ██╔══╝  '
'██████╔╝ ██║  ██║    ██║    ██║  ██║ ██████╔╝ ██║  ██║ ███████║ ███████╗'
'╚═════╝  ╚═╝  ╚═╝    ╚═╝    ╚═╝  ╚═╝ ╚═════╝  ╚═╝  ╚═╝ ╚══════╝ ╚══════╝'
        )
        local _w
        _w="${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}"
        if [ "${_w:-80}" -ge 74 ] 2>/dev/null; then
            local r
            for r in 0 1 2 3 4 5; do
                _banner_grad_row "${_art[$r]}" "$r"
            done
        else
            # Narrow consoles: clean styled text (figlet art would wrap/corrupt).
            printf "${C_LIME}${C_BOLD}  »» DATABASE EGGS · Multi-Database Server Runtime${C_RESET}\n"
            printf "${C_LIME}${C_BOLD}  »» 55+ Engines · Every Version · Every Panel${C_RESET}\n"
        fi
    else
        printf "${C_LIME}${C_BOLD} ██████╗   █████╗  ████████╗  █████╗  ██████╗   █████╗  ███████╗ ███████╗${C_RESET}\n"
        printf "${C_LIME}${C_BOLD} ██╔══██╗ ██╔══██╗ ╚══██╔══╝ ██╔══██╗ ██╔══██╗ ██╔══██╗ ██╔════╝ ██╔════╝${C_RESET}\n"
        printf "${C_LIME}${C_BOLD} ██║  ██║ ███████║    ██║    ███████║ ██████╔╝ ███████║ ███████║ █████╗  ${C_RESET}\n"
        printf "${C_LIME}${C_BOLD} ██║  ██║ ██╔══██║    ██║    ██╔══██║ ██╔══██╗ ██╔══██║ ╚════██║ ██╔══╝  ${C_RESET}\n"
        printf "${C_LIME}${C_BOLD} ██████╔╝ ██║  ██║    ██║    ██║  ██║ ██████╔╝ ██║  ██║ ███████║ ███████╗${C_RESET}\n"
        printf "${C_LIME}${C_BOLD} ╚═════╝  ╚═╝  ╚═╝    ╚═╝    ╚═╝  ╚═╝ ╚═════╝  ╚═╝  ╚═╝ ╚══════╝ ╚══════╝${C_RESET}\n"
    fi

    printf "${C_LIME}${C_BOLD}  </> » Multi-Database Server Runtime · 55+ Engines · Every Version${C_RESET}\n"
    if [ "${_gname}" = "none" ]; then
        printf "${C_DIM}    By PotenFYR Studios • support@potenfyr.in${C_RESET}\n\n"
    else
        printf "${C_DIM}    By PotenFYR Studios • support@potenfyr.in · gradient: %s${C_RESET}\n\n" "${_gname}"
    fi
}

print_banner

# Runtime Environment Card
printf "${C_LIME}${C_BOLD}┌─────────────────────────────────────────────────────────────┐${C_RESET}\n"
printf "${C_LIME}${C_BOLD}│${C_RESET}  ${C_BOLD}%-18s${C_RESET} : ${C_GREEN}%-36s${C_RESET}  ${C_LIME}${C_BOLD}│${C_RESET}\n" "Database Engine" "${PROJECT_TYPE^^} (v${DB_VERSION})"
printf "${C_LIME}${C_BOLD}│${C_RESET}  ${C_BOLD}%-18s${C_RESET} : ${C_CYAN}%-36s${C_RESET}  ${C_LIME}${C_BOLD}│${C_RESET}\n" "Listen Address" "${BIND_ADDRESS:-0.0.0.0}:${SERVER_PORT}"
printf "${C_LIME}${C_BOLD}│${C_RESET}  ${C_BOLD}%-18s${C_RESET} : ${C_MAGENTA}%-36s${C_RESET}  ${C_LIME}${C_BOLD}│${C_RESET}\n" "Allocated Memory" "${SERVER_MEMORY} MB"
printf "${C_LIME}${C_BOLD}│${C_RESET}  ${C_BOLD}%-18s${C_RESET} : ${C_BLUE}%-36s${C_RESET}  ${C_LIME}${C_BOLD}│${C_RESET}\n" "Database / Schema" "${DB_NAME:-default}"
printf "${C_LIME}${C_BOLD}│${C_RESET}  ${C_BOLD}%-18s${C_RESET} : ${C_DIM}%-36s${C_RESET}  ${C_LIME}${C_BOLD}│${C_RESET}\n" "Detected Panel" "${PANEL_TYPE:-standalone}"
printf "${C_LIME}${C_BOLD}│${C_RESET}  ${C_BOLD}%-18s${C_RESET} : ${C_YELLOW}%-36s${C_RESET}  ${C_LIME}${C_BOLD}│${C_RESET}\n" "Security Mode" "Strict Cryptographic / SCRAM / Auth"
printf "${C_LIME}${C_BOLD}└─────────────────────────────────────────────────────────────┘${C_RESET}\n\n"

log "Executing startup launcher..."

# Execute run.custom.sh if user explicitly provided one, otherwise execute canonical image launcher
if [ -f "${SERVER_DIR}/run.custom.sh" ]; then
    log "Custom launcher detected (run.custom.sh). Executing..."
    chmod +x "${SERVER_DIR}/run.custom.sh" 2>/dev/null || true
    exec "${SERVER_DIR}/run.custom.sh"
elif [ -n "${LAUNCHER_OVERRIDE:-}" ] && [ -f "${LAUNCHER_OVERRIDE}" ]; then
    chmod +x "${LAUNCHER_OVERRIDE}" 2>/dev/null || true
    exec "${LAUNCHER_OVERRIDE}"
elif [ -f "${RUNTIME_DIR}/run.sh" ]; then
    chmod +x "${RUNTIME_DIR}/run.sh" 2>/dev/null || true
    exec "${RUNTIME_DIR}/run.sh"
elif [ -f /usr/local/bin/run.sh ]; then
    exec /usr/local/bin/run.sh
else
    fail "Runtime launcher not found."
fi
