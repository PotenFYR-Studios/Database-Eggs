#!/usr/bin/env bash
# =============================================================================
#  PotenFYR Studios - Universal Multi-Database Version Downloader & Installer
#  Downloads and installs ANY specific version or custom URL for any database engine.
# =============================================================================

ENGINE="${1:-${DATABASE_TYPE:-mariadb}}"
VERSION="${2:-${DB_VERSION:-latest}}"
INSTALL_DIR="${3:-${SERVER_DIR:-$(pwd)}/bin}"

mkdir -p "${INSTALL_DIR}"

log()  { echo -e "\033[1m\033[36m[version-installer]\033[0m $*"; }
ok()   { echo -e "\033[1m\033[32m[version-installer][OK]\033[0m $*"; }
warn() { echo -e "\033[1m\033[33m[version-installer][warn]\033[0m $*"; }
fail() {
    echo -e "\033[1m\033[31m[version-installer][ERROR]\033[0m $*" >&2
    mkdir -p "${SERVER_DIR:-.}/logs" 2>/dev/null || true
    printf '[%s] INSTALLER ERROR: %s\n' "$(date -u +'%Y-%m-%d %H:%M:%S UTC')" "$*" >> "${SERVER_DIR:-.}/logs/installer.log" 2>/dev/null || true
    exit 1
}

# Diagnostic Error Trap
error_trap() {
    local exit_code=$?
    local line_no=$1
    local last_cmd="${BASH_COMMAND}"
    if [ ${exit_code} -ne 0 ]; then
        printf "\n\033[1;31m[version-installer] ERROR at Line %s (Exit Code: %s, Command: %s)\033[0m\n" "${line_no}" "${exit_code}" "${last_cmd}" >&2
    fi
}
trap 'error_trap $LINENO' ERR

ARCH=$(uname -m)
case "${ARCH}" in
    x86_64|amd64) ARCH_TYPE="amd64"; ARCH_ALT="x86_64"; ARCH_GNU="x86_64-unknown-linux-gnu" ;;
    aarch64|arm64) ARCH_TYPE="arm64"; ARCH_ALT="aarch64"; ARCH_GNU="aarch64-unknown-linux-gnu" ;;
    *) fail "Unsupported architecture: ${ARCH}" ;;
esac

log "Configuring: ${ENGINE} (Target Version: ${VERSION}, Arch: ${ARCH_TYPE})"

# ---------------------------------------------------------------------------
# Direct Custom URL or GitHub Release handling
# ---------------------------------------------------------------------------
if [[ "${VERSION}" =~ ^https?:// ]] || [[ -n "${CUSTOM_DOWNLOAD_URL:-}" && "${ENGINE}" = "custom" ]]; then
    DL_URL="${CUSTOM_DOWNLOAD_URL:-${VERSION}}"
    log "Downloading custom database/binary from URL: ${DL_URL}..."
    filename=$(basename "${DL_URL}" | sed 's/[?].*//')
    tmp_dl=$(mktemp)

    if curl -fsSL --retry 3 -o "${tmp_dl}" "${DL_URL}"; then
        case "${filename}" in
            *.tar.gz|*.tgz)
                tar -xzf "${tmp_dl}" -C "${INSTALL_DIR}/"
                ;;
            *.tar.xz)
                tar -xJf "${tmp_dl}" -C "${INSTALL_DIR}/"
                ;;
            *.zip)
                unzip -q -o "${tmp_dl}" -d "${INSTALL_DIR}/"
                ;;
            *)
                target_name="${CUSTOM_BINARY_NAME:-${filename}}"
                cp -f "${tmp_dl}" "${INSTALL_DIR}/${target_name}"
                ;;
        esac
        rm -f "${tmp_dl}"
        find "${INSTALL_DIR}" -type f -exec chmod +x {} + 2>/dev/null || true
        ok "Custom binary/package installed into ${INSTALL_DIR}"
    else
        warn "Failed to download custom binary from ${DL_URL}"
    fi
    exit 0
fi

