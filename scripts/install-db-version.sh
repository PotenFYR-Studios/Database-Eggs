#!/usr/bin/env bash
# =============================================================================
#  PotenFYR Studios - Universal Multi-Database Version Downloader & Installer
#  Installs ANY specific version (or dynamically-resolved 'latest') for 55+
#  database engines. Fully unprivileged-capable (installs under server bin/),
#  checksum-verifying, disk-aware, cached, and air-gap friendly.
#
#  Usage:
#    install-db-version.sh <engine> <version|latest|URL> <install_dir>
#
#  Environment switches:
#    SKIP_VERSION_INSTALL=1   Bypass all downloads (use system binaries only)
#    VERIFY_CHECKSUMS=1       Enforce sha256 sidecar checks (default: auto)
#    PF_INSTALLER_DEBUG=1     Verbose installer trace
#
#  Exit codes: 0 success | 1 requested explicit version unavailable
# =============================================================================
set -u

ENGINE="${1:-${DATABASE_TYPE:-mariadb}}"
VERSION="${2:-${DB_VERSION:-latest}}"
INSTALL_DIR="${3:-${SERVER_DIR:-$(pwd)}/bin}"

mkdir -p "${INSTALL_DIR}" "${INSTALL_DIR}/.versions" "${SERVER_DIR:-.}/logs" 2>/dev/null || true

# -----------------------------------------------------------------------------
# Central Diagnostics Library (unified logging, traces, crash safety)
# -----------------------------------------------------------------------------
PF_COMPONENT="version-installer"
PANEL_NAME="${PANEL_NAME:-version-installer}"
PF_FAIL_FAST=1
PF_FAIL_SLEEP=0
PF_LOG_FILE="${SERVER_DIR:-.}/logs/installer.log"
PF_INSTALLER_LOG="${PF_LOG_FILE}"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-diagnostics.sh" 2>/dev/null \
    || source /usr/local/bin/lib-diagnostics.sh 2>/dev/null \
    || source ./lib-diagnostics.sh 2>/dev/null

if [ "${PF_DIAG_VERSION:-}" != "1.0" ]; then
    # Minimal fallback if library unavailable
    log()  { echo "[version-installer] $*"; }
    ok()   { echo "[version-installer][OK] $*"; }
    warn() { echo "[version-installer][warn] $*" >&2; }
    err()  { echo "[version-installer][ERROR] $*" >&2; }
    fail() { err "$*"; exit 1; }
fi

# -----------------------------------------------------------------------------
# Tooling & architecture
# -----------------------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

# -----------------------------------------------------------------------------
# Architecture matrix: panels run everywhere; resolve canonical names once.
#   ARCH_TYPE : asset suffix style (amd64/arm64/arm/s390x/ppc64le/riscv64/386)
#   ARCH_ALT  : legacy suffix style (x86_64/aarch64/arm/s390x/ppc64le/riscv64/i686)
#   ARCH_GNU  : rust-style target triple for standalone builds
#   ARCH_DEB  : debian pool suffix for runtime-lib bundling
# -----------------------------------------------------------------------------
ARCH=$(uname -m)
case "${ARCH}" in
    x86_64|amd64)
        ARCH_TYPE="amd64"; ARCH_ALT="x86_64"; ARCH_DEB="amd64"
        ARCH_GNU="x86_64-unknown-linux-gnu"; ARCH_MUSL="x86_64-unknown-linux-musl" ;;
    aarch64|arm64)
        ARCH_TYPE="arm64"; ARCH_ALT="aarch64"; ARCH_DEB="arm64"
        ARCH_GNU="aarch64-unknown-linux-gnu"; ARCH_MUSL="aarch64-unknown-linux-musl" ;;
    armv7l|armv7|armv6l|armhf)
        ARCH_TYPE="arm"; ARCH_ALT="arm"; ARCH_DEB="armhf"
        ARCH_GNU="arm-unknown-linux-gnueabihf"; ARCH_MUSL="arm-unknown-linux-musleabihf" ;;
    s390x)
        ARCH_TYPE="s390x"; ARCH_ALT="s390x"; ARCH_DEB="s390x"
        ARCH_GNU="s390x-unknown-linux-gnu"; ARCH_MUSL="s390x-unknown-linux-musl" ;;
    ppc64le|ppc64)
        ARCH_TYPE="ppc64le"; ARCH_ALT="ppc64le"; ARCH_DEB="ppc64el"
        ARCH_GNU="powerpc64le-unknown-linux-gnu"; ARCH_MUSL="powerpc64le-unknown-linux-musl" ;;
    riscv64)
        ARCH_TYPE="riscv64"; ARCH_ALT="riscv64"; ARCH_DEB="riscv64"
        ARCH_GNU="riscv64-unknown-linux-gnu"; ARCH_MUSL="riscv64-unknown-linux-musl" ;;
    i386|i486|i586|i686)
        ARCH_TYPE="386"; ARCH_ALT="i686"; ARCH_DEB="i386"
        ARCH_GNU="i686-unknown-linux-gnu"; ARCH_MUSL="i686-unknown-linux-musl" ;;
    *)
        # Unknown future architectures: fall back to closest common naming,
        # every installer probes URLs before trusting them anyway.
        warn "Unrecognized architecture '${ARCH}'; assuming 64-bit little-endian."
        ARCH_TYPE="amd64"; ARCH_ALT="x86_64"; ARCH_DEB="amd64"
        ARCH_GNU="x86_64-unknown-linux-gnu"; ARCH_MUSL="x86_64-unknown-linux-musl" ;;
esac

# Which engines publish binaries for THIS architecture? Prevents pointless
# network probing and enables transparent system-engine fallback elsewhere.
engine_supports_arch() {
    local want="${ARCH_TYPE}"
    local e="$1"
    case "${e}:${want}" in
        postgresql:amd64|postgresql:arm64|postgresql:arm)      return 0 ;;
        mariadb:amd64|mariadb:arm64)                            return 0 ;;
        mysql:amd64|mysql:arm64)                                return 0 ;;
        mongodb:amd64|mongodb:arm64|mongodb:s390x)              return 0 ;;
        dragonfly:amd64|dragonfly:arm64)                        return 0 ;;
        ferretdb:amd64|ferretdb:arm64)                          return 0 ;;
        clickhouse:amd64|clickhouse:arm64)                      return 0 ;;
        influxdb:amd64|influxdb:arm64|influxdb:arm)             return 0 ;;
        victoriametrics:amd64|victoriametrics:arm64|\
        victoriametrics:arm|victoriametrics:ppc64le|\
        victoriametrics:386)                                    return 0 ;;
        pocketbase:amd64|pocketbase:arm64)                      return 0 ;;
        meilisearch:amd64|meilisearch:arm64)                    return 0 ;;
        qdrant:amd64|qdrant:arm64)                              return 0 ;;
        typesense:amd64|typesense:arm64)                        return 0 ;;
        minio:amd64|minio:arm64|minio:ppc64le|minio:s390x)      return 0 ;;
        cockroachdb:amd64|cockroachdb:arm64)                    return 0 ;;
        tidb:amd64|tidb:arm64)                                  return 0 ;;
        dolt:amd64|dolt:arm64)                                  return 0 ;;
        *)
            case "${e}" in
                etcd|nats|immudb|dgraph|seaweedfs|weaviate|quickwit|milvus|libsql|sqld|garage|manticoresearch|manticore|yugabytedb|yugabyte|arangodb|ravendb|orientdb|elasticsearch|opensearch|solr|cassandra|aerospike|questdb|neo4j|rethinkdb|keydb|valkey|redis|memcached|custom)
                    # Source-built, Java-based, tarball-distributed or
                    # deb-extracted engines: attempt regardless of arch.
                    return 0 ;;
                *)
                    # Single-binary GitHub releases: assume amd64/arm64 only.
                    case "${want}" in amd64|arm64) return 0 ;; *) return 1 ;; esac
                    ;;
            esac
            ;;
    esac
}

# Transparent fallback when upstream simply does not ship our architecture.
# Policy: warn loudly, stamp, and let the container-provided engine serve.
# STRICT_VERSION still applies whenever an upstream build DOES exist.
no_arch_build_fallback() {
    warn "Upstream ${ENGINE} does not publish ${ARCH_TYPE} binaries."
    warn "Falling back to the container-provided ${ENGINE}. Version pins resume on amd64/arm64 hosts."
    RESOLVED="${RESOLVED}-system-${ARCH_TYPE}"
    stamp_ok
    exit 0
}

# Environmental impossibility (no compiler, no root, CDN blocked, etc.):
# never brick the server. Warn loudly, mark the substitution so the launcher's
# strict verifier announces it instead of failing, and continue with the
# container-provided engine. Exact-version service resumes automatically in
# environments where provisioning becomes possible.
fallback_to_system() {
    local reason="$1"
    warn "${reason}"
    warn "Falling back to the container-provided ${ENGINE}. Your pinned version '${VERSION}' could not be provisioned in this environment."
    warn "To serve the exact version: run on a base image with build tools, grant root, or choose DB_VERSION=latest."
    printf '%s\n' "${RESOLVED}" > "${stamp_dir}/${ENGINE}-system-fallback" 2>/dev/null || true
    RESOLVED="${RESOLVED}-system-fallback"
    stamp_ok
    exit 0
}

_json_tags() { # Extract tag_name values without jq (first match wins upstream order)
    if have jq; then jq -r '.tag_name // .[0].tag_name // empty' 2>/dev/null; else
        grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | sed -E 's/.*"([^"]*)"[[:space:]]*$/\1/'
    fi
}

gh_latest_tag() { # gh_latest_tag <owner/repo> [include_prereleases]
    local repo="$1" pre="${2:-0}" tag=""
    if [ "${pre}" = "1" ]; then
        # Newest release of ANY kind (beta/alpha/rc/nightly included)
        tag=$(fetch "https://api.github.com/repos/${repo}/releases?per_page=10" - 2>/dev/null | \
            if have jq; then jq -r '[.[].tag_name][0] // empty'; else
                grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | sed -E 's/.*"([^"]*)"[[:space:]]*$/\1/'
            fi)
    else
        tag=$(fetch "https://api.github.com/repos/${1}/releases/latest" - 2>/dev/null | _json_tags)
        [ -z "${tag}" ] && tag=$(fetch "https://api.github.com/repos/${1}/releases?per_page=5" - 2>/dev/null | _json_tags)
    fi
    printf '%s' "${tag}"
}

# Validate user-supplied version input; reject injection/garbage early with
# actionable guidance. Accepts: latest|stable|beta|alpha|nightly|edge|default,
# x / x.y / x.y.z, optional v prefix, or full https URLs.
validate_version_input() {
    local v="${VERSION}"
    case "${v}" in
        ""|latest|stable|beta|alpha|nightly|edge|dev|default) return 0 ;;
        https://*|http://*) return 0 ;;
        v[0-9]*|[0-9]*) [[ "${v#[v]}" =~ ^[0-9]+(\.[0-9]+){0,3}([-._]?[A-Za-z0-9]+)*$ ]] && return 0 ;;
    esac
    fail "Invalid DB_VERSION '${v}'. Valid forms: latest | stable | beta | alpha |
  nightly | a major (18), series (11.4), exact version (8.0.45, v2.1.0),
  or a direct download URL."
}

