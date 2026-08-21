# =============================================================================
#  Multi Database - Universal Runtime Image
#  By PotenFYR Studios (https://github.com/PotenFYR-Studios/Database-Eggs)
#
#  Ships MariaDB, PostgreSQL, Redis, Memcached, SQLite, Meilisearch,
#  SurrealDB, PocketBase, MinIO, Qdrant, performance auto-tuners, and version
#  downloaders in a single universal image.
# =============================================================================

FROM ubuntu:22.04

ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    USER=container \
    HOME=/home/container

# Install base dependencies, core database servers, client tools, and utilities
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
        mariadb-server \
        mariadb-client \
        postgresql \
        postgresql-contrib \
        postgresql-client \
        redis-server \
        redis-tools \
        memcached \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /var/lib/mysql \
    && rm -rf /var/lib/postgresql/*

# Download pre-built standalone database binaries
RUN case "${TARGETARCH}" in \
        "amd64") \
            curl -fsSL https://install.surrealdb.com | sh \
            && mv /root/.surrealdb/surreal /usr/local/bin/surreal || true; \
            curl -fsSL https://get.meilisearch.com | sh \
            && mv meilisearch /usr/local/bin/meilisearch || true; \
            curl -fsSL -o /usr/local/bin/minio https://dl.min.io/server/minio/release/linux-amd64/minio \
            && chmod +x /usr/local/bin/minio || true; \
            ;; \
        "arm64") \
            curl -fsSL https://install.surrealdb.com | sh \
            && mv /root/.surrealdb/surreal /usr/local/bin/surreal || true; \
            curl -fsSL https://get.meilisearch.com | sh \
            && mv meilisearch /usr/local/bin/meilisearch || true; \
            curl -fsSL -o /usr/local/bin/minio https://dl.min.io/server/minio/release/linux-arm64/minio \
            && chmod +x /usr/local/bin/minio || true; \
            ;; \
    esac

# Create container user (UID 988, GID 988)
RUN groupadd -g 988 container \
    && useradd -m -u 988 -g container -s /bin/bash container \
    && mkdir -p /home/container /mnt/server \
    && chown -R container:container /home/container /mnt/server

# Copy entrypoint, launcher, installer, and scripts
COPY entrypoint.sh /entrypoint.sh
COPY run.sh /usr/local/bin/run.sh
COPY install.sh /usr/local/bin/install.sh
COPY scripts/ /usr/local/bin/

RUN chmod +x /entrypoint.sh /usr/local/bin/run.sh /usr/local/bin/install.sh /usr/local/bin/*.sh 2>/dev/null || true

USER container
ENV USER=container HOME=/home/container
WORKDIR /home/container

ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/entrypoint.sh"]
CMD ["run.sh"]