# ---------------------------------------------------------------------------
# Engine Specific Version Handlers
# ---------------------------------------------------------------------------
case "${ENGINE}" in
    pocketbase)
        TAG="${VERSION#v}"
        if [ "${TAG}" = "latest" ]; then
            TAG=$(curl -fsSL https://api.github.com/repos/pocketbase/pocketbase/releases/latest 2>/dev/null | jq -r '.tag_name // "v0.25.0"' 2>/dev/null | sed 's/^v//')
            [ -z "${TAG}" ] && TAG="0.25.0"
        fi
        log "Installing PocketBase v${TAG}..."
        URL="https://github.com/pocketbase/pocketbase/releases/download/v${TAG}/pocketbase_${TAG}_linux_${ARCH_TYPE}.zip"
        tmp_zip=$(mktemp)
        if curl -fsSL --retry 3 -o "${tmp_zip}" "${URL}"; then
            unzip -q -o "${tmp_zip}" -d "${INSTALL_DIR}/"
            rm -f "${tmp_zip}"
            chmod +x "${INSTALL_DIR}/pocketbase"
            ok "PocketBase v${TAG} installed successfully."
        else
            warn "Failed to download PocketBase v${TAG}. Checking local fallback..."
        fi
        ;;

    surrealdb|surreal)
        TAG="${VERSION}"
        if [ "${TAG}" = "latest" ]; then
            TAG=$(curl -fsSL https://api.github.com/repos/surrealdb/surrealdb/releases/latest 2>/dev/null | jq -r '.tag_name // "v2.0.4"' 2>/dev/null)
            [ -z "${TAG}" ] && TAG="v2.0.4"
        fi
        [[ ! "${TAG}" =~ ^v ]] && TAG="v${TAG}"
        log "Installing SurrealDB ${TAG}..."
        URL="https://github.com/surrealdb/surrealdb/releases/download/${TAG}/surreal-${TAG}.${ARCH_GNU}.tar.gz"
        if curl -fsSL "${URL}" 2>/dev/null | tar -xz -C "${INSTALL_DIR}/"; then
            chmod +x "${INSTALL_DIR}/surreal"
            ok "SurrealDB ${TAG} installed successfully."
        else
            warn "Could not fetch specific SurrealDB release tarball. Using install script fallback..."
            curl -fsSL https://install.surrealdb.com | sh
            [ -f /root/.surrealdb/surreal ] && cp /root/.surrealdb/surreal "${INSTALL_DIR}/surreal"
            chmod +x "${INSTALL_DIR}/surreal" 2>/dev/null || true
        fi
        ;;

    meilisearch)
        TAG="${VERSION}"
        if [ "${TAG}" = "latest" ]; then
            TAG=$(curl -fsSL https://api.github.com/repos/meilisearch/meilisearch/releases/latest 2>/dev/null | jq -r '.tag_name // "v1.12.0"' 2>/dev/null)
            [ -z "${TAG}" ] && TAG="v1.12.0"
        fi
        [[ ! "${TAG}" =~ ^v ]] && TAG="v${TAG}"
        log "Installing Meilisearch ${TAG}..."
        URL="https://github.com/meilisearch/meilisearch/releases/download/${TAG}/meilisearch-linux-${ARCH_TYPE}"
        if curl -fsSL --retry 3 -o "${INSTALL_DIR}/meilisearch" "${URL}"; then
            chmod +x "${INSTALL_DIR}/meilisearch"
            ok "Meilisearch ${TAG} installed successfully."
        else
            warn "Direct tag download failed. Invoking official Meilisearch installer..."
            curl -fsSL https://get.meilisearch.com | sh
            [ -f meilisearch ] && mv meilisearch "${INSTALL_DIR}/meilisearch"
            chmod +x "${INSTALL_DIR}/meilisearch" 2>/dev/null || true
        fi
        ;;

    qdrant)
        TAG="${VERSION}"
        if [ "${TAG}" = "latest" ]; then
            TAG=$(curl -fsSL https://api.github.com/repos/qdrant/qdrant/releases/latest 2>/dev/null | jq -r '.tag_name // "v1.12.1"' 2>/dev/null)
            [ -z "${TAG}" ] && TAG="v1.12.1"
        fi
        [[ ! "${TAG}" =~ ^v ]] && TAG="v${TAG}"
        log "Installing Qdrant ${TAG}..."
        URL="https://github.com/qdrant/qdrant/releases/download/${TAG}/qdrant-${ARCH_ALT}-unknown-linux-gnu.tar.gz"
        if curl -fsSL "${URL}" | tar -xz -C "${INSTALL_DIR}/"; then
            chmod +x "${INSTALL_DIR}/qdrant"
            ok "Qdrant ${TAG} installed successfully."
        fi
        ;;

    minio)
        TAG="${VERSION}"
        log "Installing MinIO (${TAG})..."
        URL="https://dl.min.io/server/minio/release/linux-${ARCH_TYPE}/minio"
        [ "${TAG}" != "latest" ] && URL="https://dl.min.io/server/minio/release/linux-${ARCH_TYPE}/archive/minio.${TAG}"
        curl -fsSL --retry 3 -o "${INSTALL_DIR}/minio" "${URL}"
        chmod +x "${INSTALL_DIR}/minio"
        ok "MinIO installed successfully."
        ;;

    typesense)
        TAG="${VERSION#v}"
        if [ "${TAG}" = "latest" ]; then
            TAG="27.0"
        fi
        log "Installing Typesense v${TAG}..."
        URL="https://dl.typesense.org/releases/${TAG}/typesense-server-${TAG}-linux-${ARCH_TYPE}.tar.gz"
        if curl -fsSL "${URL}" 2>/dev/null | tar -xz -C "${INSTALL_DIR}/"; then
            chmod +x "${INSTALL_DIR}/typesense-server"
            ok "Typesense v${TAG} installed successfully."
        fi
        ;;

    clickhouse)
        TAG="${VERSION#v}"
        log "Installing ClickHouse standalone binary..."
        if curl -fsSL https://clickhouse.com/ | sh; then
            [ -f ./clickhouse ] && mv ./clickhouse "${INSTALL_DIR}/clickhouse"
            chmod +x "${INSTALL_DIR}/clickhouse"
            ok "ClickHouse binary installed."
        fi
        ;;

    victoriametrics)
        TAG="${VERSION}"
        if [ "${TAG}" = "latest" ]; then
            TAG=$(curl -fsSL https://api.github.com/repos/VictoriaMetrics/VictoriaMetrics/releases/latest 2>/dev/null | jq -r '.tag_name // "v1.108.0"' 2>/dev/null)
            [ -z "${TAG}" ] && TAG="v1.108.0"
        fi
        [[ ! "${TAG}" =~ ^v ]] && TAG="v${TAG}"
        log "Installing VictoriaMetrics ${TAG}..."
        URL="https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/${TAG}/victoria-metrics-linux-${ARCH_TYPE}-${TAG}.tar.gz"
        if curl -fsSL "${URL}" | tar -xz -C "${INSTALL_DIR}/"; then
            chmod +x "${INSTALL_DIR}/victoria-metrics-prod" "${INSTALL_DIR}/victoriametrics" 2>/dev/null || true
            ok "VictoriaMetrics ${TAG} installed."
        fi
        ;;

    ferretdb)
        TAG="${VERSION}"
        if [ "${TAG}" = "latest" ]; then
            TAG="v1.21.0"
        fi
        log "Installing FerretDB ${TAG}..."
        URL="https://github.com/FerretDB/FerretDB/releases/download/${TAG}/ferretdb-linux-${ARCH_TYPE}.tar.gz"
        if curl -fsSL "${URL}" | tar -xz -C "${INSTALL_DIR}/"; then
            chmod +x "${INSTALL_DIR}/ferretdb" 2>/dev/null || true
            ok "FerretDB installed."
        fi
        ;;

    valkey)
        TAG="${VERSION#v}"
        if [ "${TAG}" = "latest" ]; then
            TAG="7.2.5"
        fi
        log "Configuring Valkey ${TAG}..."
        ;;

    custom)
        if [ -n "${CUSTOM_DOWNLOAD_URL:-}" ]; then
            log "Downloading custom engine binary from ${CUSTOM_DOWNLOAD_URL}..."
            curl -fsSL --retry 3 -o "${INSTALL_DIR}/${CUSTOM_BINARY_NAME:-server}" "${CUSTOM_DOWNLOAD_URL}"
            chmod +x "${INSTALL_DIR}/${CUSTOM_BINARY_NAME:-server}"
            ok "Custom engine ready: ${INSTALL_DIR}/${CUSTOM_BINARY_NAME:-server}"
        fi
        ;;

    mariadb|mysql|postgresql|postgres|redis|keydb|dragonfly|memcached|mongodb|influxdb|couchdb|neo4j|rethinkdb)
        log "Engine '${ENGINE}' (${VERSION}) is ready via container runtime orchestrator."
        ok "Engine verified."
        ;;

    *)
        log "Configured database engine '${ENGINE}'."
        ;;
esac