ARCH=$(uname -m)
# (Architecture canonicalization lives in the full matrix above.)

# Libc family: gnu builds need glibc; musl builds target Alpine-like hosts.
if command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; then
    PF_LIBC="musl"
else
    PF_LIBC="gnu"
fi

IS_ROOT=0
[ "$(id -u 2>/dev/null || echo 1)" = "0" ] && IS_ROOT=1

fetch() { # fetch <url> <outfile|->   (atomic for file output: temp + rename)
    local url="$1" out="$2"
    local UA="PotenFYR-Installer/1.0 (+https://github.com/PotenFYR-Studios/Database-Eggs)"
    if [ "${out}" = "-" ]; then
        curl -fsSL -A "${UA}" --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 1800 "${url}" 2>/dev/null \
            || wget -qO- --tries=3 --timeout=20 -U "${UA}" "${url}" 2>/dev/null
        return
    fi
    local tmp_out="${out}.dl.$$"
    rm -f "${tmp_out}"
    if curl -fsSL -A "${UA}" --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 3600 -o "${tmp_out}" "${url}" 2>/dev/null \
       || wget -qO "${tmp_out}" --tries=3 --timeout=20 "${url}" 2>/dev/null; then
        if [ -s "${tmp_out}" ]; then
            mv -f "${tmp_out}" "${out}"
            return 0
        fi
    fi
    rm -f "${tmp_out}"
    return 1
}

# Candidate downloader: HEAD probes first (fast); when a CDN blocks or lies
# about HEAD (Akamai et al.), falls back to bounded real GET attempts.
try_fetch_candidates() { # try_fetch_candidates <outfile> <url> [url...]
    local out="$1"; shift
    local u n=0
    for u in "$@"; do
        probe_url "${u}" || continue
        if fetch "${u}" "${out}" && [ -s "${out}" ]; then printf '%s' "${u}"; return 0; fi
    done
    for u in "$@"; do
        n=$((n + 1)); [ ${n} -gt 4 ] && break
        rm -f "${out}"
        if fetch "${u}" "${out}" && [ -s "${out}" ]; then printf '%s' "${u}"; return 0; fi
    done
    rm -f "${out}"
    return 1
}

# Some CDNs (Akamai-fronted hosts like cdn.mysql.com) reject tool-default
# user agents from datacenter IPs; present an honest client UA everywhere.
PF_CURL_UA="${PF_CURL_UA:-PotenFYR-Installer/1.0 (+https://github.com/PotenFYR-Studios/Database-Eggs)}"

probe_url() { curl -fsIL -A "${PF_CURL_UA}" --retry 1 --connect-timeout 10 --max-time 25 -o /dev/null "$1" 2>/dev/null; }

# shellcheck disable=SC2120
eofl_resolve() { # eofl_resolve <product> <prefix>
    local product="$1" prefix="${2:-}"
    local cache_file="/tmp/.eofl-cache-${product}.json"
    if [ ! -s "${cache_file}" ]; then
        fetch "https://endoflife.date/api/${product}.json" "${cache_file}" || true
    fi
    [ -s "${cache_file}" ] || return 1

    if have jq; then
        if [ -n "${prefix}" ]; then
            jq -r --arg p "${prefix}" '[.[] | select(.cycle | startswith($p))][0].latest // empty' "${cache_file}" 2>/dev/null
        else
            jq -r '.[0].latest // empty' "${cache_file}" 2>/dev/null
        fi
    else
        # jq-less fallback: pair up cycle/latest fields in document order
        paste \
            <(grep -oE '"cycle"[[:space:]]*:[[:space:]]*"[^"]*"' "${cache_file}" | sed -E 's/.*"([^"]*)"[[:space:]]*$/\1/') \
            <(grep -oE '"latest"[[:space:]]*:[[:space:]]*"[^"]*"' "${cache_file}" | sed -E 's/.*"([^"]*)"[[:space:]]*$/\1/') \
        | awk -F'\t' -v p="${prefix}" '
            NF<2 {next}
            p=="" && !done {print $2; done=1; exit}
            index($1, p)==1 {print $2; exit}'
    fi
}

verify_checksum() { # verify_checksum <file> <sidecar_url>
    local f="$1" sidecar="$2"
    [ -z "${sidecar}" ] && return 0
    have sha256sum || return 0
    local expected actual
    expected=$(fetch "${sidecar}" - 2>/dev/null | awk '{print $1}' | head -n1)
    [ -z "${expected}" ] && return 0
    actual=$(sha256sum "${f}" 2>/dev/null | awk '{print $1}')
    if [ -n "${actual}" ] && [ "${actual}" = "${expected}" ]; then return 0; fi
    err "SHA256 verification FAILED for $(basename "${f}") (corrupt or tampered download)"
    return 1
}

disk_preflight_mb() { # warn when less than <mb> available
    local need_mb="${1:-1024}" avail_kb
    avail_kb=$(df -Pk "${INSTALL_DIR}" 2>/dev/null | awk 'NR==2{print $4}')
    if [ -n "${avail_kb}" ] && [ "${avail_kb}" -lt $((need_mb * 1024)) ]; then
        warn "Low disk: ${ENGINE} ${RESOLVED} wants ~${need_mb}MB; only $((avail_kb / 1024))MB free."
        return 1
    fi
    return 0
}

apt_try_install() {
    # Container isolation guarantee: system package installation ONLY happens
    # when the operator explicitly opts in via ALLOW_SYSTEM_APT=1 AND we run as root.
    [ "${ALLOW_SYSTEM_APT:-0}" = "1" ] || return 1
    if [ "${IS_ROOT}" = "1" ] && have apt-get; then
        DEBIAN_FRONTEND=noninteractive apt-get update -qq 2>/dev/null || true
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "$@" 2>/dev/null && return 0
    fi
    return 1
}

extract_libaio() { # bundle libaio.so.1 + libnuma.so.1 beside daemons that link them (MariaDB/MySQL bintars)
    local dest="$1"
    mkdir -p "${dest}"
    local arch_deb="${ARCH_DEB}"
    local u tmp_deb need=0

    [ -e "${dest}/libaio.so.1" ] || need=1
    if [ "${need}" = "1" ]; then
        for u in \
            "https://archive.ubuntu.com/ubuntu/pool/main/liba/libaio/libaio1_0.3.112-13build1_${arch_deb}.deb" \
            "https://deb.debian.org/debian/pool/main/liba/libaio/libaio1_0.3.112-13build1_${arch_deb}.deb"; do
            tmp_deb=$(mktemp)
            if fetch "${u}" "${tmp_deb}" && dpkg-deb -x "${tmp_deb}" "${dest}/.lx" 2>/dev/null; then
                find "${dest}/.lx" -name 'libaio.so*' -exec cp -a {} "${dest}/" \; 2>/dev/null || true
                rm -rf "${dest}/.lx" "${tmp_deb}"
                [ -e "${dest}/libaio.so.1" ] && break
            fi
            rm -f "${tmp_deb}"
        done
    fi
    [ -e "${dest}/libaio.so.1" ] || warn "Could not bundle libaio.so.1."

    [ -e "${dest}/libnuma.so.1" ] && return 0
    for u in \
        "https://archive.ubuntu.com/ubuntu/pool/main/n/numactl/libnuma1_2.0.14-3ubuntu2_${arch_deb}.deb" \
        "https://archive.ubuntu.com/ubuntu/pool/main/n/numactl/libnuma1_2.0.18-1_${arch_deb}.deb"; do
        tmp_deb=$(mktemp)
        if fetch "${u}" "${tmp_deb}" && dpkg-deb -x "${tmp_deb}" "${dest}/.nx" 2>/dev/null; then
            find "${dest}/.nx" -name 'libnuma.so*' -exec cp -a {} "${dest}/" \; 2>/dev/null || true
            rm -rf "${dest}/.nx" "${tmp_deb}"
            [ -e "${dest}/libnuma.so.1" ] && break
        fi
        rm -f "${tmp_deb}"
    done
    return 0
}

# Enforce executable bit + non-empty payload on every installed single binary.
# Fixes rare Permission-denied exec failures regardless of umask/mount quirks.
seal_binary() { # seal_binary <path>
    local f="$1"
    [ -f "${f}" ] || { warn "seal_binary: ${f} missing."; return 1; }
    [ -s "${f}" ] || { warn "seal_binary: ${f} is empty."; return 1; }
    chmod 755 "${f}" 2>/dev/null || true
    chmod +x "${f}" 2>/dev/null || true
    if [ ! -x "${f}" ]; then
        err "Binary not executable after chmod: ${f}"
        ls -la "$(dirname "${f}")" >&2 2>/dev/null | tail -n 5
        return 1
    fi
    return 0
}

ensure_java() { # Temurin JRE 17 for Java-hosted engines (Neo4j, Cassandra, Solr, OrientDB...)
    if have java && java -version 2>&1 | grep -qE 'version "(17|18|19|20|21|22)'; then
        export JAVA_HOME="${JAVA_HOME:-$(dirname "$(dirname "$(command -v java)")")}"
        return 0
    fi
    local jdir="${SERVER_DIR:-${HOME}}/.runtimes/jdk17"
    if [ -x "${jdir}/bin/java" ]; then
        export JAVA_HOME="${jdir}"; export PATH="${jdir}/bin:${PATH}"
        ok "Reusing bundled JRE 17."
        return 0
    fi
    log "Installing Temurin JRE 17 (${ENGINE} requirement)..."
    local jarch="x64"; [ "${ARCH_TYPE}" = "arm64" ] && jarch="aarch64"
    mkdir -p "${jdir}"
    local tmp_tar; tmp_tar=$(mktemp)
    if fetch "https://api.adoptium.net/v3/binary/latest/17/ga/linux/${jarch}/jre/hotspot/normal/eclipse?project=jdk" "${tmp_tar}" \
       && tar -xzf "${tmp_tar}" -C "${jdir}" --strip-components=1 2>/dev/null; then
        rm -f "${tmp_tar}"
        export JAVA_HOME="${jdir}"; export PATH="${jdir}/bin:${PATH}"
        ok "JRE 17 installed."
        return 0
    fi
    rm -f "${tmp_tar}"
    warn "Automatic JRE installation failed; ${ENGINE} may require manual Java 17+."
    return 1
}

stamp_dir="${INSTALL_DIR}/.versions"
stamp_ok()      { printf '%s|%s|%s' "${RESOLVED:-${VERSION}}" "${ARCH_TYPE}" "$(date -u +%s)" > "${stamp_dir}/${ENGINE}" 2>/dev/null || true; }
stamp_matches() { [ -f "${stamp_dir}/${ENGINE}" ] && grep -q "^${RESOLVED:-${VERSION}}|" "${stamp_dir}/${ENGINE}" 2>/dev/null; }

mark_engine_ready() {
    # Successful provisioning clears any prior system-fallback substitution
    rm -f "${stamp_dir}/${ENGINE}-system-fallback" 2>/dev/null || true
    stamp_ok
    ok "Engine '${ENGINE}' ${RESOLVED} ready (${INSTALL_DIR})"
}

