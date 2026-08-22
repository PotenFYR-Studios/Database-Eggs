#!/usr/bin/env bash
# =============================================================================
#  PotenFYR Studios - Smart Companion & Extension Loader
#  Dynamically injects auxiliary tools (Python, Node.js, Litestream, Rclone,
#  AWS CLI, database CLI tools) on-demand into isolated runtime directories.
# =============================================================================

load_companions() {
    local requested="${EXTRA_RUNTIMES:-}"
    [ -z "${requested}" ] && return 0

    local runtimes_dir="${SERVER_DIR:-/home/container}/.runtimes"
    mkdir -p "${runtimes_dir}"

    local arch
    arch=$(uname -m)
    local arch_type="amd64"
    local arch_alt="x86_64"
    case "${arch}" in
        x86_64|amd64) arch_type="amd64"; arch_alt="x86_64" ;;
        aarch64|arm64) arch_type="arm64"; arch_alt="aarch64" ;;
    esac

    # Split comma or space separated list
    local tools
    IFS=', ' read -r -a tools <<< "${requested}"

    for tool in "${tools[@]}"; do
        tool=$(echo "${tool}" | tr '[:upper:]' '[:lower:]' | xargs)
        [ -z "${tool}" ] && continue

        local target_dir="${runtimes_dir}/${tool}"
        local target_bin="${target_dir}/bin"
        mkdir -p "${target_bin}"

        case "${tool}" in
            python|uv)
                if ! command -v python3 >/dev/null 2>&1 && [ ! -x "${target_bin}/python3" ] && [ ! -x "${target_bin}/uv" ]; then
                    log "Injecting Python/UV companion runtime into ${target_dir}..."
                    local uv_url="https://github.com/astral-sh/uv/releases/latest/download/uv-${arch_alt}-unknown-linux-gnu.tar.gz"
                    if curl -fsSL --retry 3 "${uv_url}" 2>/dev/null | tar -xz -C "${target_bin}/" --strip-components=1 2>/dev/null; then
                        chmod +x "${target_bin}"/* 2>/dev/null || true
                        ok "UV / Python companion ready."
                    else
                        warn "Could not download UV standalone binary. Checking python package..."
                    fi
                fi
                export PATH="${target_bin}:${PATH}"
                ;;

            node|nodejs|bun)
                if ! command -v node >/dev/null 2>&1 && [ ! -x "${target_bin}/node" ] && [ ! -x "${target_bin}/bun" ]; then
                    log "Injecting Bun/Node.js companion runtime into ${target_dir}..."
                    local bun_url="https://github.com/oven-sh/bun/releases/latest/download/bun-linux-${arch_alt}.zip"
                    local tmp_zip
                    tmp_zip=$(mktemp)
                    if curl -fsSL --retry 3 -o "${tmp_zip}" "${bun_url}" 2>/dev/null; then
                        unzip -q -o "${tmp_zip}" -d "${target_dir}/" 2>/dev/null || true
                        rm -f "${tmp_zip}"
                        cp -f "${target_dir}"/bun-linux-*/bun "${target_bin}/bun" 2>/dev/null || true
                        ln -sf "${target_bin}/bun" "${target_bin}/node" 2>/dev/null || true
                        chmod +x "${target_bin}"/* 2>/dev/null || true
                        ok "Node.js / Bun companion ready."
                    else
                        warn "Could not download Node.js/Bun standalone binary."
                    fi
                fi
                export PATH="${target_bin}:${PATH}"
                ;;

            litestream)
                if ! command -v litestream >/dev/null 2>&1 && [ ! -x "${target_bin}/litestream" ]; then
                    log "Injecting Litestream SQLite replication companion into ${target_dir}..."
                    local ls_url="https://github.com/benbjohnson/litestream/releases/download/v0.3.13/litestream-v0.3.13-linux-${arch_type}.tar.gz"
                    if curl -fsSL --retry 3 "${ls_url}" 2>/dev/null | tar -xz -C "${target_bin}/" 2>/dev/null; then
                        chmod +x "${target_bin}/litestream" 2>/dev/null || true
                        ok "Litestream companion ready."
                    else
                        warn "Could not download Litestream binary."
                    fi
                fi
                export PATH="${target_bin}:${PATH}"
                ;;

            rclone)
                if ! command -v rclone >/dev/null 2>&1 && [ ! -x "${target_bin}/rclone" ]; then
                    log "Injecting Rclone cloud sync companion into ${target_dir}..."
                    local rc_url="https://downloads.rclone.org/rclone-current-linux-${arch_type}.zip"
                    local tmp_zip
                    tmp_zip=$(mktemp)
                    if curl -fsSL --retry 3 -o "${tmp_zip}" "${rc_url}" 2>/dev/null; then
                        unzip -q -o "${tmp_zip}" -d "${target_dir}/" 2>/dev/null || true
                        rm -f "${tmp_zip}"
                        cp -f "${target_dir}"/rclone-*-linux-*/rclone "${target_bin}/rclone" 2>/dev/null || true
                        chmod +x "${target_bin}/rclone" 2>/dev/null || true
                        ok "Rclone companion ready."
                    else
                        warn "Could not download Rclone binary."
                    fi
                fi
                export PATH="${target_bin}:${PATH}"
                ;;

            aws|aws-cli|s3cmd)
                if ! command -v aws >/dev/null 2>&1 && [ ! -x "${target_bin}/mc" ]; then
                    log "Injecting MinIO Client (mc) S3 companion into ${target_dir}..."
                    local mc_url="https://dl.min.io/client/mc/release/linux-${arch_type}/mc"
                    if curl -fsSL --retry 3 -o "${target_bin}/mc" "${mc_url}" 2>/dev/null; then
                        chmod +x "${target_bin}/mc" 2>/dev/null || true
                        ln -sf "${target_bin}/mc" "${target_bin}/s3" 2>/dev/null || true
                        ok "S3 / MinIO Client companion ready (alias: mc, s3)."
                    else
                        warn "Could not download MinIO client companion."
                    fi
                fi
                export PATH="${target_bin}:${PATH}"
                ;;

            psql|postgresql-client)
                if ! command -v psql >/dev/null 2>&1 && [ ! -x "${target_bin}/psql" ]; then
                    log "Injecting PostgreSQL client tools..."
                    if [ -f /usr/lib/postgresql/16/bin/psql ]; then
                        ln -sf /usr/lib/postgresql/16/bin/psql "${target_bin}/psql" 2>/dev/null || true
                    fi
                fi
                export PATH="${target_bin}:${PATH}"
                ;;

            mysql-client|mariadb-client)
                if ! command -v mysql >/dev/null 2>&1 && [ ! -x "${target_bin}/mysql" ]; then
                    log "Injecting MySQL/MariaDB client tools..."
                    if [ -f /usr/bin/mariadb ]; then
                        ln -sf /usr/bin/mariadb "${target_bin}/mysql" 2>/dev/null || true
                    fi
                fi
                export PATH="${target_bin}:${PATH}"
                ;;

            mongosh)
                if ! command -v mongosh >/dev/null 2>&1 && [ ! -x "${target_bin}/mongosh" ]; then
                    log "Injecting MongoDB Shell (mongosh) companion into ${target_dir}..."
                    local msh_url="https://downloads.mongodb.com/compass/mongosh-2.3.8-linux-${arch_alt}.tgz"
                    if curl -fsSL --retry 3 "${msh_url}" 2>/dev/null | tar -xz -C "${target_dir}/" 2>/dev/null; then
                        cp -f "${target_dir}"/mongosh-*/bin/mongosh "${target_bin}/mongosh" 2>/dev/null || true
                        chmod +x "${target_bin}/mongosh" 2>/dev/null || true
                        ok "mongosh companion ready."
                    else
                        warn "Could not download mongosh companion."
                    fi
                fi
                export PATH="${target_bin}:${PATH}"
                ;;

            redis-cli)
                if ! command -v redis-cli >/dev/null 2>&1 && [ ! -x "${target_bin}/redis-cli" ]; then
                    log "Injecting Redis CLI companion tools..."
                    if [ -f /usr/bin/redis-cli ]; then
                        ln -sf /usr/bin/redis-cli "${target_bin}/redis-cli" 2>/dev/null || true
                    fi
                fi
                export PATH="${target_bin}:${PATH}"
                ;;

            *)
                log "Custom companion '${tool}' requested. Setting path: ${target_bin}"
                export PATH="${target_bin}:${target_dir}:${PATH}"
                ;;
        esac
    done
}
