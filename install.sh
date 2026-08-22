#!/bin/bash
# =============================================================================
#  Multi Database - Universal Installation Script
#  By PotenFYR Studios (https://github.com/PotenFYR-Studios/Database-Eggs)
# =============================================================================

if [ -d /mnt/server ]; then
    cd /mnt/server || exit 1
elif [ -d /home/container ]; then
    cd /home/container || exit 1
else
    cd "$(pwd)" || exit 1
fi
SERVER_DIR="$(pwd)"

C_RESET='\033[0m'
C_BOLD='\033[1m'
C_CYAN='\033[36m'
C_GREEN='\033[32m'
C_YELLOW='\033[33m'
C_RED='\033[31m'
C_BLUE='\033[34m'
C_MAGENTA='\033[35m'
C_DIM='\033[2m'

log()  { printf "${C_CYAN}${C_BOLD}[install]${C_RESET} %s\n" "$*"; }
ok()   { printf "${C_CYAN}${C_BOLD}[install]${C_RESET} ${C_GREEN}${C_BOLD}[ok]${C_RESET} %s\n" "$*"; }
warn() { printf "${C_CYAN}${C_BOLD}[install]${C_RESET} ${C_YELLOW}${C_BOLD}[warn]${C_RESET} %s\n" "$*"; }
fail() { printf "${C_CYAN}${C_BOLD}[install]${C_RESET} ${C_RED}${C_BOLD}[error]${C_RESET} %s\n" "$*"; exit 1; }

# Startup banner (Compact Slant font, clean ANSI gradient)
printf "\n"
printf "${C_CYAN}${C_BOLD}   __  ___      ____  _       ____  ____     ${C_RESET}\n"
printf "${C_CYAN}${C_BOLD}  /  |/  /_  __/ / /_(_)     / __ \\/ __ )    ${C_RESET}\n"
printf "${C_BLUE}${C_BOLD} / /|_/ / / / / / __/ /_____/ / / / __  |    ${C_RESET}\n"
printf "${C_BLUE}${C_BOLD}/ /  / / /_/ / / /_/ /_____/ /_/ / /_/ /     ${C_RESET}\n"
printf "${C_MAGENTA}${C_BOLD}/_/  /_/\\__,_/_/\\__/_/     /_____/_____/      ${C_RESET}\n"
printf "${C_YELLOW}${C_BOLD}  » Universal Multi-Database Server Installer${C_RESET}\n"
printf "${C_DIM}    By PotenFYR Studios • support@potenfyr.in${C_RESET}\n\n"

ARCH=$(uname -m)
case "${ARCH}" in
    x86_64|amd64) ARCH_TYPE="amd64"; ARCH_ALT="x86_64" ;;
    aarch64|arm64) ARCH_TYPE="arm64"; ARCH_ALT="aarch64" ;;
    *) ARCH_TYPE="amd64"; ARCH_ALT="x86_64" ;;
esac

log "Target Architecture: ${ARCH_TYPE} (${ARCH})"

# Ensure essential tools in installer container
if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
    if command -v apk >/dev/null 2>&1; then
        apk add --no-cache curl jq tar unzip ca-certificates openssl bash >/dev/null 2>&1 || true
    elif command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq >/dev/null 2>&1 || true
        apt-get install -y -qq curl jq tar unzip ca-certificates openssl >/dev/null 2>&1 || true
    fi
fi

# Clean directories for user files
mkdir -p "${SERVER_DIR}/data" "${SERVER_DIR}/config" "${SERVER_DIR}/logs" "${SERVER_DIR}/bin"

# Remove any obsolete scripts that might have been copied from older egg versions
rm -f "${SERVER_DIR}/run.sh" "${SERVER_DIR}/entrypoint.sh" 2>/dev/null || true
rm -rf "${SERVER_DIR}/scripts" 2>/dev/null || true

PROJECT_TYPE=$(echo "${DB_TYPE:-${DATABASE_TYPE:-mariadb}}" | tr '[:upper:]' '[:lower:]')
DB_VERSION="${DB_VERSION:-latest}"

log "Configuring storage environment for engine: ${PROJECT_TYPE} (Version: ${DB_VERSION})..."

# If custom engine with download URL, fetch only the custom binary into bin/
if [ "${PROJECT_TYPE}" = "custom" ] && [ -n "${CUSTOM_DOWNLOAD_URL:-}" ]; then
    log "Downloading custom engine binary from ${CUSTOM_DOWNLOAD_URL}..."
    tmp_dl=$(mktemp)
    if curl -fsSL --retry 3 -o "${tmp_dl}" "${CUSTOM_DOWNLOAD_URL}"; then
        filename=$(basename "${CUSTOM_DOWNLOAD_URL}" | sed 's/[?].*//')
        case "${filename}" in
            *.tar.gz|*.tgz) tar -xzf "${tmp_dl}" -C "${SERVER_DIR}/bin/" ;;
            *.tar.xz) tar -xJf "${tmp_dl}" -C "${SERVER_DIR}/bin/" ;;
            *.zip) unzip -q -o "${tmp_dl}" -d "${SERVER_DIR}/bin/" ;;
            *) cp -f "${tmp_dl}" "${SERVER_DIR}/bin/${CUSTOM_BINARY_NAME:-server}" ;;
        esac
        rm -f "${tmp_dl}"
        chmod -R +x "${SERVER_DIR}/bin" 2>/dev/null || true
        ok "Custom binary installed in ${SERVER_DIR}/bin"
    fi
fi

# Handle EXTRA_URLS
if [ -n "${EXTRA_URLS:-}" ]; then
    log "Downloading extra user resources..."
    for line in ${EXTRA_URLS}; do
        [ -z "${line}" ] && continue
        dest="${SERVER_DIR}"
        url="${line}"
        if [[ "${line}" == *"|"* ]]; then
            url=$(echo "${line}" | cut -d'|' -f1)
            dest="${SERVER_DIR}/$(echo "${line}" | cut -d'|' -f2)"
            mkdir -p "$(dirname "${dest}")"
        else
            dest="${SERVER_DIR}/$(basename "${url}")"
        fi
        log "Fetching: ${url} -> ${dest}"
        curl -fsSL --retry 3 "${url}" -o "${dest}" || warn "Failed to download: ${url}"
    done
fi

# Permissions & Cleanup
chown -R 988:988 "${SERVER_DIR}" 2>/dev/null || true
chmod -R 755 "${SERVER_DIR}/data" "${SERVER_DIR}/config" "${SERVER_DIR}/logs" "${SERVER_DIR}/bin" 2>/dev/null || true

ok "Server directories prepared successfully."