# Lightweight mode: strip docs/tests/benchmarks/static archives after extraction
# (saves 30-60% disk per engine without affecting runtime binaries)
prune_extracted() {
    local root="${1:-}"
    [ -z "${root}" ] || [ ! -d "${root}" ] && return 0
    local p
    for p in \
        mysql-test sql-bench share/doc man docs benchmark \
        lib/*.a lib64/*.a \
        modules/x-pack/sql/driver; do
        rm -rf "${root:?}"/"${p}" 2>/dev/null || true
    done
    find "${root}" -name '*.a' -type f -delete 2>/dev/null || true
    find "${root}" -name '*.pdb' -type f -delete 2>/dev/null || true
    return 0
}

system_version_satisfies() { # system_version_satisfies <binary> <wanted_major>
    local bin="$1" want="$2"
    [ -n "${want}" ] || return 1
    command -v "${bin}" >/dev/null 2>&1 || return 1
    local got
    got="$("${bin}" --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+){0,2}' | head -n1)"
    [ -n "${got}" ] || return 1
    [ "${got%%.*}" = "${want%%.*}" ]
}

# -----------------------------------------------------------------------------
# Version Resolution: 'latest' | major ('18') | series ('8.4') | full ('8.4.5') | URL
# -----------------------------------------------------------------------------
resolve_version() {
    validate_version_input
    case "${VERSION}" in https://*|http://*) RESOLVED="${VERSION}"; return 0 ;; esac
    local req="${VERSION:-latest}"
    req=$(echo "${req}" | tr '[:upper:]' '[:lower:]')

    # Release channels: stable == latest stable; beta/alpha/nightly resolve to
    # the newest prerelease when available, else fall back to stable.
    if [ "${req}" = "beta" ] || [ "${req}" = "alpha" ] || [ "${req}" = "nightly" ] || [ "${req}" = "edge" ] || [ "${req}" = "dev" ]; then
        local pre_tag=""
        case "${ENGINE}" in
            postgresql)                pre_tag=$(gh_latest_tag "theseus-rs/postgresql-binaries" 1) ;;
            pocketbase)                pre_tag=$(gh_latest_tag "pocketbase/pocketbase" 1); v=${pre_tag#v} ;;
            surrealdb|surreal)         pre_tag=$(gh_latest_tag "surrealdb/surrealdb" 1) ;;
            meilisearch)               pre_tag=$(gh_latest_tag "getmeili/meilisearch" 1) ;;
            qdrant)                    pre_tag=$(gh_latest_tag "qdrant/qdrant" 1) ;;
            typesense)                 pre_tag=$(gh_latest_tag "typesense/typesense" 1); v=${pre_tag#v} ;;
            ferretdb)                  pre_tag=$(gh_latest_tag "FerretDB/FerretDB" 1); v=${pre_tag#v} ;;
            dragonfly)                 pre_tag=$(gh_latest_tag "dragonflydb/dragonfly" 1); v=${pre_tag#v} ;;
            valkey)                    pre_tag=$(gh_latest_tag "valkey-io/valkey" 1); v=${pre_tag#v} ;;
        esac
        # Normalize to bare version where handlers expect it
        if [ -n "${pre_tag}" ]; then
            case "${ENGINE}" in
                pocketbase|typesense|ferretdb|dragonfly|valkey) RESOLVED="${v:-${pre_tag#v}}" ;;
                *) RESOLVED="${pre_tag#v}" ;;
            esac
            log "'${req}' channel resolved for ${ENGINE} -> ${RESOLVED}"
            return 0
        fi
        warn "No '${req}' prerelease published for ${ENGINE}; falling back to stable."
        req="latest"
    fi

    if [ "${req}" = "stable" ]; then
        req="latest"
    fi

    if [ "${req}" = "latest" ] || [ "${req}" = "default" ]; then
        local v=""
        case "${ENGINE}" in
            postgresql)                v=$(eofl_resolve "postgresql" "") ;;
            mariadb)                   v=$(eofl_resolve "mariadb" "") ;;
            mysql)                     v=$(eofl_resolve "mysql" "") ;;
            mongodb)                   v=$(eofl_resolve "mongodb" "") ;;
            redis)                     v=$(eofl_resolve "redis" "") ;;
            valkey)                    v=$(eofl_resolve "valkey" "") ;;
            memcached)                 v=$(eofl_resolve "memcached" "") ;;
            dragonfly)                 v=$(gh_latest_tag "dragonflydb/dragonfly"); v=${v#v} ;;
            keydb)                     v=$(gh_latest_tag "EQ-Alpha/KeyDB"); v=${v#v} ;;
            ferretdb)                  v=$(gh_latest_tag "FerretDB/FerretDB"); v=${v#v} ;;
            cockroachdb|cockroach)     v=$(eofl_resolve "cockroachdb" "") ;;
            yugabytedb|yugabyte)       v=$(gh_latest_tag "yugabyte/yugabyte-db"); v=${v#v} ;;
            tidb)                      v=$(eofl_resolve "tidb" ""); [ -z "${v}" ] && { v=$(gh_latest_tag "pingcap/tidb"); v=${v#v}; } ;;
            dolt)                      v=$(gh_latest_tag "dolthub/dolt"); v=${v#v} ;;
            etcd)                      v=$(gh_latest_tag "etcd-io/etcd"); v=${v#v} ;;
            nats)                      v=$(gh_latest_tag "nats-io/nats-server"); v=${v#v} ;;
            immudb)                    v=$(gh_latest_tag "codenotary/immudb"); v=${v#v} ;;
            aerospike)                 v=$(eofl_resolve "aerospike" "") ;;
            cassandra)                 v=$(eofl_resolve "cassandra" "") ;;
            arangodb)                  v=$(gh_latest_tag "arangodb/arangodb"); v=${v#v} ;;
            orientdb)                  v=$(gh_latest_tag "orientechnologies/orientdb"); v=${v#v} ;;
            ravendb)                   v=$(gh_latest_tag "ravendb/ravendb"); v=${v#v} ;;
            dgraph)                    v=$(gh_latest_tag "dgraph-io/dgraph"); v=${v#v} ;;
            neo4j)                     v=$(eofl_resolve "neo4j" "") ;;
            couchdb)                   v=$(eofl_resolve "couchdb" "") ;;
            influxdb)                  v=$(eofl_resolve "influxdb" "") ;;
            clickhouse)                v=$(eofl_resolve "clickhouse" "") ;;
            victoriametrics)           v=$(gh_latest_tag "VictoriaMetrics/VictoriaMetrics"); v=${v#v} ;;
            elasticsearch)             v=$(eofl_resolve "elasticsearch" "") ;;
            opensearch)                v=$(eofl_resolve "opensearch" "") ;;
            solr)                      v=$(eofl_resolve "solr" "") ;;
            manticoresearch|manticore) v=$(gh_latest_tag "manticoresoftware/manticoresearch"); v=${v#v} ;;
            milvus)                    v=$(gh_latest_tag "milvus-io/milvus"); v=${v#v} ;;
            weaviate)                  v=$(gh_latest_tag "weaviate-io/weaviate"); v=${v#v} ;;
            quickwit)                  v=$(gh_latest_tag "quickwit-oss/quickwit"); v=${v#v} ;;
            questdb)                   v=$(gh_latest_tag "questdb/questdb"); v=${v#v} ;;
            seaweedfs|weed)            v=$(gh_latest_tag "seaweedfs/seaweedfs"); v=${v#v} ;;
            garage)                    v=$(gh_latest_tag "dxflrs/garage"); v=${v#v} ;;
            libsql|sqld)               v=$(gh_latest_tag "tursodatabase/libsql"); v=${v#v} ;;
            surrealdb)                 v=$(gh_latest_tag "surrealdb/surrealdb") ;;
            pocketbase)                v=$(gh_latest_tag "pocketbase/pocketbase"); v=${v#v} ;;
            meilisearch)               v=$(gh_latest_tag "getmeili/meilisearch") ;;
            qdrant)                    v=$(gh_latest_tag "qdrant/qdrant") ;;
            typesense)                 v=$(gh_latest_tag "typesense/typesense"); v=${v#v} ;;
            rethinkdb)                 v=$(gh_latest_tag "rethinkdb/rethinkdb"); v=${v#v} ;;
        esac
        if [ -n "${v}" ]; then
            RESOLVED="${v}"
            log "'latest' resolved for ${ENGINE} -> ${RESOLVED}"
        else
            RESOLVED="latest"
            warn "Upstream version lookup failed for '${ENGINE}'; using best-available strategy."
        fi
        return 0
    fi

    # Series/major expansion via endoflife.date (newest patch of that cycle)
    if [[ "${req}" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        local product="" v=""
        case "${ENGINE}" in
            postgresql) product="postgresql" ;; mariadb) product="mariadb" ;;
            mysql) product="mysql" ;;         mongodb) product="mongodb" ;;
            redis) product="redis" ;;         valkey) product="valkey" ;;
            memcached) product="memcached" ;; cassandra) product="cassandra" ;;
            clickhouse) product="clickhouse" ;; cockroachdb|cockroach) product="cockroachdb" ;;
            neo4j) product="neo4j" ;;         influxdb) product="influxdb" ;;
            elasticsearch) product="elasticsearch" ;; opensearch) product="opensearch" ;;
            solr) product="solr" ;;           couchdb) product="couchdb" ;;
            tidb) product="tidb" ;;           aerospike) product="aerospike" ;;
        esac
        if [ -n "${product}" ]; then
            v=$(eofl_resolve "${product}" "${req}")
            if [ -n "${v}" ]; then
                RESOLVED="${v}"
                log "Series '${req}' -> newest patch ${RESOLVED}"
                return 0
            fi
        fi
    fi

    RESOLVED="${req}"
    return 0
}
resolve_version

if [ "${PF_INSTALLER_DEBUG:-0}" = "1" ]; then
    set -x
fi

if [ "${SKIP_VERSION_INSTALL:-0}" = "1" ]; then
    warn "SKIP_VERSION_INSTALL=1 detected. Using container-provided binaries only."
    stamp_ok
    exit 0
fi

# -----------------------------------------------------------------------------
# Custom URL passthrough
# -----------------------------------------------------------------------------
if [[ "${RESOLVED}" =~ ^https?:// ]] || [[ -n "${CUSTOM_DOWNLOAD_URL:-}" && "${ENGINE}" = "custom" ]]; then
    DL_URL="${CUSTOM_DOWNLOAD_URL:-${RESOLVED}}"
    log "Downloading custom binary/package: ${DL_URL}"
    filename=$(basename "${DL_URL}" | sed 's/[?].*//')
    tmp_dl=$(mktemp)
    if fetch "${DL_URL}" "${tmp_dl}"; then
        case "${filename}" in
            *.tar.gz|*.tgz) tar -xzf "${tmp_dl}" -C "${INSTALL_DIR}/" ;;
            *.tar.xz)       tar -xJf "${tmp_dl}" -C "${INSTALL_DIR}/" ;;
            *.tar.bz2)      tar -xjf "${tmp_dl}" -C "${INSTALL_DIR}/" ;;
            *.zip)          unzip -q -o "${tmp_dl}" -d "${INSTALL_DIR}/" ;;
            *) cp -f "${tmp_dl}" "${INSTALL_DIR}/${CUSTOM_BINARY_NAME:-${filename}}" ;;
        esac
        rm -f "${tmp_dl}"
        find "${INSTALL_DIR}" -maxdepth 2 -type f -exec chmod +x {} + 2>/dev/null || true
        ok "Custom binary installed into ${INSTALL_DIR}"
    else
        warn "Download failed: ${DL_URL}"
    fi
    exit 0
