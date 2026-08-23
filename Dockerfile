# =============================================================================
#  PotenFYR Studios - Multi-Variant Database Container Runtime
#  Supports Multi-Variant Dedicated Lean Builds & Universal Multi-Database Images:
#  - RUNTIME_VARIANT=all          (Universal Multi-Database)
#  - RUNTIME_VARIANT=mysql        (MariaDB / MySQL Server & Client)
#  - RUNTIME_VARIANT=postgres     (PostgreSQL 16+ Server, Contrib & Client)
#  - RUNTIME_VARIANT=mongodb      (MongoDB Community Server & Mongosh)
#  - RUNTIME_VARIANT=redis        (Redis, Valkey, KeyDB, Dragonfly, Memcached)
#  - RUNTIME_VARIANT=meilisearch  (Meilisearch Search Engine)
#  - RUNTIME_VARIANT=clickhouse   (ClickHouse Analytical Server & Client)
#  - RUNTIME_VARIANT=sqlite       (SQLite3 + Litestream Replication)
# =============================================================================

FROM ubuntu:22.04

LABEL maintainer="PotenFYR Studios <support@potenfyr.com>" \
      org.opencontainers.image.title="PotenFYR Multi-Variant Database Runtime" \
      org.opencontainers.image.description="Dedicated lean & universal database container runtimes with companion injection for Pterodactyl, Pelican, Feather, Wisp, and Docker." \
      org.opencontainers.image.source="https://github.com/PotenFYR-Studios/Database-Eggs" \
      org.opencontainers.image.licenses="MIT"

ARG TARGETPLATFORM
ARG TARGETARCH
ARG RUNTIME_VARIANT=all

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    RUNTIME_VARIANT=${RUNTIME_VARIANT} \
    PATH="/usr/lib/postgresql/16/bin:/usr/lib/postgresql/15/bin:/usr/lib/postgresql/14/bin:/usr/local/bin:/usr/bin:/bin:${PATH}"

