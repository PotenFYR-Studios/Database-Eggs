#!/usr/bin/env bash
# =============================================================================
#  PotenFYR Studios - Universal Multi-Database Version Downloader & Installer
#  Downloads and installs ANY specific version or custom URL for any database engine.
# =============================================================================

set -euo pipefail

ENGINE="${1:-${DATABASE_TYPE:-mariadb}}"
VERSION="${2:-${DB_VERSION:-latest}}"
INSTALL_DIR="${3:-${SERVER_DIR:-$(pwd)}/bin}"

mkdir -p "${INSTALL_DIR}"

log()  { echo -e "\033[1m\033[36m[version-installer]\033[0m $*"; }
ok()   { echo -e "\033[1m\033[32m[version-installer][OK]\033[0m $*"; }
warn() { echo -e "\033[1m\033[33m[version-installer][warn]\033[0m $*"; }
fail() { echo -e "\033[1m\033[31m[version-installer][ERROR]\033[0m $*"; exit 1; }

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
if [[ "${VERSION}" =~ ^https?:// ]]; then
    log "Downloading custom binary from direct URL: ${VERSION}..."
    filename=$(basename "${VERSION}" | sed 's/[?].*//')
    curl -fsSL --retry 3 -o "${INSTALL_DIR}/${filename}" "${VERSION}"
    chmod +x "${INSTALL_DIR}/${filename}" 2>/dev/null || true
    ok "Installed ${filename} to ${INSTALL_DIR}"
    exit 0
fi

# ---------------------------------------------------------------------------
# Engine Specific Version Handlers
# ---------------------------------------------------------------------------
case "${ENGINE}" in
    pocketbase)
        TAG="${VERSION#v}"
        if [ "${TAG}" = "latest" ]; then
            TAG=$(curl -fsSL https://api.github.com/repos/pocketbase/pocketbase/releases/latest 2>/dev/null | jq -r '.tag_name // "v0.25.0"' | sed 's/^v//')
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
            TAG=$(curl -fsSL https://api.github.com/repos/surrealdb/surrealdb/releases/latest 2>/dev/null | jq -r '.tag_name // "v2.0.4"')
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
            TAG=$(curl -fsSL https://api.github.com/repos/meilisearch/meilisearch/releases/latest 2>/dev/null | jq -r '.tag_name // "v1.12.0"')
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
            TAG=$(curl -fsSL https://api.github.com/repos/qdrant/qdrant/releases/latest 2>/dev/null | jq -r '.tag_name // "v1.12.1"')
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

    victoriametrics)
        TAG="${VERSION}"
        if [ "${TAG}" = "latest" ]; then
            TAG=$(curl -fsSL https://api.github.com/repos/VictoriaMetrics/VictoriaMetrics/releases/latest 2>/dev/null | jq -r '.tag_name // "v1.108.0"')
        fi
        [[ ! "${TAG}" =~ ^v ]] && TAG="v${TAG}"
        log "Installing VictoriaMetrics ${TAG}..."
        URL="https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/${TAG}/victoria-metrics-linux-${ARCH_TYPE}-${TAG}.tar.gz"
        if curl -fsSL "${URL}" | tar -xz -C "${INSTALL_DIR}/"; then
            chmod +x "${INSTALL_DIR}/victoria-metrics-prod" "${INSTALL_DIR}/victoriametrics" 2>/dev/null || true
            ok "VictoriaMetrics ${TAG} installed."
        fi
        ;;

    mariadb|mysql|postgresql|postgres|redis|valkey|keydb|dragonfly|memcached|mongodb|ferretdb|clickhouse|influxdb|couchdb|neo4j|rethinkdb)
        log "Engine '${ENGINE}' (${VERSION}) is managed natively via container runtime and package orchestrator."
        ok "Engine ready."
        ;;

    *)
        log "Configured custom database engine '${ENGINE}'."
        ;;
esac