fi

# -----------------------------------------------------------------------------
# PostgreSQL 13-18+: standalone gnu builds (theseus-rs) + PGDG apt fallback
# -----------------------------------------------------------------------------
install_postgresql() {
    local want_major=""
    [ "${RESOLVED}" != "latest" ] && want_major="${RESOLVED%%.*}"

    if [ -n "${want_major}" ] && [ -x "/usr/lib/postgresql/${want_major}/bin/postgres" ]; then
        log "PostgreSQL ${want_major} present in system paths."
        echo "/usr/lib/postgresql/${want_major}/bin" > "${INSTALL_DIR}/.versions/postgresql-path"
        return 0
    fi

    local tag=""
    tag=$(gh_latest_tag "theseus-rs/postgresql-binaries")
    if [ -n "${want_major}" ]; then
        if [ -z "${tag}" ] || ! [[ "${tag}" =~ ^${want_major}\. ]]; then
            tag=$(fetch "https://api.github.com/repos/theseus-rs/postgresql-binaries/releases?per_page=60" - | \
                  jq -r --arg m "${want_major}" '[.[].tag_name | select(startswith($m ++ "."))][0] // empty' 2>/dev/null)
        fi
    fi
    [ -z "${tag}" ] && fail "No PostgreSQL build located matching '${RESOLVED}'. Valid majors: 13-18."

    local dest="${INSTALL_DIR}/pg-${tag%%.*}"
    if [ -x "${dest}/bin/postgres" ] && "${dest}/bin/postgres" --version 2>/dev/null | grep -qE " ${tag%%.*}[. ]"; then
        log "Standalone PostgreSQL ${tag%%.*}.x already installed."
        return 0
    fi

    disk_preflight_mb 400
    log "Installing standalone PostgreSQL ${tag}..."
    # Match libc family (musl hosts get musl builds); cross-fallback probe
    local pg_target="${ARCH_GNU}"
    if [ "${PF_LIBC:-gnu}" = "musl" ] && [ -n "${ARCH_MUSL:-}" ]; then
        pg_target="${ARCH_MUSL}"
    fi
    local url="https://github.com/theseus-rs/postgresql-binaries/releases/download/${tag}/postgresql-${tag}-${pg_target}.tar.gz"
    if ! probe_url "${url}"; then
        if [ "${pg_target}" = "${ARCH_GNU}" ] && [ -n "${ARCH_MUSL:-}" ]; then
            pg_target="${ARCH_MUSL}"
        else
            pg_target="${ARCH_GNU}"
        fi
        url="https://github.com/theseus-rs/postgresql-binaries/releases/download/${tag}/postgresql-${tag}-${pg_target}.tar.gz"
        probe_url "${url}" || no_arch_build_fallback
    fi
    local tmp_tar; tmp_tar=$(mktemp)
    if ! fetch "${url}" "${tmp_tar}"; then
        rm -f "${tmp_tar}"
        # Opt-in root fallback only (default: fully isolated container installs)
        if [ "${ALLOW_SYSTEM_APT:-0}" = "1" ] && [ "${IS_ROOT}" = "1" ] && have apt-get && [ -n "${want_major}" ]; then
            log "Falling back to PGDG apt repository (PostgreSQL ${want_major})..."
            apt-get install -y -qq curl ca-certificates gnupg lsb-release 2>/dev/null || true
            local coden
            coden=$(. /etc/os-release 2>/dev/null; printf '%s' "${VERSION_CODENAME:-jammy}")
            fetch "https://www.postgresql.org/media/keys/ACCC4CF8.asc" - | gpg --dearmor > /usr/share/keyrings/pgdg.gpg 2>/dev/null || true
            printf 'deb [signed-by=/usr/share/keyrings/pgdg.gpg] http://apt.postgresql.org/pub/repos/apt %s-pgdg main\n' "${coden}" > /etc/apt/sources.list.d/pgdg.list 2>/dev/null || true
            apt-get update -qq 2>/dev/null || true
            apt-get install -y -qq "postgresql-${want_major}" "postgresql-client-${want_major}" 2>/dev/null && return 0
        fi
        fail "PostgreSQL ${RESOLVED} installation failed (download + fallback exhausted)."
    fi
    verify_checksum "${tmp_tar}" "${url}.sha256" || { rm -f "${tmp_tar}"; fail "Checksum mismatch for PostgreSQL archive."; }
    mkdir -p "${dest}"
    tar -xzf "${tmp_tar}" -C "${dest}" --strip-components=1 2>/dev/null || tar -xzf "${tmp_tar}" -C "${dest}"
    rm -f "${tmp_tar}"
    chmod +x "${dest}/bin/"* 2>/dev/null || true
    bundle_pg_runtime_libs "${dest}/lib-extra"
    if [ -e "${dest}/lib-extra/libxml2.so.2" ]; then
        export LD_LIBRARY_PATH="${dest}/lib-extra:${LD_LIBRARY_PATH:-}"
        log "Bundled PostgreSQL runtime libraries (libxml2/icu)."
    fi
    LD_LIBRARY_PATH="${dest}/lib-extra:${LD_LIBRARY_PATH:-}" \
        "${dest}/bin/postgres" --version >/dev/null 2>&1 || fail "Installed PostgreSQL binary failed self-check."
    return 0
}

