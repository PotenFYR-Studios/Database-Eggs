# Database Eggs

One egg. Every database. Every version. Every panel. Installs, auto-tunes, secures, and runs **20+ database engines** across all versions (SQL, In-Memory Caching, Document NoSQL, Multi-Model, Search, AI Vector stores, and S3-compatible Object Storage) with cryptographically strong automated secrets, dynamic performance auto-tuning, and cross-panel compatibility across **Pterodactyl, Pelican Panel, Feather Panel, Wisp, Jexactyl, PufferPanel**, and native Docker.

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

- **Universal Single Egg (`egg-database-multi.json`)**: Switch between MariaDB, PostgreSQL, Redis, MongoDB, SurrealDB, Meilisearch, PocketBase, and 15+ other databases simply by changing one variable.
- **All-Version Support (`DB_VERSION`)**: Deploy any version tag (such as `10.11`, `16`, `7.2`, `v2.0.4`, `0.25.0`, `latest`) or direct custom binary download URLs.
- **Cryptographically Strong Automated Secrets**: Whenever passwords or secrets are left blank or set to `auto`, the system automatically generates high-entropy, 32+ character random credentials using `/dev/urandom` and OpenSSL (~190 bits of entropy).
- **Dynamic Performance Auto-Tuning**: Automatically calculates optimal buffer pool sizes, cache limits, worker threads, and connection limits based on allocated server memory (`SERVER_MEMORY`) and CPU cores.
- **Production Security Hardening**: Enforces SCRAM-SHA-256 password hashing for PostgreSQL, removes anonymous and test accounts for MySQL/MariaDB, disables dangerous debug commands in Redis, and locks down permissions to `chmod 600` and `chmod 700`.
- **Protected Credential Persistence**: Generated secrets and connection info are saved in `.db_credentials`, `credentials.txt`, and `.env` and printed directly on the console with ready-to-copy connection strings.
- **True Cross-Panel Universal Compatibility**: First-class support for **Pterodactyl (0.7, 1.x)**, **Pelican Panel**, **Feather Panel**, **Wisp**, **Jexactyl**, **PufferPanel**, and native Docker.

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
| **Custom** | `custom` | Custom direct download URL | Any | Execute any custom database daemon via `CUSTOM_COMMAND`. |

---

## Cryptographic Strong Password System

Database security requires non-guessable, high-entropy secrets. By default (`AUTO_GENERATE_CREDENTIALS=1`), if you leave `DB_PASSWORD` or `DB_ROOT_PASSWORD` as `auto` (or blank):

1. **High-Entropy Generation**: Uses `/dev/urandom` and OpenSSL cryptographic random byte streams to generate 32-character passwords (~190 bits of entropy).
2. **URL and Connection-String Safe**: Characters are selected to prevent breaking URI connection strings (`mysql://...`, `postgresql://...`, `redis://...`).
3. **Persisted Securely**:
   - `.db_credentials`: Read by the container on startup to ensure passwords never change on server reboot.
   - `credentials.txt`: Formatted human-readable summary of all connection parameters.
   - `.env`: Ready-to-use environment variables for your application.
   - File permissions are locked to `chmod 600` (read/write only by the server container).

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
- Automatic credential generation and `.db_credentials` file persistence
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
├── egg-database-multi.json         # Universal multi-database egg (import into panel)
├── eggs/                           # Dedicated standalone eggs
│   ├── egg-mariadb.json
│   ├── egg-postgresql.json
│   ├── egg-redis.json
│   ├── egg-mongodb.json
│   ├── egg-surrealdb.json
│   ├── egg-meilisearch.json
│   ├── egg-pocketbase.json
│   ├── egg-minio.json
│   └── egg-qdrant.json
├── Dockerfile                      # Multi-arch universal container image
├── entrypoint.sh                   # Container entrypoint & credential generator
├── run.sh                          # Universal database launcher & dispatcher
├── install.sh                      # Universal installation script
├── scripts/                        # Modular engine & tuning handlers
│   ├── password-gen.sh             # Cryptographic secret & password generator
│   ├── performance-tuning.sh       # Dynamic RAM & CPU performance auto-tuner
│   ├── install-db-version.sh       # Multi-version downloader & installer
│   ├── db-init-mariadb.sh          # MariaDB & MySQL handler
│   ├── db-init-postgres.sh         # PostgreSQL handler
│   ├── db-init-redis.sh            # Redis, Valkey, KeyDB, Dragonfly handler
│   ├── db-init-mongo.sh            # MongoDB & FerretDB handler
│   ├── db-init-surreal.sh          # SurrealDB handler
│   ├── db-init-search.sh           # Meilisearch, Typesense, Qdrant handler
│   └── db-init-storage.sh          # PocketBase, MinIO, InfluxDB handler
├── tests/                          # Automated Docker verification suites
│   ├── test-docker.sh              # Universal bash Docker verification test suite
│   └── test-docker.ps1             # PowerShell Docker test runner for Windows
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