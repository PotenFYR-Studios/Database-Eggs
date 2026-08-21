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

log()  { echo -e "\033[1m\033[36m[install]\033[0m $*"; }
ok()   { echo -e "\033[1m\033[32m[install][OK]\033[0m $*"; }
warn() { echo -e "\033[1m\033[33m[install][warn]\033[0m $*"; }
fail() { echo -e "\033[1m\033[31m[install][ERROR]\033[0m $*"; exit 1; }

ARCH=$(uname -m)
case "${ARCH}" in
    x86_64|amd64) ARCH_TYPE="amd64"; ARCH_ALT="x86_64" ;;
    aarch64|arm64) ARCH_TYPE="arm64"; ARCH_ALT="aarch64" ;;
    *) ARCH_TYPE="amd64"; ARCH_ALT="x86_64" ;;
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

# Copy or download repository scripts into server root
REPO_BASE="https://raw.githubusercontent.com/PotenFYR-Studios/Database-Eggs/main"

# 1. Check local image copies in /usr/local/bin
if [ -f /usr/local/bin/run.sh ]; then
    cp -f /usr/local/bin/run.sh "${SERVER_DIR}/run.sh" 2>/dev/null || true
    cp -f /usr/local/bin/entrypoint.sh "${SERVER_DIR}/entrypoint.sh" 2>/dev/null || true
    cp -rf /usr/local/bin/*.sh "${SERVER_DIR}/scripts/" 2>/dev/null || true
fi

# 2. If missing, download from GitHub raw
if [ ! -f "${SERVER_DIR}/run.sh" ]; then
    log "Fetching latest runtime scripts from GitHub..."
    curl -fsSL --retry 3 "${REPO_BASE}/run.sh" -o "${SERVER_DIR}/run.sh" 2>/dev/null || true
    curl -fsSL --retry 3 "${REPO_BASE}/entrypoint.sh" -o "${SERVER_DIR}/entrypoint.sh" 2>/dev/null || true
    for h in password-gen.sh performance-tuning.sh install-db-version.sh db-init-mariadb.sh db-init-postgres.sh db-init-redis.sh db-init-mongo.sh db-init-surreal.sh db-init-search.sh db-init-storage.sh; do
        curl -fsSL --retry 2 "${REPO_BASE}/scripts/${h}" -o "${SERVER_DIR}/scripts/${h}" 2>/dev/null || true
    done
fi

# Invoke universal version installer if present
if [ -f "${SERVER_DIR}/scripts/install-db-version.sh" ]; then
    bash "${SERVER_DIR}/scripts/install-db-version.sh" "${PROJECT_TYPE}" "${DB_VERSION}" "${SERVER_DIR}/bin" || true
elif [ -f /usr/local/bin/install-db-version.sh ]; then
    /usr/local/bin/install-db-version.sh "${PROJECT_TYPE}" "${DB_VERSION}" "${SERVER_DIR}/bin" || true
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