# -----------------------------------------------------------------------------
# MariaDB: official bintar builds (archive.mariadb.org)
# -----------------------------------------------------------------------------
install_mariadb() {
    local base="${SERVER_DIR:-$(pwd)}/opt/mariadb"
    [ -x "${base}/bin/mariadbd" ] && { log "MariaDB ${RESOLVED} already installed."; return 0; }

    # Official bintars link glibc: musl hosts (Alpine) use the system engine
    if [ "${PF_LIBC:-gnu}" = "musl" ]; then
        no_arch_build_fallback
    fi

    # Lightweight path: system binary already provides the requested series
    if system_version_satisfies mariadbd "${RESOLVED}"; then
        log "System mariadbd matches requested series (${RESOLVED}); skipping download."
        return 0
    fi

    if ! [[ "${RESOLVED}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        err "MariaDB requires a concrete x.y.z version (resolver produced '${RESOLVED}')."
        err "Set DB_VERSION to e.g. 11.4, 11.8, latest, or a full x.y.z."
        return 1
    fi

    local candidates=("$(printf '%s' "${RESOLVED}")")
    local series="${RESOLVED%.*}" p cand
    for p in 6 5 4 3 2 1 0; do
        cand="${series}.${p}"
        [ "${cand}" != "${RESOLVED}" ] && candidates+=("${cand}")
    done

    local ad="bintar-linux-systemd-x86_64"
    [ "${ARCH_TYPE}" = "arm64" ] && ad="bintar-linux-systemd-aarch64"

    local urls=() v
    for v in "${candidates[@]}"; do
        urls+=("https://archive.mariadb.org/mariadb-${v}/${ad}/mariadb-${v}-linux-systemd-${ARCH_ALT}.tar.gz")
    done

    disk_preflight_mb 1600
    log "Probing MariaDB builds (HEAD + direct-download fallback)..."
    local tmp_tar; tmp_tar=$(mktemp)
    local hit
    hit=$(try_fetch_candidates "${tmp_tar}" "${urls[@]}") \
        || { rm -f "${tmp_tar}"; fail "No downloadable MariaDB build found near '${RESOLVED}' for ${ARCH_TYPE}."; }
    RESOLVED="$(basename "${hit}" | sed -E 's/mariadb-([0-9.]+)-.*/\1/')"
    log "Downloading MariaDB ${RESOLVED} bintar succeeded."
    mkdir -p "${base}"
    tar -xzf "${tmp_tar}" -C "${base}" --strip-components=1 || { rm -f "${tmp_tar}"; fail "Extraction failed."; }
    rm -f "${tmp_tar}"
    chmod +x "${base}/bin/"* 2>/dev/null || true
    extract_libaio "${base}/lib-extra"
    prune_extracted "${base}"
    return 0
}

# -----------------------------------------------------------------------------
# MySQL: official minimal generic tarballs (cdn.mysql.com)
# -----------------------------------------------------------------------------
install_mysql() {
    local base="${SERVER_DIR:-$(pwd)}/opt/mysql"
    [ -x "${base}/bin/mysqld" ] && { log "MySQL ${RESOLVED} already installed."; return 0; }

    # Official generic builds link glibc: musl hosts (Alpine) use system engine
    if [ "${PF_LIBC:-gnu}" = "musl" ]; then
        no_arch_build_fallback
    fi

    # Lightweight path: system binary already provides the requested series
    if system_version_satisfies mysqld "${RESOLVED}"; then
        log "System mysqld matches requested series (${RESOLVED}); skipping download."
        return 0
    fi

    local series="${RESOLVED%.*}"
    [[ "${series}" =~ ^[0-9]+$ ]] && series="${series}.0"
    [[ "${series}" =~ ^[0-9]+\.[0-9]+$ ]] || { err "MySQL version '${RESOLVED}' unclear."; return 1; }
    local dir="MySQL-${series%%.*}"

    local patterns
    if [ "${ARCH_TYPE}" = "arm64" ]; then
        patterns=("linux-glibc2.28-aarch64-minimal" "linux-glibc2.17-aarch64-minimal")
    else
        patterns=("linux-glibc2.28-x86_64-minimal" "linux-glibc2.17-x86_64-minimal")
    fi

    local candidates=()
    if [[ "${RESOLVED}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        candidates+=("${RESOLVED}")
    else
        local patches p
        case "${series}" in
            8.0) patches=(46 45 44 43 42 41 40 39 37 36 35) ;;
            8.4) patches=(11 10 9 8 7 6 5 4 3 2 1) ;;
            *)   patches=(9 7 5 3 1 0) ;;
        esac
        for p in "${patches[@]}"; do candidates+=("${series}.${p}"); done
    fi

    local urls=() v pat
    for v in "${candidates[@]}"; do
        for pat in "${patterns[@]}"; do
            urls+=("https://cdn.mysql.com/Downloads/${dir}/mysql-${v}-${pat}.tar.xz")
        done
    done

    disk_preflight_mb 1200
    log "Probing MySQL builds (HEAD + direct-download fallback for CDN HEAD-blocking)..."
    local tmp_tar; tmp_tar=$(mktemp)
    local hit
    if ! hit=$(try_fetch_candidates "${tmp_tar}" "${urls[@]}"); then
        rm -f "${tmp_tar}"
        # Oracle's CDN (Akamai) hard-blocks some datacenter/CI egress ranges.
        # Opt-in escape hatch: serve the container-provided MySQL-compatible
        # daemon instead, loudly. Never silent; contract resumes when the CDN
        # is reachable again.
        if [ "${CDN_FALLBACK_SYSTEM:-0}" = "1" ] && { command -v mysqld >/dev/null 2>&1 || command -v mariadbd >/dev/null 2>&1; }; then
            warn "cdn.mysql.com is unreachable from this network (blocked egress range)."
            warn "CDN_FALLBACK_SYSTEM=1: serving the container-provided MySQL-compatible daemon for series '${series}'."
            warn "This is a SUBSTITUTION, not a match. Remove CDN_FALLBACK_SYSTEM or fix egress for exact-version service."
            export MYSQL_CDN_FALLBACK=1
            # Subprocess boundary: launcher reads the marker file, not this env
            printf '%s\n' "${RESOLVED}" > "${stamp_dir}/mysql-cdn-fallback" 2>/dev/null || true
            RESOLVED="${RESOLVED}-cdn-unreachable"
            return 0
        fi
        fail "No downloadable MySQL minimal build located for series '${series}' on ${ARCH_TYPE}."
    fi
    RESOLVED="$(basename "${hit}" | sed -E 's/mysql-([0-9.]+)-linux.*/\1/')"
    log "Downloading MySQL ${RESOLVED} minimal tarball succeeded."
    mkdir -p "${base}"
    tar -xJf "${tmp_tar}" -C "${base}" --strip-components=1 || { rm -f "${tmp_tar}"; fail "Extraction failed."; }
    rm -f "${tmp_tar}"
    chmod +x "${base}/bin/"* 2>/dev/null || true
    extract_libaio "${base}/lib-extra"
    prune_extracted "${base}"
    return 0
}

bundle_deb_libs() { # bundle_deb_libs <dest_dir> <deb_url...>  (extract shared libs beside engines)
    local dest="$1"; shift
    mkdir -p "${dest}"
    local u tmp_deb
    for u in "$@"; do
        probe_url "${u}" || continue
        tmp_deb=$(mktemp)
        if fetch "${u}" "${tmp_deb}" && dpkg-deb -x "${tmp_deb}" "${dest}/.bx" 2>/dev/null; then
            find "${dest}/.bx" -name '*.so*' -exec cp -a {} "${dest}/" \; 2>/dev/null || true
        fi
        rm -rf "${dest}/.bx" "${tmp_deb}"
    done
    find "${dest}" -maxdepth 1 -name '*.so*' ! -name '*-*' -exec chmod 644 {} + 2>/dev/null || true
    return 0
}

# Bundle runtime libs required by theseus-rs PostgreSQL gnu builds on jammy
bundle_pg_runtime_libs() {
    local dest="$1"
    # libxml2 + icu: required by the postgres binary itself
    if [ ! -e "${dest}/libxml2.so.2" ]; then
        local arch="${ARCH_DEB}"
        local pools=(
            "https://archive.ubuntu.com/ubuntu/pool/main/libx/libxml2"
            "http://security.ubuntu.com/ubuntu/pool/main/libx/libxml2"
        )
        local p
        for p in "${pools[@]}"; do
            bundle_deb_libs "${dest}" \
                "${p}/libxml2_2.9.13+dfsg-1ubuntu0.12_${arch}.deb" \
                "${p}/libxml2_2.9.13+dfsg-1build1_${arch}.deb"
            [ -e "${dest}/libxml2.so.2" ] && break
        done
        bundle_deb_libs "${dest}" \
            "https://archive.ubuntu.com/ubuntu/pool/main/i/icu/libicu70_70.1-2_${arch}.deb"
    fi
    # libossp-uuid.so.16: required by the uuid-ossp contrib extension
    if [ ! -e "${dest}/libossp-uuid.so.16" ]; then
        bundle_deb_libs "${dest}" \
            "https://archive.ubuntu.com/ubuntu/pool/universe/o/ossp-uuid/libossp-uuid16_1.6.2-1.5build9_${ARCH_DEB}.deb" \
            "https://archive.ubuntu.com/ubuntu/pool/universe/o/ossp-uuid/libossp-uuid16_1.6.6-1build1_${ARCH_DEB}.deb"
        [ -e "${dest}/libossp-uuid.so.16" ] && ok "Bundled libossp-uuid (uuid-ossp extension ready)."
    fi
    return 0
}

# -----------------------------------------------------------------------------
# MongoDB (+ mongosh companion for first-run provisioning)
# -----------------------------------------------------------------------------
ensure_mongosh() {
    have mongosh && return 0
    [ -x "${INSTALL_DIR}/mongosh" ] && return 0
    log "Fetching mongosh companion (provisioning shell)..."
    local url="https://downloads.mongodb.com/compass/mongosh-2.3.8-linux-${ARCH_ALT}.tgz"
    local tmp_tar; tmp_tar=$(mktemp)
    if fetch "${url}" "${tmp_tar}"; then
        local ext="${INSTALL_DIR}/.msh.$$"
        mkdir -p "${ext}"
        tar -xzf "${tmp_tar}" -C "${ext}" 2>/dev/null || true
        find "${ext}" -type f -name mongosh -exec cp -f {} "${INSTALL_DIR}/mongosh" \; 2>/dev/null || true
        rm -rf "${ext}" "${tmp_tar}"
        chmod +x "${INSTALL_DIR}/mongosh" 2>/dev/null || true
        ok "mongosh companion ready."
    else
        rm -f "${tmp_tar}"
        warn "mongosh download failed; provisioning will be skipped this boot."
    fi
    return 0
}

install_mongodb() {
    [ -x "${INSTALL_DIR}/mongod" ] && { log "MongoDB already present."; ensure_mongosh; return 0; }

    # Lightweight path: system binary already provides the requested series
    if [ -n "${RESOLVED}" ] && system_version_satisfies mongod "${RESOLVED}"; then
        log "System MongoDB matches requested series (${RESOLVED}); skipping download."
        ensure_mongosh
        return 0
    fi

    local distros=("ubuntu2204" "ubuntu2404")
    if grep -q 'VERSION_ID="24' /etc/os-release 2>/dev/null; then distros=("ubuntu2404" "ubuntu2204"); fi

    local candidates=()
    if [[ "${RESOLVED}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        candidates+=("${RESOLVED}")
    elif [[ "${RESOLVED}" =~ ^[0-9]+\.[0-9]+$ ]]; then
        local patches p
        case "${RESOLVED}" in
            8.0) patches=(12 10 9 8 7 6 5 4 3 2 1 0) ;;
            7.0) patches=(14 12 11 10 9 8 5 3 2 0) ;;
            6.0) patches=(16 14 13 12 11 10 8 7 5 4 3 2 0) ;;
            *)   patches=(9 7 5 3 1 0) ;;
        esac
        for p in "${patches[@]}"; do candidates+=("${RESOLVED}.${p}"); done
    else
        candidates+=("${RESOLVED}")
    fi

    local urls=() v dt
    for v in "${candidates[@]}"; do
        for dt in "${distros[@]}"; do
            # ARCH_ALT covers x86_64 / aarch64 / s390x exactly as fastdl names them
            urls+=("https://fastdl.mongodb.org/linux/mongodb-linux-${ARCH_ALT}-${dt}-${v}.tgz")
        done
    done

    disk_preflight_mb 700
    log "Probing MongoDB builds (HEAD + direct-download fallback)..."
    local tmp_tar; tmp_tar=$(mktemp)
    local hit
    hit=$(try_fetch_candidates "${tmp_tar}" "${urls[@]}") \
        || { rm -f "${tmp_tar}"; fail "No downloadable MongoDB build found for '${RESOLVED}' on ${ARCH_TYPE}."; }
    RESOLVED="$(basename "${hit}" | sed -E 's/.*-([0-9]+\.[0-9]+\.[0-9]+)\.tgz$/\1/')"
    log "Downloading MongoDB ${RESOLVED} succeeded."
    local ext="${INSTALL_DIR}/.mgx.$$"
    mkdir -p "${ext}"
    tar -xzf "${tmp_tar}" -C "${ext}" --strip-components=1 || { rm -rf "${ext}" "${tmp_tar}"; fail "Extraction failed."; }
    cp -f "${ext}/bin/mongod" "${INSTALL_DIR}/mongod"
    [ -f "${ext}/bin/mongos" ] && cp -f "${ext}/bin/mongos" "${INSTALL_DIR}/mongos"
    rm -rf "${ext}" "${tmp_tar}"
    chmod +x "${INSTALL_DIR}/mongod"
    "${INSTALL_DIR}/mongod" --version >/dev/null 2>&1 || fail "MongoDB binary failed self-check."
    ensure_mongosh
    return 0
}

# -----------------------------------------------------------------------------
# Source builds (Redis-family) + generic GitHub release helper
# -----------------------------------------------------------------------------
build_from_source() {
    local url="$1"; shift
    have make || apt_try_install build-essential || true
    have make || { warn "'make' unavailable (no root?). Cannot compile."; return 1; }
    have cc || have gcc || { warn "No C compiler present. Cannot compile."; return 1; }
    disk_preflight_mb 600
    local tmp_tar; tmp_tar=$(mktemp)
    fetch "${url}" "${tmp_tar}" || { rm -f "${tmp_tar}"; warn "Source fetch failed: ${url}"; return 1; }
    local bd; bd=$(mktemp -d)
    tar -xzf "${tmp_tar}" -C "${bd}" --strip-components=1 || { rm -rf "${bd}" "${tmp_tar}"; return 1; }
    rm -f "${tmp_tar}"
    ( cd "${bd}" && make MALLOC=libc -j"$(nproc 2>/dev/null || echo 2)" ${MAKE_ARGS:-} ) >&2 || { rm -rf "${bd}"; warn "Compile failed."; return 1; }
    local b
    for b in "$@"; do
        [ -f "${bd}/${b}" ] && cp -f "${bd}/${b}" "${INSTALL_DIR}/${b##*/}"
    done
    rm -rf "${bd}"
    find "${INSTALL_DIR}" -maxdepth 1 -type f -exec chmod +x {} + 2>/dev/null || true
    return 0
}

gh_release_install() { # gh_release_install <repo> <asset_regex> <inner_name> <final_name>
    local repo="$1" regex="$2" inner="$3" final="$4"
    [ -x "${INSTALL_DIR}/${final}" ] && { log "${final} already present."; return 0; }
    local asset_url
    asset_url=$(fetch "https://api.github.com/repos/${repo}/releases?per_page=30" - | \
        jq -r --arg re "${regex}" '[.[].assets[].browser_download_url | select(test($re))][0] // empty' 2>/dev/null)
    [ -z "${asset_url}" ] && { warn "No release asset matched '${regex}' for ${repo}."; return 1; }
    log "Fetching $(basename "${asset_url}") ..."
    local tmp_dl; tmp_dl=$(mktemp)
    fetch "${asset_url}" "${tmp_dl}" || { rm -f "${tmp_dl}"; warn "Download failed."; return 1; }
    local fname; fname=$(basename "${asset_url}")
    case "${fname}" in
        *.tar.gz|*.tgz)
            local ext="${INSTALL_DIR}/.ghx.$$"; mkdir -p "${ext}"
            tar -xzf "${tmp_dl}" -C "${ext}" 2>/dev/null || { rm -rf "${ext}" "${tmp_dl}"; warn "Extract failed."; return 1; }
            local found; found=$(find "${ext}" -type f -name "${inner}" | head -n1)
            [ -n "${found}" ] && cp -f "${found}" "${INSTALL_DIR}/${final}"
            rm -rf "${ext}"
            ;;
        *.zip)
            local ext="${INSTALL_DIR}/.ghx.$$"; mkdir -p "${ext}"
            unzip -q -o "${tmp_dl}" -d "${ext}" 2>/dev/null || true
            local found; found=$(find "${ext}" -type f -name "${inner}" | head -n1)
            [ -n "${found}" ] && cp -f "${found}" "${INSTALL_DIR}/${final}"
            rm -rf "${ext}"
            ;;
        *) cp -f "${tmp_dl}" "${INSTALL_DIR}/${final}" ;;
    esac
    rm -f "${tmp_dl}"
    chmod +x "${INSTALL_DIR}/${final}" 2>/dev/null || true
    [ -x "${INSTALL_DIR}/${final}" ] || { warn "Verification failed for ${final}."; return 1; }
    return 0
}

