#!/bin/bash
# =============================================================================
#  Multi Database - Universal Installation Script
#  By PotenFYR Studios (https://github.com/PotenFYR-Studios/Database-Eggs)
# =============================================================================

set -uo pipefail

if [ -d /mnt/server ]; then
    cd /mnt/server || exit 1
elif [ -d /home/container ]; then
    cd /home/container || exit 1
else
    cd "$(pwd)" || exit 1
fi
SERVER_DIR="$(pwd)"

log()  { echo -e "\033[1m\033[36m[install]\033[0m $*"; }
ok()   { echo -e "\033[1m\033[32m[install][OK]\033[0m $*"; }
warn() { echo -e "\033[1m\033[33m[install][warn]\033[0m $*"; }
fail() { echo -e "\033[1m\033[31m[install][ERROR]\033[0m $*"; exit 1; }

ARCH=$(uname -m)
case "${ARCH}" in
    x86_64|amd64) ARCH_TYPE="amd64"; ARCH_ALT="x86_64" ;;
    aarch64|arm64) ARCH_TYPE="arm64"; ARCH_ALT="aarch64" ;;
    *) fail "Unsupported architecture: ${ARCH}" ;;
esac

log "Target Architecture: ${ARCH_TYPE} (${ARCH})"

# Ensure essential tools
if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq >/dev/null 2>&1 || true
        apt-get install -y -qq curl jq tar unzip ca-certificates openssl >/dev/null 2>&1 || true
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache curl jq tar unzip ca-certificates openssl >/dev/null 2>&1 || true
    fi
fi

mkdir -p "${SERVER_DIR}/bin" "${SERVER_DIR}/data" "${SERVER_DIR}/config" "${SERVER_DIR}/logs" "${SERVER_DIR}/scripts"

PROJECT_TYPE=$(echo "${DB_TYPE:-${DATABASE_TYPE:-mariadb}}" | tr '[:upper:]' '[:lower:]')
DB_VERSION="${DB_VERSION:-latest}"

log "Configuring installation for engine: ${PROJECT_TYPE} (Version: ${DB_VERSION})..."

# Invoke universal version installer if present
if [ -f /usr/local/bin/install-db-version.sh ]; then
    /usr/local/bin/install-db-version.sh "${PROJECT_TYPE}" "${DB_VERSION}" "${SERVER_DIR}/bin" || true
elif [ -f "${SERVER_DIR}/scripts/install-db-version.sh" ]; then
    bash "${SERVER_DIR}/scripts/install-db-version.sh" "${PROJECT_TYPE}" "${DB_VERSION}" "${SERVER_DIR}/bin" || true
fi

# Handle EXTRA_URLS
if [ -n "${EXTRA_URLS:-}" ]; then
    log "Downloading extra resources..."
    for line in ${EXTRA_URLS}; do
        [ -z "${line}" ] && continue
        dest="${SERVER_DIR}"
        url="${line}"
        if [[ "${line}" =~ \| ]]; then
            dest="${SERVER_DIR}/${line%%|*}"
            url="${line#*|}"
        fi
        mkdir -p "${dest}"
        filename=$(basename "${url}" | sed 's/[?].*//')
        curl -fsSL --retry 3 -o "${dest}/${filename}" "${url}"
        ok "Downloaded: ${filename}"
    done
fi

# Ensure permissions
chown -R 988:988 "${SERVER_DIR}" 2>/dev/null || true
chmod -R 755 "${SERVER_DIR}/scripts" "${SERVER_DIR}/bin" 2>/dev/null || true
[ -f "${SERVER_DIR}/run.sh" ] && chmod +x "${SERVER_DIR}/run.sh"
[ -f "${SERVER_DIR}/entrypoint.sh" ] && chmod +x "${SERVER_DIR}/entrypoint.sh"

ok "Installation completed successfully."
