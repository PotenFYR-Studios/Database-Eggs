# Database Eggs

One egg. Every database. Every version. Every panel. Installs, auto-tunes, secures, and runs **55+ database engines** at **any upstream version** (SQL, NoSQL, In-Memory, Vector, Search, Graph, Time-Series, Object Storage) - versions install isolated inside your container on demand from startup variables. Switching engine or major version never deletes previous data. Cryptographically strong automated secrets, dynamic performance auto-tuning, automatic panel detection, deep crash diagnostics, and cross-panel compatibility across **Pterodactyl, Pelican Panel, Feather Panel, Wisp, Convoy, Cytopanel, Jexactyl, PufferPanel**, Kubernetes/OpenShift, and native Docker.

```text
   __  ___      ____  _       ____  ____     
  /  |/  /_  __/ / /_(_)     / __ \/ __ )    
 / /|_/ / / / / / __/ /_____/ / / / __  |    
/ /  / / /_/ / / /_/ /_____/ /_/ / /_/ /     
/_/  /_/\__,_/_/\__/_/     /_____/_____/      
  » Universal Multi-Database Server Runtime
    By PotenFYR Studios • support@potenfyr.in
```

[![GitHub License](https://img.shields.io/github/license/PotenFYR-Studios/Database-Eggs?style=for-the-badge&color=blue)](LICENSE)
[![Docker Image](https://img.shields.io/badge/Docker-GHCR-blue?style=for-the-badge&logo=docker)](https://github.com/PotenFYR-Studios/Database-Eggs/pkgs/container/database-eggs)
[![Universal Compatibility](https://img.shields.io/badge/Panels-Pterodactyl%20%7C%20Pelican%20%7C%20Feather%20%7C%20Wisp-brightgreen?style=for-the-badge)](https://github.com/PotenFYR-Studios/Database-Eggs)

---

## Table of Contents

1. [Features](#features)
2. [Supported Engines & All-Version Matrix](#supported-engines--all-version-matrix)
3. [Cryptographic Strong Password System](#cryptographic-strong-password-system)
4. [Dynamic Performance Auto-Tuning](#dynamic-performance-auto-tuning)
5. [Production Security Hardening](#production-security-hardening)
6. [Quickstart & Setup](#quickstart--setup)
7. [Connecting to Your Database](#connecting-to-your-database)
8. [Docker & Panel Testing Suite](#docker--panel-testing-suite)
9. [Egg Variables Reference](#egg-variables-reference)
10. [Repository Layout](#repository-layout)
11. [License](#license)

---

## Features

- **Universal Single Egg (`egg-database-multi.json`) + Single Image**: One egg, one container image. Pick any of 55+ engines via `DATABASE_TYPE`; everything installs inside your own container volume - nothing touches the host.
- **Exact-Version Contract (`DB_VERSION`)**: Set `18`, `11.4`, `8.0`, `latest`, or a full version - the runtime provisions exactly that engine version and **refuses to silently run a different one** (`STRICT_VERSION=1` default). `latest` resolves dynamically upstream at every boot; series like `16` auto-resolve to the newest patch.
- **Non-Destructive Version Switching**: Data lives in per-instance folders (`data/<engine>/<version>/`). Same-series boots reuse the identical instance; breaking major switches create a fresh instance and clearly print where old data is preserved. Nothing is ever deleted automatically.
- **Automatic Panel Detection**: Identifies Pterodactyl, Pelican, Feather/Wings-family, Wisp, Convoy, Kubernetes/OpenShift, or plain Docker from environment signals and shows it on the startup card.
- **Deep Crash Diagnostics**: Any failure writes a sanitized crash report (stack trace, last command, env snapshot with secrets masked, recent engine logs, disk/network state) to `logs/startup_error.log` / `logs/installer.log`.
- **Cryptographically Strong Automated Secrets**: `auto`/blank passwords become 32+ char high-entropy secrets (~190 bits) persisted in `.env` (mode `600`), never logged.
- **Dynamic Performance Auto-Tuning**: Buffer pools, caches, workers, and connection limits computed from allocated RAM/CPU.
- **Production Security Hardening**: SCRAM-SHA-256 for PostgreSQL, anonymous/test account purge for MySQL/MariaDB, Redis `DEBUG` removal, MongoDB authorization, checksum-verified downloads, loopback-only secondary ports (consoles/admin UIs) unless explicitly allocated.
- **Lightweight & Fleet-Friendly**: Version stamps skip re-downloads, extracted packages are pruned of docs/test-suites, disk preflight warns before big installs, `SKIP_VERSION_INSTALL=1` enables air-gapped boot using system binaries.

---

## Supported Engines & All-Version Matrix

| Engine | `DATABASE_TYPE` | Version Options (`DB_VERSION`) | Default Port | Key Capabilities |
| :--- | :--- | :--- | :--- | :--- |
| **MariaDB** | `mariadb` | `latest`, `10.5`, `10.6`, `10.11`, `11.0`, `11.4` | `3306` | InnoDB auto-tuned pool, UTF8MB4, auto-provisioned user/database, custom `my.cnf`. |
| **MySQL** | `mysql` | `latest`, `5.7`, `8.0`, `8.4`, `9.0` | `3306` | Oracle MySQL compatible relational engine with remote root grants and security hardening. |
| **PostgreSQL** | `postgresql` | `latest`, `12`, `13`, `14`, `15`, `16`, `17` | `5432` | Enterprise SQL with SCRAM-SHA-256 auth, `uuid-ossp`, `pg_trgm`, `vector`. |
| **Redis** | `redis` | `latest`, `6.0`, `6.2`, `7.0`, `7.2`, `7.4`, `8.0` | `6379` | High-speed cache/broker with RDB + AOF persistence, multi-threading, and `requirepass`. |
| **Valkey** | `valkey` | `latest`, `7.2`, `8.0` | `6379` | High-performance open source Linux Foundation Redis alternative. |
| **KeyDB** | `keydb` | `latest`, `6.3` | `6379` | Multi-threaded Redis superset with high throughput. |
| **Dragonfly** | `dragonfly` | `latest`, `v1.x` | `6379` | Next-generation ultra-fast in-memory datastore. |
| **Memcached** | `memcached` | `latest`, `1.6.x` | `11211` | Pure in-memory key-value caching system. |
| **MongoDB** | `mongodb` | `latest`, `4.4`, `5.0`, `6.0`, `7.0`, `8.0` | `27017` | Document database with WiredTiger engine and auto-configured admin auth. |
| **FerretDB** | `ferretdb` | `latest`, `v1.x`, `v2.x` | `27017` | MongoDB-compatible engine backed by SQLite or PostgreSQL. |
| **SurrealDB** | `surrealdb` | `latest`, `v1.0.0` -> `v2.x` | `8000` | Document, Graph, Relational, and real-time WebSocket database with SurrealQL. |
| **Meilisearch** | `meilisearch` | `latest`, `v1.0.0` -> `v1.12.x` | `7700` | Ultra-fast typo-tolerant full-text search engine with REST API. |
| **Typesense** | `typesense` | `latest`, `0.25.0`, `26.0`, `27.0` | `8108` | Typo-tolerant fast search engine with CORS support. |
| **Qdrant** | `qdrant` | `latest`, `v1.8.0` -> `v1.12.x` | `6333` | Vector similarity search engine for AI embeddings and semantic search with Web UI. |
| **PocketBase** | `pocketbase` | `latest`, `0.20.0` -> `0.25.x` | `8090` | Single-binary realtime backend with embedded SQLite and Admin UI. |
| **MinIO** | `minio` | `latest`, `RELEASE.YYYY-MM-DD...` | `9000` | S3-compatible high-performance object storage with Web Console (`9001`). |
| **ClickHouse** | `clickhouse` | `latest`, `24.x` | `8123` | High-performance columnar database for real-time analytics and big data. |
| **InfluxDB** | `influxdb` | `latest`, `1.8`, `2.7`, `3.0` | `8086` | Time-series database for metrics, events, and IoT monitoring. |
| **VictoriaMetrics** | `victoriametrics` | `latest`, `v1.90` -> `v1.108.x` | `8428` | High-efficiency Prometheus-compatible time-series database. |
| **Neo4j** | `neo4j` | `latest`, `5.x` | `7474` | Leading Graph database with Cypher query language and Browser UI. |
| **Apache CouchDB** | `couchdb` | `latest`, `3.3.x` | `5984` | JSON document database with HTTP/REST API and Fauxton dashboard. |
| **CockroachDB** | `cockroachdb` | `latest`, `23.2`, `24.3`, `25.x` | `26257` | Distributed survivable SQL (single-node mode; `COCKROACH_SECURE=1` for certs). |
| **YugabyteDB** | `yugabytedb` | `latest`, `2.20`, `2024.x` | `5433` | PostgreSQL-compatible distributed SQL with YSQL API on your allocation. |
| **TiDB** | `tidb` | `latest`, `7.5`, `8.5` | `4000` | MySQL-compatible HTAP database using embedded unistore storage. |
| **Dolt** | `dolt` | `latest`, `1.x` | `3306` | MySQL-compatible SQL database with version-controlled data (branches/diffs). |
| **libSQL (sqld)** | `sqld` | `latest`, `0.x` | `8080` | SQLite fork server with HTTP API (Turso-compatible). |
| **Etcd** | `etcd` | `latest`, `3.5.x` | `2379` | Distributed key-value store for configuration & service discovery (v3 API). |
| **NATS** | `nats` | `latest`, `2.10.x` | `4222` | High-performance messaging with embedded JetStream KV/Object stores. |
| **Immudb** | `immudb` | `latest`, `1.9.x` | `3322` | Tamper-proof immutable ledger database with cryptographic proofs. |
| **Dgraph** | `dgraph` | `latest`, `21.x`, `24.x` | `8080` | Native GraphQL graph database (Zero+Alpha on one allocation). |
| **ArangoDB** | `arangodb` | `latest`, `3.12.x` | `8529` | Multi-model (document/graph/key-value) with AQL query language. |
| **OrientDB** | `orientdb` | `latest`, `3.2.x` | `2424` | Multi-model NoSQL with SQL-like queries and graph support (Java auto-injected). |
| **RavenDB** | `ravendb` | `latest`, `6.x`, `7.x` | `8080` | ACID NoSQL document database with full-text search (self-contained runtime). |
| **Cassandra** | `cassandra` | `latest`, `4.1`, `5.0` | `9042` | Wide-column distributed NoSQL with CQL (JRE 17 auto-injected). |
| **Aerospike** | `aerospike` | `latest`, `7.x` | `3000` | High-performance real-time NoSQL with in-memory storage engine. |
| **RethinkDB** | `rethinkdb` | `latest`, `2.4.x` | `28015` | Real-time JSON database with changefeeds and ReQL. |
| **Elasticsearch** | `elasticsearch` | `latest`, `8.x`, `9.x` | `9200` | Distributed RESTful search & analytics (single-node, bundled JDK). |
| **OpenSearch** | `opensearch` | `latest`, `2.x` | `9200` | AWS-forked Elasticsearch successor with OpenSearch Dashboards support. |
| **Solr** | `solr` | `latest`, `9.x` | `8983` | Enterprise Lucene-based search platform with faceting & highlighting. |
| **Manticore Search** | `manticoresearch` | `latest`, `6.x`, `7.x` | `9306` | Fast open-source search (MySQL protocol listener on loopback by default). |
| **Milvus** | `milvus` | `latest`, `2.4.x` | `19530` | Cloud-native vector database for AI similarity search (standalone). |
| **Weaviate** | `weaviate` | `latest`, `1.2x` | `8080` | GraphQL-vector hybrid search engine with modular vectorizers. |
| **Quickwit** | `quickwit` | `latest`, `0.8.x` | `7280` | Sub-second search on object storage / logs analytics engine. |
| **QuestDB** | `questdb` | `latest`, `8.x` | `9000` | High-performance time-series with InfluxDB-line & PostgreSQL protocols. |
| **SeaweedFS** | `seaweedfs` | `latest`, `3.x` | `9333` | Fast distributed object store (volume API on allocation, S3 optional). |
| **Garage** | `garage` | `latest`, `1.x` | `3900` | Lightweight geo-distributed S3-compatible object storage (single node). |
| **Custom** | `custom` | Custom direct download URL | Any | Execute any custom database daemon via `CUSTOM_COMMAND`. |

> **Single-port policy**: panels allocate ONE port per server. Only each engine's primary protocol binds your allocation (`0.0.0.0`). Secondary services (admin UIs, consoles, cluster ports) default to `127.0.0.1` inside the container and can be exposed via explicit variables (`CONSOLE_PORT`, `TCP_PORT`, `NEO4J_HTTP_PORT`, etc.).

### Version Selection & Data Instance Safety

- `DB_VERSION=latest` → newest upstream release, resolved fresh every boot.
- `DB_VERSION=18` or `11.4` → newest patch of that series.
- `DB_VERSION=8.0.45` → exact version.
- Data instances are isolated: `data/<engine>/<series>/`. Switching majors creates a NEW instance - old data stays untouched and the console tells you its path so you can migrate or delete it manually when ready.

---

## Cryptographic Strong Password System

Database security requires non-guessable, high-entropy secrets. By default (`AUTO_GENERATE_CREDENTIALS=1`), if you leave `DB_PASSWORD` or `DB_ROOT_PASSWORD` as `auto` (or blank):

1. **High-Entropy Generation**: Uses `/dev/urandom` and OpenSSL cryptographic random byte streams to generate 32-character passwords (~190 bits of entropy).
2. **URL and Connection-String Safe**: Characters are selected to prevent breaking URI connection strings (`mysql://...`, `postgresql://...`, `redis://...`).
3. **Persisted Securely**:
   - `.env`: Saved in standard dotenv format with permissions locked to `chmod 600`. Read on startup so passwords never change on server reboot.
   - Startup Environment: Exported into runtime environment variables and shell aliases (`.profile` & `.bashrc`).

---

## Dynamic Performance Auto-Tuning

When `PERFORMANCE_TUNING=1` (default), the egg dynamically configures database engines based on allocated RAM (`SERVER_MEMORY`) and CPU cores:

- **MariaDB / MySQL**:
  - `innodb_buffer_pool_size` set to **60% of container RAM** (for example 614MB on 1GB, 2.4GB on 4GB).
  - `innodb_log_file_size` set to **25% of buffer pool**.
  - `innodb_flush_log_at_trx_commit = 2` for maximum game server and web throughput with ACID compliance.
  - `max_connections` and `thread_cache_size` auto-scaled to prevent out-of-memory OOM crashes.
- **PostgreSQL**:
  - `shared_buffers` set to **25% of container RAM**.
  - `effective_cache_size` set to **75% of container RAM**.
  - `maintenance_work_mem` set to **10% of RAM** (capped at 512MB).
  - `work_mem` calculated dynamically to allow complex queries without exhausting RAM.
  - `random_page_cost = 1.1` optimized for NVMe/SSD storage.
- **Redis / Valkey / KeyDB**:
  - `maxmemory` set to **85% of container RAM** (reserving 15% for background saves and replication).
  - `io-threads` and `io-threads-do-reads` enabled and scaled to CPU core count.
  - `lazyfree-lazy-eviction` and non-blocking background memory reclamation enabled.
- **MongoDB**:
  - `wiredTiger.engineConfig.cacheSizeGB` calculated based on container RAM.
  - Snappy block compression and index prefix compression enabled.

---

## Production Security Hardening

When `SECURITY_HARDENING=1` (default), the egg applies production-grade isolation policies:

1. **PostgreSQL**: Strict `SCRAM-SHA-256` password encryption enforced for all remote network connections.
2. **MariaDB / MySQL**: Anonymous user accounts and test databases are purged on first startup; local infile and symbolic link exploits are disabled.
3. **Redis**: Dangerous administrative commands (`DEBUG`) are removed from public access in production.
4. **MongoDB**: Strict role-based authorization enabled (`security.authorization: enabled`).
5. **Permissions**: Sockets and data directories are restricted to `chmod 700` and credential files to `chmod 600`.
6. **Masked Logs**: Passwords and secret tokens are automatically masked in debug logs.

---

## Quickstart & Setup

### 1. Import the Egg into Your Panel
1. Download [egg-database-multi.json](https://github.com/PotenFYR-Studios/Database-Eggs/blob/main/egg-database-multi.json).
2. In your panel Admin area:
   - **Pterodactyl / Jexactyl**: Go to **Admin -> Nests -> Create Nest (for example "Databases") -> Import Egg** and upload `egg-database-multi.json`.
   - **Pelican Panel**: Go to **Admin -> Eggs -> Import** and select `egg-database-multi.json`.

### 2. Create a Server
- **Server Name**: `Production Database`
- **Egg**: `Multi Database`
- **Docker Image**: `ghcr.io/potenfyr-studios/database-eggs:latest`
- **Port Allocation**: Assign a port (for example `3306` for MariaDB/MySQL, `5432` for Postgres, `6379` for Redis, `27017` for Mongo, `9000` for MinIO).

### 3. Configure Variables
- Set `DATABASE_TYPE` (such as `mariadb`, `postgresql`, `redis`, `mongodb`, `surrealdb`, `pocketbase`, `meilisearch`, `minio`).
- Set `DB_VERSION` (such as `latest`, `16`, `10.11`, `7.2`, `v2.0.4`).
- Leave passwords as `auto` to generate unbreakable random credentials.

### 4. Start the Server
Click **Start**. The console will display the banner, auto-tune performance parameters, output connection details, and start the engine.

---

## Connecting to Your Database

```bash
# MariaDB / MySQL
mysql -h <SERVER_IP> -P <PORT> -u <DB_USER> -p'<DB_PASSWORD>' <DB_NAME>

# PostgreSQL
psql "postgresql://<DB_USER>:<DB_PASSWORD>@<SERVER_IP>:<PORT>/<DB_NAME>"

# Redis / Valkey / KeyDB / Dragonfly
redis-cli -h <SERVER_IP> -p <PORT> -a '<DB_PASSWORD>'

# MongoDB
mongosh "mongodb://<DB_USER>:<DB_PASSWORD>@<SERVER_IP>:<PORT>/<DB_NAME>?authSource=admin"

# SurrealDB
surreal sql --endpoint http://<SERVER_IP>:<PORT> --user <DB_USER> --pass '<DB_PASSWORD>'
```

---

## Docker & Panel Testing Suite

The repository includes a standalone automated test suite to verify all database engines under simulated panel container conditions (UID `988:988`, volume mounts, non-root user permissions, memory limits, and signal handling):

### Running on Linux / macOS / WSL

```bash
chmod +x tests/test-docker.sh
./tests/test-docker.sh
```

### Running on Windows (PowerShell)

```powershell
.\tests\test-docker.ps1
```

The test suite validates:
- Multi-engine startup and socket initialization
- Client connection and query execution (MariaDB, PostgreSQL, Redis, MongoDB, SurrealDB, Meilisearch, PocketBase, MinIO, Qdrant)
- Automatic credential generation and `.env` file persistence (mode 600)
- Dynamic RAM auto-tuning and memory capping
- Graceful `SIGTERM` / `SIGINT` container shutdown (clean exit codes)

---

## Egg Variables Reference

| Variable | Default | Description |
| :--- | :--- | :--- |
| `DATABASE_TYPE` | `mariadb` | Database engine to execute (`mariadb`, `mysql`, `postgresql`, `redis`, `valkey`, `mongodb`, `surrealdb`, `meilisearch`, `pocketbase`, `minio`, `qdrant`, etc.). |
| `DB_VERSION` | `latest` | Target version tag or release (for example `10.11`, `16`, `7.2`, `v2.0.4`, `0.25.0`, or direct URL). |
| `DB_NAME` | `database` | Name of the primary database or schema created on first initialization. |
| `DB_USER` | `dbuser` | Application user created with full database privileges. |
| `DB_PASSWORD` | `auto` | Application user password. `auto` generates a high-entropy 32+ char secret. |
| `DB_ROOT_PASSWORD`| `auto` | Root, Superuser, Admin, or Master Key. `auto` generates an ultra-strong secret. |
| `AUTO_GENERATE_CREDENTIALS` | `1` | `1` = automatically generate and persist strong credentials on startup. |
| `PERFORMANCE_TUNING` | `1` | `1` = dynamically calculate buffer pools, memory caches, and IO threads. |
| `SECURITY_HARDENING` | `1` | `1` = enforce SCRAM-SHA-256, purge default accounts, and lock permissions. |
| `EXTRA_ARGS` | `""` | Custom command-line arguments passed directly to the database daemon. |
| `EXTRA_URLS` | `""` | Extra files to download during installation (format: `dest/file\|url`). |
| `CUSTOM_COMMAND`| `""` | Custom shell command executed when `DATABASE_TYPE=custom`. |

---

## Repository Layout

```
Database-Eggs/
├── egg-database-multi.json         # THE universal egg (single egg, 55+ engines, any version)
├── Dockerfile                      # Multi-arch universal container image
├── entrypoint.sh                   # Entrypoint: panel detection, secrets, crash diagnostics
├── run.sh                          # Universal launcher: version contract + data instances
├── scripts/                        # Modular engine & tuning handlers
│   ├── lib-diagnostics.sh          # Central logging, traces, crash-safety library
│   ├── password-gen.sh             # Cryptographic secret & password generator
│   ├── performance-tuning.sh       # Dynamic RAM & CPU performance auto-tuner
│   ├── install-db-version.sh       # 55+ engine version installer (latest resolver)
│   ├── db-init-mariadb.sh          # MariaDB & MySQL handler
│   ├── db-init-postgres.sh         # PostgreSQL handler (13-18+)
│   ├── db-init-redis.sh            # Redis, Valkey, KeyDB, Dragonfly, Memcached
│   ├── db-init-mongo.sh            # MongoDB & FerretDB handler
│   ├── db-init-surreal.sh          # SurrealDB handler
│   ├── db-init-search.sh           # Meili, Typesense, Qdrant, ES, OpenSearch, Solr...
│   ├── db-init-storage.sh          # PocketBase, MinIO, ClickHouse, QuestDB, Garage...
│   └── db-init-extra.sh            # CockroachDB, TiDB, Dolt, Etcd, NATS, Cassandra...
├── tests/
│   └── test-docker.sh              # Universal bash Docker verification test suite
├── .github/workflows/
│   ├── docker-image.yml            # CI/CD: Builds multi-arch images (GHCR)
│   ├── validate-eggs.yml           # CI: Validates egg JSON and shell syntax
│   └── test-docker.yml             # CI: Automated Docker integration testing
├── LICENSE                         # MIT License
└── README.md                       # Documentation
```

---

## License

This project is licensed under the [MIT License](LICENSE) : developed and maintained by **[PotenFYR Studios](https://github.com/PotenFYR-Studios)**.