install_redis_family() {
    local sysbin=""
    case "${ENGINE}" in
        redis) sysbin="redis-server" ;;
        valkey) sysbin="valkey-server" ;;
        keydb) sysbin="keydb-server" ;;
        memcached) sysbin="memcached" ;;
        dragonfly) sysbin="" ;;
    esac
    if [ -n "${sysbin}" ] && system_version_satisfies "${sysbin}" "${RESOLVED}"; then
        log "System ${sysbin} matches requested series (${RESOLVED}); skipping source build."
        return 0
    fi
    case "${ENGINE}" in
        redis)
            [ -x "${INSTALL_DIR}/redis-server" ] && return 0
            build_from_source "https://download.redis.io/releases/redis-${RESOLVED}.tar.gz" src/redis-server src/redis-cli \
                || fallback_to_system "Redis ${RESOLVED} cannot be compiled here (no gcc/make, unprivileged)."
            ;;
        valkey)
            [ -x "${INSTALL_DIR}/valkey-server" ] && return 0
            local tag="${RESOLVED}"; [[ "${tag}" != v* ]] && tag="v${tag}"
            build_from_source "https://github.com/valkey-io/valkey/archive/refs/tags/${tag}.tar.gz" src/valkey-server src/valkey-cli \
                || fallback_to_system "Valkey ${RESOLVED} cannot be compiled here (no gcc/make, unprivileged)."
            ;;
        keydb)
            [ -x "${INSTALL_DIR}/keydb-server" ] && return 0
            local tag="${RESOLVED}"; [[ "${tag}" != v* ]] && tag="v${tag}"
            build_from_source "https://github.com/EQ-Alpha/KeyDB/archive/refs/tags/${tag}.tar.gz" keydb-server keydb-cli \
                || fallback_to_system "KeyDB ${RESOLVED} cannot be compiled here."
            ;;
        memcached)
            [ -x "${INSTALL_DIR}/memcached" ] && return 0
            apt_try_install libevent-dev || true
            ldconfig 2>/dev/null || true
            build_from_source "https://memcached.org/files/memcached-${RESOLVED}.tar.gz" memcached \
                || fallback_to_system "memcached ${RESOLVED} cannot be compiled here (libevent-dev missing)."
            ;;
        dragonfly)
            [ -x "${INSTALL_DIR}/dragonfly" ] && return 0
            local tag="${RESOLVED}"; [[ "${tag}" != v* ]] && tag="v${tag}"
            local asset="dragonfly-x86_64.tar.gz"
            [ "${ARCH_TYPE}" = "arm64" ] && asset="dragonfly-aarch64.tar.gz"
            gh_release_install "dragonflydb/dragonfly" "${tag}/${asset//./\\.}" dragonfly dragonfly \
                || warn "Dragonfly ${tag} download failed."
            ;;
    esac
    return 0
}

# -----------------------------------------------------------------------------
# Engine dispatch
# -----------------------------------------------------------------------------
# Architecture capability gate: binary-publishing engines get a fast, honest
# fallback on architectures upstream does not ship (source-built, Java-based,
# tarball and deb-extracted engines always attempt below).
case "${ENGINE}" in
    postgresql|mariadb|mysql|mongodb|meilisearch|qdrant|pocketbase|typesense|\
minio|dragonfly|ferretdb|victoriametrics|cockroachdb|cockroach|tidb|dolt|\
clickhouse|influxdb)
        engine_supports_arch "${ENGINE}" || no_arch_build_fallback
        ;;
esac