# Install common system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        wget \
        jq \
        unzip \
        tar \
        xz-utils \
        tzdata \
        iproute2 \
        procps \
        net-tools \
        locales \
        openssl \
        pwgen \
        gosu \
        tini \
        sqlite3 \
    && rm -rf /var/lib/apt/lists/* \
    && locale-gen en_US.UTF-8 \
    && update-locale LANG=en_US.UTF-8

# Conditional Engine Installation based on RUNTIME_VARIANT
RUN apt-get update && \
    if [ "${RUNTIME_VARIANT}" = "all" ] || [ "${RUNTIME_VARIANT}" = "mysql" ]; then \
        apt-get install -y --no-install-recommends mariadb-server mariadb-client; \
    fi && \
    if [ "${RUNTIME_VARIANT}" = "all" ] || [ "${RUNTIME_VARIANT}" = "postgres" ]; then \
        apt-get install -y --no-install-recommends postgresql postgresql-contrib postgresql-client && \
        for bin in /usr/lib/postgresql/*/bin/*; do [ -f "$bin" ] && ln -sf "$bin" /usr/local/bin/ 2>/dev/null || true; done; \
    fi && \
    if [ "${RUNTIME_VARIANT}" = "all" ] || [ "${RUNTIME_VARIANT}" = "redis" ]; then \
        apt-get install -y --no-install-recommends redis-server redis-tools memcached; \
    fi && \
    rm -rf /var/lib/apt/lists/* \
    && rm -rf /var/lib/mysql \
    && rm -rf /var/lib/postgresql/*

# Standalone Engine Binaries (Universal & Dedicated Variants)
RUN arch_type="amd64"; arch_alt="x86_64"; arch_gnu="x86_64-unknown-linux-gnu"; \
    if [ "${TARGETARCH}" = "arm64" ]; then \
        arch_type="arm64"; arch_alt="aarch64"; arch_gnu="aarch64-unknown-linux-gnu"; \
    fi; \
    if [ "${RUNTIME_VARIANT}" = "all" ] || [ "${RUNTIME_VARIANT}" = "meilisearch" ]; then \
        curl -fsSL -o /usr/local/bin/meilisearch "https://github.com/meilisearch/meilisearch/releases/download/v1.12.0/meilisearch-linux-${arch_alt}" || true; \
    fi; \
    if [ "${RUNTIME_VARIANT}" = "all" ] || [ "${RUNTIME_VARIANT}" = "clickhouse" ]; then \
        curl -fsSL https://clickhouse.com/ | sh && (mv clickhouse /usr/local/bin/clickhouse 2>/dev/null || true) || true; \
    fi; \
    if [ "${RUNTIME_VARIANT}" = "all" ] || [ "${RUNTIME_VARIANT}" = "sqlite" ]; then \
        curl -fsSL "https://github.com/benbjohnson/litestream/releases/download/v0.3.13/litestream-v0.3.13-linux-${arch_type}.tar.gz" 2>/dev/null | tar -xz -C /usr/local/bin/ 2>/dev/null || true; \
    fi; \
    if [ "${RUNTIME_VARIANT}" = "all" ]; then \
        curl -fsSL https://install.surrealdb.com | sh && (cp -f /root/.surrealdb/surreal /usr/local/bin/surreal 2>/dev/null || cp -f ~/.surrealdb/surreal /usr/local/bin/surreal 2>/dev/null || true) || true; \
        curl -fsSL -o /usr/local/bin/minio "https://dl.min.io/server/minio/release/linux-${arch_type}/minio" || true; \
        curl -fsSL -o /tmp/pb.zip "https://github.com/pocketbase/pocketbase/releases/download/v0.25.0/pocketbase_0.25.0_linux_${arch_type}.zip" && unzip -q /tmp/pb.zip -d /tmp/pb && mv /tmp/pb/pocketbase /usr/local/bin/pocketbase && rm -rf /tmp/pb* || true; \
        curl -fsSL "https://github.com/qdrant/qdrant/releases/download/v1.12.1/qdrant-${arch_gnu}.tar.gz" 2>/dev/null | tar -xz -C /usr/local/bin/ 2>/dev/null || true; \
        if [ "${TARGETARCH}" = "amd64" ] || [ "${TARGETARCH}" = "arm64" ]; then \
            apt-get update -qq && apt-get install -y -qq --no-install-recommends build-essential && \
            curl -fsSL -o /tmp/valkey.tar.gz "https://github.com/valkey-io/valkey/archive/refs/tags/8.1.3.tar.gz" && \
            tar -xzf /tmp/valkey.tar.gz -C /tmp && \
            (cd /tmp/valkey-8.1.3 && make MALLOC=libc valkey-server valkey-cli >/dev/null 2>&1) \
                && cp -f /tmp/valkey-8.1.3/src/valkey-server /usr/local/bin/ \
                && cp -f /tmp/valkey-8.1.3/src/valkey-cli /usr/local/bin/ \
                || true; \
            rm -rf /tmp/valkey*; \
            apt-get purge -y --auto-remove build-essential -qq 2>/dev/null || true; \
        fi; \
    fi; \
    chmod +x /usr/local/bin/* 2>/dev/null || true

# Create container users and configure permissions for dynamic UID mapping (OpenShift/Pterodactyl/Docker)
RUN groupadd -g 988 container 2>/dev/null || true \
    && useradd -m -u 988 -g container -s /bin/bash container 2>/dev/null || true \
    && groupadd -g 999 dockeruser 2>/dev/null || true \
    && useradd -m -u 999 -g 988 -s /bin/bash ptdluser 2>/dev/null || true \
    && groupadd -g 1000 standarduser 2>/dev/null || true \
    && useradd -m -u 1000 -g 988 -s /bin/bash appuser 2>/dev/null || true \
    && mkdir -p /home/container /mnt/server \
    && chown -R container:container /home/container /mnt/server \
    && chmod -R 777 /home/container /mnt/server \
    && chmod 666 /etc/passwd /etc/group /etc/shadow 2>/dev/null || true

# Copy entrypoint, launcher, and modular scripts
COPY entrypoint.sh /entrypoint.sh
COPY run.sh /usr/local/bin/run.sh
COPY scripts/ /usr/local/bin/

RUN chmod +x /entrypoint.sh /usr/local/bin/run.sh /usr/local/bin/*.sh 2>/dev/null || true

USER container
ENV USER=container HOME=/home/container
WORKDIR /home/container

ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/entrypoint.sh"]
CMD ["run.sh"]