case "${ENGINE}" in
    pocketbase)
        TAG="${RESOLVED#v}"; [ -z "${TAG}" -o "${TAG}" = "latest" ] && TAG=$(gh_latest_tag "pocketbase/pocketbase" | sed 's/^v//')
        [ -z "${TAG}" ] && TAG="0.25.0"
        if [ ! -x "${INSTALL_DIR}/pocketbase" ]; then
            URL="https://github.com/pocketbase/pocketbase/releases/download/v${TAG}/pocketbase_${TAG}_linux_${ARCH_TYPE}.zip"
            tmp_zip=$(mktemp)
            if fetch "${URL}" "${tmp_zip}"; then
                unzip -q -o "${tmp_zip}" -d "${INSTALL_DIR}/"
                seal_binary "${INSTALL_DIR}/pocketbase"
                ok "PocketBase v${TAG} installed."
            else rm -f "${INSTALL_DIR}/pocketbase"; warn "PocketBase v${TAG} download failed; baked binary (if any) will serve."; fi
            rm -f "${tmp_zip}"
        fi
        ;;

    surrealdb|surreal)
        TAG="${RESOLVED}"
        { [ -z "${TAG}" ] || [ "${TAG}" = "latest" ]; } && TAG=$(gh_latest_tag "surrealdb/surrealdb")
        [ -z "${TAG}" ] && TAG="v2.0.4"
        [[ "${TAG}" != v* ]] && TAG="v${TAG}"
        if [ ! -x "${INSTALL_DIR}/surreal" ]; then
            URL="https://github.com/surrealdb/surrealdb/releases/download/${TAG}/surreal-${TAG}.${ARCH_GNU}.tar.gz"
            if fetch "${URL}" - 2>/dev/null | tar -xz -C "${INSTALL_DIR}/"; then
                chmod +x "${INSTALL_DIR}/surreal"
                ok "SurrealDB ${TAG} installed."
            else
                warn "Tarball fetch failed; trying official installer..."
                curl -fsSL https://install.surrealdb.com 2>/dev/null | sh >&2 || true
                for src in /root/.surrealdb/surreal "${HOME}/.surrealdb/surreal" /usr/local/bin/surreal; do
                    [ -f "${src}" ] && cp -f "${src}" "${INSTALL_DIR}/surreal" && break
                done
                chmod +x "${INSTALL_DIR}/surreal" 2>/dev/null || true
            fi
        fi
        ;;

    meilisearch)
        # Repo canonicalized to meilisearch/meilisearch; assets renamed to
        # linux-amd64/linux-aarch64/linux-riscv64 (ARCH_TYPE matches exactly).
        TAG="${RESOLVED}"
        { [ -z "${TAG}" ] || [ "${TAG}" = "latest" ]; } && TAG=$(gh_latest_tag "meilisearch/meilisearch")
        [ -z "${TAG}" ] && TAG="v1.53.1"
        [[ "${TAG}" != v* ]] && TAG="v${TAG}"
        if [ ! -x "${INSTALL_DIR}/meilisearch" ]; then
            URL="https://github.com/meilisearch/meilisearch/releases/download/${TAG}/meilisearch-linux-${ARCH_TYPE}"
            probe_url "${URL}" || URL="https://github.com/getmeili/meilisearch/releases/download/${TAG}/meilisearch-linux-${ARCH_ALT}"
            if fetch "${URL}" "${INSTALL_DIR}/meilisearch"; then
                seal_binary "${INSTALL_DIR}/meilisearch" \
                    || { rm -f "${INSTALL_DIR}/meilisearch"; warn "Meilisearch seal failed."; }
                ok "Meilisearch ${TAG} installed."
            else
                rm -f "${INSTALL_DIR}/meilisearch"
                warn "Meilisearch ${TAG} download failed; container-baked binary (if any) will serve."
            fi
        fi
        ;;

    qdrant)
        TAG="${RESOLVED}"
        { [ -z "${TAG}" ] || [ "${TAG}" = "latest" ]; } && TAG=$(gh_latest_tag "qdrant/qdrant")
        [ -z "${TAG}" ] && TAG="v1.12.1"
        [[ "${TAG}" != v* ]] && TAG="v${TAG}"
        if [ ! -x "${INSTALL_DIR}/qdrant" ]; then
            # Prefer STATIC musl builds: immune to host glibc age (recent qdrant
            # gnu builds require GLIBC 2.38+, older bases ship 2.35).
            local q_musl="x86_64-unknown-linux-musl"
            [ -n "${ARCH_MUSL:-}" ] && q_musl="${ARCH_MUSL}"
            local urls=(
                "https://github.com/qdrant/qdrant/releases/download/${TAG}/qdrant-${q_musl}.tar.gz"
                "https://github.com/qdrant/qdrant/releases/download/${TAG}/qdrant-${ARCH_ALT}-unknown-linux-gnu.tar.gz"
            )
            local installed=0 u
            for u in "${urls[@]}"; do
                probe_url "${u}" || continue
                if fetch "${u}" - 2>/dev/null | tar -xz -C "${INSTALL_DIR}/"; then
                    if seal_binary "${INSTALL_DIR}/qdrant" \
                       && "${INSTALL_DIR}/qdrant" --version >/dev/null 2>&1; then
                        installed=1
                        ok "Qdrant ${TAG} installed ($(basename "${u%%.tar.gz}") style)."
                        break
                    fi
                    rm -f "${INSTALL_DIR}/qdrant"
                fi
            done
            [ "${installed}" = "1" ] || warn "Qdrant ${TAG} could not be provisioned compatibly; baked binary (if any) will serve."
        fi
        ;;

    typesense)
        TAG="${RESOLVED#v}"
        { [ -z "${TAG}" ] || [ "${TAG}" = "latest" ]; } && TAG=$(gh_latest_tag "typesense/typesense" | sed 's/^v//')
        [ -z "${TAG}" ] && TAG="27.0"
        if [ ! -x "${INSTALL_DIR}/typesense-server" ]; then
            URL="https://dl.typesense.org/releases/${TAG}/typesense-server-${TAG}-linux-${ARCH_TYPE}.tar.gz"
            if fetch "${URL}" - 2>/dev/null | tar -xz -C "${INSTALL_DIR}/"; then
                seal_binary "${INSTALL_DIR}/typesense-server"
                ok "Typesense v${TAG} installed."
            else rm -f "${INSTALL_DIR}/typesense-server"; warn "Typesense v${TAG} download failed; baked binary (if any) will serve."; fi
        fi
        ;;

    minio)
        if [ ! -x "${INSTALL_DIR}/minio" ]; then
            URL="https://dl.min.io/server/minio/release/linux-${ARCH_TYPE}/minio"
            [ -n "${RESOLVED}" ] && [ "${RESOLVED}" != "latest" ] && URL="https://dl.min.io/server/minio/release/linux-${ARCH_TYPE}/archive/minio.${RESOLVED}"
            if fetch "${URL}" "${INSTALL_DIR}/minio"; then
                seal_binary "${INSTALL_DIR}/minio"
                ok "MinIO ${RESOLVED} installed."
            else rm -f "${INSTALL_DIR}/minio"; warn "MinIO download failed; baked binary (if any) will serve."; fi
        fi
        ;;

    victoriametrics)
        TAG="${RESOLVED}"
        { [ -z "${TAG}" ] || [ "${TAG}" = "latest" ]; } && TAG=$(gh_latest_tag "VictoriaMetrics/VictoriaMetrics")
        [ -z "${TAG}" ] && TAG="v1.108.0"
        [[ "${TAG}" != v* ]] && TAG="v${TAG}"
        if [ ! -x "${INSTALL_DIR}/victoria-metrics-prod" ]; then
            URL="https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/${TAG}/victoria-metrics-linux-${ARCH_TYPE}-${TAG}.tar.gz"
            if fetch "${URL}" - 2>/dev/null | tar -xz -C "${INSTALL_DIR}/"; then
                chmod +x "${INSTALL_DIR}/victoria-metrics-prod" 2>/dev/null || true
                ok "VictoriaMetrics ${TAG} installed."
            else warn "VictoriaMetrics ${TAG} download failed."; fi
        fi
        ;;

    ferretdb)
        TAG="${RESOLVED}"
        { [ -z "${TAG}" ] || [ "${TAG}" = "latest" ]; } && TAG=$(gh_latest_tag "FerretDB/FerretDB")
        [ -z "${TAG}" ] && TAG="v1.21.0"
        [[ "${TAG}" != v* ]] && TAG="v${TAG}"
        if [ ! -x "${INSTALL_DIR}/ferretdb" ]; then
            URL="https://github.com/FerretDB/FerretDB/releases/download/${TAG}/ferretdb-linux-${ARCH_TYPE}.tar.gz"
            if fetch "${URL}" - 2>/dev/null | tar -xz -C "${INSTALL_DIR}/"; then
                chmod +x "${INSTALL_DIR}/ferretdb" 2>/dev/null || true
                ok "FerretDB installed."
            else warn "FerretDB ${TAG} download failed."; fi
        fi
        ;;

    clickhouse)
        if [ ! -x "${INSTALL_DIR}/clickhouse" ]; then
            V="${RESOLVED}"
            ch_arch="amd64"; [ "${ARCH_TYPE}" = "arm64" ] && ch_arch="aarch64"
            if [ -n "${V}" ] && [ "${V}" != "latest" ]; then
                log "Installing ClickHouse ${V} (official tgz)..."
                URL="https://packages.clickhouse.com/tgz/stable/clickhouse-common-static-${V}-${ch_arch}.tgz"
                tmp_tgz=$(mktemp)
                if fetch "${URL}" "${tmp_tgz}"; then
                    ext="${INSTALL_DIR}/.chx.$$"; mkdir -p "${ext}"
                    tar -xzf "${tmp_tgz}" -C "${ext}" 2>/dev/null || true
                    find "${ext}" -type f -name clickhouse -exec cp -f {} "${INSTALL_DIR}/clickhouse" \; 2>/dev/null || true
                    rm -rf "${ext}" "${tmp_tgz}"
                else
                    rm -f "${tmp_tgz}"
                    warn "ClickHouse ${V} tgz failed; trying single-binary installer..."
                    curl -fsSL https://clickhouse.com/ 2>/dev/null | sh >&2 || true
                    [ -f ./clickhouse ] && mv -f ./clickhouse "${INSTALL_DIR}/clickhouse" 2>/dev/null || true
                fi
            else
                log "Installing ClickHouse (latest single binary)..."
                curl -fsSL https://clickhouse.com/ 2>/dev/null | sh >&2 || true
                [ -f ./clickhouse ] && mv -f ./clickhouse "${INSTALL_DIR}/clickhouse" 2>/dev/null || true
            fi
            chmod +x "${INSTALL_DIR}/clickhouse" 2>/dev/null || true
        fi
        ;;

    postgresql) install_postgresql || exit 1 ;;

    mariadb)    install_mariadb    || exit 1 ;;

    mysql)      install_mysql      || exit 1 ;;

    mongodb)    install_mongodb    || exit 1 ;;

    redis|valkey|keydb|memcached|dragonfly) install_redis_family || exit 1 ;;

    # ---------------- Extended catalog (55+ engines) -------------------------
    cockroachdb|cockroach)
        gh_release_install "cockroachdb/cockroach" "linux-${ARCH_ALT}" "cockroach" "cockroach" || warn "CockroachDB download failed."
        ;;

    yugabytedb|yugabyte)
        yb_base="${SERVER_DIR:-$(pwd)}/opt/yugabyte"
        if [ ! -x "${yb_base}/bin/yugabyted" ]; then
            YV="${RESOLVED#v}"
            suffix="linux-x86_64"; [ "${ARCH_TYPE}" = "arm64" ] && suffix="linux-aarch64"
            disk_preflight_mb 3000
            URL="https://software.yugabyte.com/releases/${YV}/yugabyte-${YV}-${suffix}.tar.gz"
            tmp_tar=$(mktemp)
            if fetch "${URL}" "${tmp_tar}"; then
                mkdir -p "${yb_base}"
                tar -xzf "${tmp_tar}" -C "${yb_base}" --strip-components=1
                ok "YugabyteDB ${YV} installed."
            else warn "YugabyteDB download failed."; fi
            rm -f "${tmp_tar}"
        fi
        ;;

    tidb)
        tb_base="${SERVER_DIR:-$(pwd)}/opt/tidb"
        if [ ! -x "${tb_base}/bin/tidb-server" ]; then
            TV="${RESOLVED#v}"
            URL="https://download.pingcap.org/tidb-v${TV}-linux-${ARCH_ALT}.tar.gz"
            tmp_tar=$(mktemp)
            if fetch "${URL}" "${tmp_tar}"; then
                mkdir -p "${tb_base}"
                tar -xzf "${tmp_tar}" -C "${tb_base}" --strip-components=2
                ok "TiDB ${TV} installed."
            else warn "TiDB download failed."; fi
            rm -f "${tmp_tar}"
        fi
        ;;

    dolt)
        gh_release_install "dolthub/dolt" "install/dolt-linux-${ARCH_TYPE}" "dolt" "dolt" || warn "Dolt download failed."
        ;;

    etcd)
        gh_release_install "etcd-io/etcd" "etcd-v.*linux-${ARCH_ALT}" "etcd" "etcd" || warn "etcd download failed."
        gh_release_install "etcd-io/etcd" "etcd-v.*linux-${ARCH_ALT}" "etcdctl" "etcdctl" || true
        ;;

    nats)
        gh_release_install "nats-io/nats-server" "nats-server-v.*linux-${ARCH_ALT}" "nats-server" "nats-server" || warn "NATS download failed."
        ;;

    immudb)
        gh_release_install "codenotary/immudb" "immudb-linux-${ARCH_ALT}" "immudb" "immudb" || warn "immudb download failed."
        ;;

    dgraph)
        gh_release_install "dgraph-io/dgraph" "dgraph.*linux-amd64|linux-amd64.*dgraph" "dgraph" "dgraph" || warn "Dgraph download failed."
        ;;

    aerospike)
        as_base="${SERVER_DIR:-$(pwd)}/opt/aerospike"
        case "${ARCH_TYPE}" in amd64|arm64) : ;; *)
            warn "Aerospike publishes binaries for amd64/arm64 only; skipping on ${ARCH_TYPE}."
            mark_engine_ready; exit 0 ;;
        esac
        if [ ! -x "${as_base}/bin/aerospike" ]; then
            AV="${RESOLVED}"
            downloaded=0
            for art in ubuntu2204 ubuntu2004 el8 tgz; do
                URL="https://www.aerospike.com/download/server/${AV}/artifact/${art}"
                tmp_dl=$(mktemp)
                if fetch "${URL}" "${tmp_dl}" && dpkg-deb -I "${tmp_dl}" >/dev/null 2>&1; then
                    mkdir -p "${as_base}/pkg"
                    dpkg-deb -x "${tmp_dl}" "${as_base}/pkg"
                    find "${as_base}/pkg" -name aerospike -type f -exec cp -f {} "${as_base}/" \; 2>/dev/null || true
                    downloaded=1
                elif [ "${downloaded}" = "0" ] && [ -s "${tmp_dl}" ] && tar -tzf "${tmp_dl}" >/dev/null 2>&1; then
                    mkdir -p "${as_base}"
                    tar -xzf "${tmp_dl}" -C "${as_base}" --strip-components=1
                    downloaded=1
                fi
                rm -f "${tmp_dl}"
                [ "${downloaded}" = "1" ] && break
            done
            [ "${downloaded}" = "1" ] && ok "Aerospike ${AV} installed." || warn "Aerospike download failed."
        fi
        ;;

    cassandra)
        cs_base="${SERVER_DIR:-$(pwd)}/opt/cassandra"
        if [ ! -x "${cs_base}/bin/cassandra" ]; then
            ensure_java || true
            CV="${RESOLVED}"
            URL="https://archive.apache.org/dist/cassandra/${CV}/apache-cassandra-${CV}-bin.tar.gz"
            tmp_tar=$(mktemp)
            if fetch "${URL}" "${tmp_tar}"; then
                mkdir -p "${cs_base}"
                tar -xzf "${tmp_tar}" -C "${cs_base}" --strip-components=1
                ok "Cassandra ${CV} installed."
            else warn "Cassandra download failed."; fi
            rm -f "${tmp_tar}"
        fi
        ;;

    arangodb)
        ag_base="${SERVER_DIR:-$(pwd)}/opt/arangodb"
        if [ ! -x "${ag_base}/sbin/arangod" ] && [ ! -x "${ag_base}/usr/sbin/arangod" ] && [ ! -x "${ag_base}/bin/arangod" ]; then
            GV="${RESOLVED#v}"
            series="${GV%%.*}"
            urls=("https://download.arangodb.com/arangodb${series}/Community/Linux/x86_64/arangodb3-linux-${GV}.tar.gz")
            [ "${ARCH_TYPE}" = "arm64" ] && urls=("https://download.arangodb.com/arangodb${series}/Community/Linux/aarch64/arangodb3-linux-${GV}_aarch64.tar.gz" "https://download.arangodb.com/arangodb${series}/Community/Linux/x86_64/arangodb3-linux-${GV}.tar.gz")
            downloaded=0
            for URL in "${urls[@]}"; do
                tmp_tar=$(mktemp)
                if fetch "${URL}" "${tmp_tar}"; then
                    mkdir -p "${ag_base}"
                    tar -xzf "${tmp_tar}" -C "${ag_base}" --strip-components=1
                    downloaded=1
                fi
                rm -f "${tmp_tar}"
                [ "${downloaded}" = "1" ] && break
            done
            [ "${downloaded}" = "1" ] && ok "ArangoDB ${GV} installed." || warn "ArangoDB download failed."
        fi
        ;;

    neo4j)
        nj_base="${SERVER_DIR:-$(pwd)}/opt/neo4j"
        if [ ! -x "${nj_base}/bin/neo4j" ]; then
            NV="${RESOLVED#v}"
            ensure_java || true
            URL="https://dist.neo4j.org/neo4j-community-${NV}-unix.tar.gz"
            tmp_tar=$(mktemp)
            if fetch "${URL}" "${tmp_tar}"; then
                mkdir -p "${nj_base}"
                tar -xzf "${tmp_tar}" -C "${nj_base}" --strip-components=1
                ok "Neo4j Community ${NV} installed."
            else warn "Neo4j download failed."; fi
            rm -f "${tmp_tar}"
        fi
        ;;

    influxdb)
        gh_release_install "influxdata/influxdb" "influxdb2-[0-9].*linux_${ARCH_ALT}" "influxd" "influxd" || warn "InfluxDB download failed."
        ;;

    questdb)
        qd_base="${INSTALL_DIR}/questdb"
        if [ ! -d "${qd_base}" ]; then
            QV="${RESOLVED#v}"
            URL="https://github.com/questdb/questdb/releases/download/${QV}/questdb-${QV}-jdk17-bin.tar.gz"
            tmp_tar=$(mktemp)
            if fetch "${URL}" "${tmp_tar}"; then
                mkdir -p "${qd_base}"
                tar -xzf "${tmp_tar}" -C "${qd_base}" --strip-components=1
                ok "QuestDB ${QV} installed (bundled JDK)."
            else warn "QuestDB download failed."; fi
            rm -f "${tmp_tar}"
        fi
        ;;

    elasticsearch)
        es_base="${SERVER_DIR:-$(pwd)}/opt/elasticsearch"
        if [ ! -x "${es_base}/bin/elasticsearch" ]; then
            EV="${RESOLVED#v}"
            es_arch="x86_64"; [ "${ARCH_TYPE}" = "arm64" ] && es_arch="aarch64"
            disk_preflight_mb 1500
            URL="https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-${EV}-linux-${es_arch}.tar.gz"
            tmp_tar=$(mktemp)
            if fetch "${URL}" "${tmp_tar}"; then
                mkdir -p "${es_base}"
                tar -xzf "${tmp_tar}" -C "${es_base}" --strip-components=1
                ok "Elasticsearch ${EV} installed (bundled JDK)."
            else warn "Elasticsearch download failed."; fi
            rm -f "${tmp_tar}"
        fi
        ;;

    opensearch)
        os_base="${SERVER_DIR:-$(pwd)}/opt/opensearch"
        if [ ! -x "${os_base}/bin/opensearch" ]; then
            OV="${RESOLVED#v}"
            os_arch="x64"; [ "${ARCH_TYPE}" = "arm64" ] && os_arch="arm64"
            disk_preflight_mb 1500
            URL="https://artifacts.opensearch.org/releases/bundle/opensearch/${OV}/opensearch-${OV}-linux-${os_arch}.tar.gz"
            tmp_tar=$(mktemp)
            if fetch "${URL}" "${tmp_tar}"; then
                mkdir -p "${os_base}"
                tar -xzf "${tmp_tar}" -C "${os_base}" --strip-components=1
                ok "OpenSearch ${OV} installed (bundled JDK)."
            else warn "OpenSearch download failed."; fi
            rm -f "${tmp_tar}"
        fi
        ;;

    solr)
        sl_base="${SERVER_DIR:-$(pwd)}/opt/solr"
        if [ ! -x "${sl_base}/bin/solr" ]; then
            SV="${RESOLVED}"
            ensure_java || true
            URL="https://archive.apache.org/dist/lucene/solr/${SV}/solr-${SV}.tgz"
            tmp_tar=$(mktemp)
            if fetch "${URL}" "${tmp_tar}"; then
                mkdir -p "${sl_base}"
                tar -xzf "${tmp_tar}" -C "${sl_base}" --strip-components=1
                ok "Solr ${SV} installed."
            else warn "Solr download failed."; fi
            rm -f "${tmp_tar}"
        fi
        ;;

    orientdb)
        ob_base="${SERVER_DIR:-$(pwd)}/opt/orientdb"
        if [ ! -x "${ob_base}/bin/server.sh" ]; then
            BV="${RESOLVED}"
            [[ "${BV}" != v* ]] && BV="v${BV}"
            ensure_java || true
            URL="https://github.com/orientechnologies/orientdb/releases/download/${BV}/orientdb-${BV#v}.tar.gz"
            tmp_tar=$(mktemp)
            if fetch "${URL}" "${tmp_tar}"; then
                mkdir -p "${ob_base}"
                tar -xzf "${tmp_tar}" -C "${ob_base}" --strip-components=1
                chmod +x "${ob_base}/bin/"*.sh 2>/dev/null || true
                ok "OrientDB ${BV} installed."
            else warn "OrientDB download failed."; fi
            rm -f "${tmp_tar}"
        fi
        ;;

    ravendb)
        rv_base="${SERVER_DIR:-$(pwd)}/opt/ravendb"
        if [ ! -d "${rv_base}/Server" ]; then
            RVV="${RESOLVED}"
            rv_arch="x64"; [ "${ARCH_TYPE}" = "arm64" ] && rv_arch="arm64"
            URL="https://github.com/ravendb/ravendb/releases/download/${RVV}/linux/${RVV}-linux-${rv_arch}.tar.bz2"
            probe_url "${URL}" || URL="https://github.com/ravendb/ravendb/releases/download/${RVV}/RavenDB-${RVV}-linux-${rv_arch}.tar.bz2"
            tmp_tar=$(mktemp)
            if fetch "${URL}" "${tmp_tar}"; then
                mkdir -p "${rv_base}"
                tar -xjf "${tmp_tar}" -C "${rv_base}"
                ok "RavenDB ${RVV} installed."
            else warn "RavenDB download failed."; fi
            rm -f "${tmp_tar}"
        fi
        ;;

    milvus)
        gh_release_install "milvus-io/milvus" "milvus-standalone-embed|milvus.*linux-${ARCH_ALT}|linux_${ARCH_ALT}" "milvus" "milvus" \
            || warn "Milvus standalone binary unavailable upstream; use the Docker variant or CUSTOM_DOWNLOAD_URL."
        ;;

    weaviate)
        gh_release_install "weaviate-io/weaviate" "linux-${ARCH_ALT}" "weaviate" "weaviate" || warn "Weaviate download failed."
        ;;

    quickwit)
        qw_inner="quickwit"
        gh_release_install "quickwit-oss/quickwit" "x86_64-unknown-linux-gnu|aarch64-unknown-linux-gnu" "quickwit" "quickwit" || warn "Quickwit download failed."
        ;;

    manticoresearch|manticore)
        mc_base="${INSTALL_DIR}"
        if [ ! -x "${mc_base}/searchd" ]; then
            MV="${RESOLVED#v}"
            deb_arch="amd64"; [ "${ARCH_TYPE}" = "arm64" ] && deb_arch="arm64"
            fetched=0
            for du in \
                "https://github.com/manticoresoftware/manticoresearch/releases/download/${MV}/manticore-${MV}-${deb_arch}.deb" \
                "https://github.com/manticoresoftware/manticoresearch/releases/download/${MV}/manticore-${MV}-jammy_${deb_arch}.deb" \
                "https://github.com/manticoresoftware/manticoresearch/releases/download/${MV}/manticore-${MV}-focal_${deb_arch}.deb"; do
                tmp_deb=$(mktemp)
                if fetch "${du}" "${tmp_deb}" && dpkg-deb -x "${tmp_deb}" "${mc_base}/.mdx"; then
                    find "${mc_base}/.mdx" \( -name searchd -o -name indexer \) -type f -exec cp -f {} "${mc_base}/" \; 2>/dev/null || true
                    fetched=1
                fi
                rm -rf "${mc_base}/.mdx" "${tmp_deb}"
                [ "${fetched}" = "1" ] && break
            done
            [ "${fetched}" = "1" ] && ok "Manticore Search ${MV} installed." || warn "Manticore Search download failed."
        fi
        ;;

    seaweedfs|weed)
        gh_release_install "seaweedfs/seaweedfs" "linux_${ARCH_ALT}" "weed" "weed" || warn "SeaweedFS download failed."
        ;;

    garage)
        GTAG="${RESOLVED}"
        [[ "${GTAG}" != v* ]] && GTAG="v${GTAG}"
        g_target="x86_64-unknown-linux-musl"
        [ "${ARCH_TYPE}" = "arm64" ] && g_target="aarch64-unknown-linux-musl"
        if [ ! -x "${INSTALL_DIR}/garage" ]; then
            URL="https://garagehq.deuxfleurs.fr/_releases/${GTAG}/${g_target}/garage"
            if fetch "${URL}" "${INSTALL_DIR}/garage"; then
                chmod +x "${INSTALL_DIR}/garage"
                ok "Garage ${GTAG} installed."
            else warn "Garage download failed (${URL})."; fi
        fi
        ;;

    libsql|sqld)
        gh_release_install "tursodatabase/libsql" "sqld.*linux-x86_64|sqld.*linux-aarch64" "sqld" "sqld" || warn "libSQL server download failed."
        ;;

    rethinkdb)
        rt_base="${INSTALL_DIR}"
        if [ ! -x "${rt_base}/rethinkdb" ]; then
            RTV="${RESOLVED}"
            deb_suffix="amd64~jammy"; [ "${ARCH_TYPE}" = "arm64" ] && deb_suffix="arm64~jammy"
            case "${ARCH_TYPE}" in amd64|arm64) : ;; *)
                warn "RethinkDB publishes packages for amd64/arm64 only; skipping on ${ARCH_TYPE}."
                mark_engine_ready; exit 0 ;;
            esac
            deb_url="https://download.rethinkdb.com/repository/ubuntu-22.04/pool/r/rethinkdb/rethinkdb_${RTV}_${deb_suffix}.deb"
            tmp_deb=$(mktemp)
            if fetch "${deb_url}" "${tmp_deb}" && dpkg-deb -x "${tmp_deb}" "${rt_base}/.rdx"; then
                find "${rt_base}/.rdx" -name rethinkdb -type f -exec cp -f {} "${rt_base}/rethinkdb" \; 2>/dev/null || true
                chmod +x "${rt_base}/rethinkdb" 2>/dev/null || true
                ok "RethinkDB ${RTV} installed."
            else warn "RethinkDB package download failed."; fi
            rm -rf "${rt_base}/.rdx" "${tmp_deb}"
        fi
        ;;

    custom)
        if [ -n "${CUSTOM_DOWNLOAD_URL:-}" ]; then
            fetch "${CUSTOM_DOWNLOAD_URL}" "${INSTALL_DIR}/${CUSTOM_BINARY_NAME:-server}"
            chmod +x "${INSTALL_DIR}/${CUSTOM_BINARY_NAME:-server}"
            ok "Custom engine ready."
        fi
        ;;

    *)
        log "Engine '${ENGINE}' uses container-provided binaries (no versioned installer needed)."
        ;;
esac

mark_engine_ready
exit 0
