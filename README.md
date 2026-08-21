# Database Eggs

One egg. Every database. Every panel. Installs, configures, secures, and runs **20+ database engines** — SQL, In-Memory Caching, Document NoSQL, Multi-Model, Search, AI Vector stores, and S3-compatible Object Storage — with cryptographically strong automated secrets, cross-panel compatibility across **Pterodactyl, Pelican Panel, Feather Panel, Wisp, Jexactyl, PufferPanel**, and standalone Docker.

```
  ____        _        _                    _____                  
 |  _ \  __ _| |_ __ _| |__   __ _ ___  ___| ____|__ _  __ _ ___ 
 | | | |/ _` | __/ _` | '_ \ / _` / __|/ _ \  _| / _` |/ _` / __|
 | |_| | (_| | || (_| | |_) | (_| \__ \  __/ |__| (_| | (_| \__ \
 |____/ \__,_|\__\__,_|_.__/ \__,_|___/\___|_____\__, |\__, |___/
                                                 |___/ |___/     
                          - By PotenFYR Studios
```

[![GitHub License](https://img.shields.io/github/license/PotenFYR-Studios/Database-Eggs?style=for-the-badge&color=blue)](LICENSE)
[![Docker Image](https://img.shields.io/badge/Docker-GHCR-blue?style=for-the-badge&logo=docker)](https://github.com/PotenFYR-Studios/Database-Eggs/pkgs/container/database-eggs)
[![Universal Compatibility](https://img.shields.io/badge/Panels-Pterodactyl%20%7C%20Pelican%20%7C%20Feather%20%7C%20Wisp-brightgreen?style=for-the-badge)](https://github.com/PotenFYR-Studios/Database-Eggs)

---

## Table of Contents

1. [Features](#features)
2. [Supported Database Engines](#supported-database-engines)
3. [Cryptographic Strong Password System](#cryptographic-strong-password-system)
4. [Quickstart & Setup](#quickstart--setup)
5. [Connecting to Your Database](#connecting-to-your-database)
6. [Egg Variables Reference](#egg-variables-reference)
7. [Repository Layout](#repository-layout)
8. [Docker Images (GHCR)](#docker-images-ghcr)
9. [Troubleshooting & FAQ](#troubleshooting--faq)
10. [License](#license)

---

## Features

- ⚡ **Universal Single Egg (`egg-database-multi.json`)**: Switch between MariaDB, PostgreSQL, Redis, MongoDB, SurrealDB, Meilisearch, PocketBase, and 15+ other databases simply by changing one variable.
- 🔐 **Cryptographically Strong Automated Secrets**: Whenever passwords/secrets are left blank or set to `auto`, the system automatically generates high-entropy, 32+ character random credentials using `/dev/urandom` and `openssl`.
- 📁 **Protected Credential Persistence**: Generated secrets and connection info are saved in `.db_credentials`, `credentials.txt`, and `.env` with strict `chmod 600` permissions and printed directly on the console with ready-to-copy connection strings.
- 🌐 **True Cross-Panel Universal Compatibility**: First-class support for **Pterodactyl (0.7, 1.x)**, **Pelican Panel**, **Feather Panel**, **Wisp**, **Jexactyl**, **PufferPanel**, and native Docker.
- 🛠️ **Full Data & Config Persistence**: User editable configuration files (`my.cnf`, `postgresql.conf`, `redis.conf`, `mongod.conf`) stored in `./config` and persistent database storage in `./data`.
- 🚀 **Built-in Web UIs & Consoles**: Instant access to web dashboards for MinIO (S3 Console), PocketBase (Admin UI), Qdrant (Dashboard), and SurrealDB.
- 🛡️ **Graceful Shutdown & Signal Handling**: Proper `SIGTERM` / `SIGINT` handling ensures database engines flush caches and shut down cleanly without table corruption.

---

## Supported Database Engines

| Engine | Type / Family | `DATABASE_TYPE` | Default Port | Storage & Key Features |
| :--- | :--- | :--- | :--- | :--- |
| **MariaDB** | SQL / Relational | `mariadb` | `3306` | InnoDB, UTF8MB4, auto-provisioned user/database, custom `my.cnf`. |
| **MySQL** | SQL / Relational | `mysql` | `3306` | Oracle MySQL compatible relational engine with remote root grants. |
| **PostgreSQL** | SQL / Relational | `postgresql` | `5432` | Enterprise SQL with SCRAM-SHA-256 auth, `uuid-ossp`, `pg_trgm`, `vector`. |
| **Redis** | In-Memory / Cache | `redis` | `6379` | High-speed cache/broker with RDB + AOF persistence & `requirepass`. |
| **Valkey** | In-Memory / Cache | `valkey` | `6379` | High-performance open source Linux Foundation Redis alternative. |
| **KeyDB** | In-Memory / Cache | `keydb` | `6379` | Multi-threaded Redis superset with high throughput. |
| **Dragonfly** | In-Memory / Cache | `dragonfly` | `6379` | Next-generation ultra-fast in-memory datastore. |
| **Memcached** | In-Memory / Cache | `memcached` | `11211` | Pure in-memory key-value caching system. |
| **MongoDB** | Document NoSQL | `mongodb` | `27017` | Document database with WiredTiger engine and auto-configured admin auth. |
| **FerretDB** | Document NoSQL | `ferretdb` | `27017` | MongoDB-compatible engine backed by SQLite or PostgreSQL. |
| **SurrealDB** | Multi-Model | `surrealdb` | `8000` | Document, Graph, Relational, and real-time WebSocket database with SurrealQL. |
| **Meilisearch** | Search Engine | `meilisearch` | `7700` | Ultra-fast typo-tolerant full-text search engine with REST API. |
| **Typesense** | Search Engine | `typesense` | `8108` | Typo-tolerant fast search engine with CORS support. |
| **Qdrant** | Vector AI DB | `qdrant` | `6333` | Vector similarity search engine for AI embeddings & semantic search. |
| **PocketBase** | Backend & SQLite | `pocketbase` | `8090` | Single-binary realtime backend with embedded SQLite & Admin UI. |
| **MinIO** | S3 Object Store | `minio` | `9000` | S3-compatible high-performance object storage with Web Console (`9001`). |
| **ClickHouse** | Columnar OLAP | `clickhouse` | `8123` | High-performance columnar database for real-time analytics & big data. |
| **InfluxDB** | Time-Series (TSDB)| `influxdb` | `8086` | Time-series database for metrics, events, and IoT monitoring. |
| **VictoriaMetrics** | Time-Series (TSDB)| `victoriametrics` | `8428` | High-efficiency Prometheus-compatible time-series database. |
| **Neo4j** | Graph Database | `neo4j` | `7474` | Leading Graph database with Cypher query language and Browser UI. |
| **Apache CouchDB** | Document NoSQL | `couchdb` | `5984` | JSON document database with HTTP/REST API and Fauxton dashboard. |
| **Custom** | Any Command | `custom` | Any | Execute any custom database daemon via `CUSTOM_COMMAND`. |

---

## Cryptographic Strong Password System

Database security requires non-guessable, high-entropy secrets. By default (`AUTO_GENERATE_CREDENTIALS=1`), if you leave `DB_PASSWORD` or `DB_ROOT_PASSWORD` as `auto` (or blank):

1. **High-Entropy Generation**: Uses `/dev/urandom` and OpenSSL cryptographic random byte streams to generate 32-character passwords (~190 bits of entropy).
2. **URL & Connection-String Safe**: Characters are selected to prevent breaking URI connection strings (`mysql://...`, `postgresql://...`, `redis://...`).
3. **Persisted Securely**:
   - `.db_credentials`: Read by the container on startup to ensure passwords never change on server reboot.
   - `credentials.txt`: Formatted human-readable summary of all connection parameters.
   - `.env`: Ready-to-use environment variables for your application.
   - File permissions are locked to `chmod 600` (read/write only by the server container).

```text
=====================================================
       POTENFYR STUDIOS - DATABASE CREDENTIALS       
=====================================================
Engine:        mariadb
Host (Local):  127.0.0.1
Host (Docker): 172.18.0.4
Port:          3306
Database Name: production
User:          dbuser
User Password: jK8!mQ9$xL2#vP4^wR7*tY1@zN6~bC3_
Root/Admin:    root
Root Password: Wq9*xT4#mK2!vL7$zR1^tY6@bC8~jP3_
=====================================================
```

---

## Quickstart & Setup

### 1. Import the Egg into Your Panel
1. Download [egg-database-multi.json](https://github.com/PotenFYR-Studios/Database-Eggs/blob/main/egg-database-multi.json).
2. In your panel Admin area:
   - **Pterodactyl / Jexactyl**: Go to **Admin → Nests → Create Nest (e.g. "Databases") → Import Egg** and upload `egg-database-multi.json`.
   - **Pelican Panel**: Go to **Admin → Eggs → Import** and select `egg-database-multi.json`.

### 2. Create a Server
- **Server Name**: `Production MariaDB` (or any desired name)
- **Egg**: `Multi Database`
- **Docker Image**: `ghcr.io/potenfyr-studios/database-eggs:latest`
- **Port Allocation**: Assign a port (e.g., `3306` for MySQL/MariaDB, `5432` for Postgres, `6379` for Redis, `27017` for Mongo, `9000` for MinIO).

### 3. Configure Variables
- Set `DATABASE_TYPE` (e.g. `mariadb`, `postgresql`, `redis`, `mongodb`, `surrealdb`, `pocketbase`, `meilisearch`, `minio`).
- Set `DB_NAME` and `DB_USER`.
- Leave `DB_PASSWORD` and `DB_ROOT_PASSWORD` as `auto` to generate unbreakable random credentials.

### 4. Start the Server
Click **Start**. The console will print the banner, provision the database, output connection details, and begin serving queries.

---

## Connecting to Your Database

### Command-Line (CLI)

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

### Connection URIs for Applications (.env)

```dotenv
# MySQL / MariaDB
DATABASE_URL=mysql://dbuser:PASSWORD@127.0.0.1:3306/database

# PostgreSQL
DATABASE_URL=postgresql://dbuser:PASSWORD@127.0.0.1:5432/database?sslmode=disable

# Redis
REDIS_URL=redis://:PASSWORD@127.0.0.1:6379/0

# MongoDB
MONGODB_URI=mongodb://dbuser:PASSWORD@127.0.0.1:27017/database?authSource=admin

# Meilisearch
MEILISEARCH_HOST=http://127.0.0.1:7700
MEILISEARCH_KEY=MASTER_KEY
```

---

## Egg Variables Reference

| Variable | Default | Description |
| :--- | :--- | :--- |
| `DATABASE_TYPE` | `mariadb` | Database engine to execute (`mariadb`, `mysql`, `postgresql`, `redis`, `valkey`, `mongodb`, `surrealdb`, `meilisearch`, `pocketbase`, `minio`, `qdrant`, etc.). |
| `DB_NAME` | `database` | Name of the primary database or schema created on first initialization. |
| `DB_USER` | `dbuser` | Application user created with full database privileges. |
| `DB_PASSWORD` | `auto` | Application user password. `auto` generates a high-entropy 32+ char secret. |
| `DB_ROOT_PASSWORD`| `auto` | Root, Superuser, Admin, or Master Key. `auto` generates an ultra-strong secret. |
| `AUTO_GENERATE_CREDENTIALS` | `1` | `1` = automatically generate and persist strong credentials on startup. |
| `EXTRA_ARGS` | `""` | Custom command-line arguments passed directly to the database daemon. |
| `EXTRA_URLS` | `""` | Extra files to download during installation (format: `dest/file\|url`). |
| `CUSTOM_COMMAND`| `""` | Custom shell command executed when `DATABASE_TYPE=custom`. |

---

## Repository Layout

```
Database-Eggs/
├── egg-database-multi.json         # Universal multi-database egg (import into panel)
├── eggs/                           # Individual dedicated standalone eggs
│   ├── egg-mariadb.json
│   ├── egg-postgresql.json
│   ├── egg-redis.json
│   ├── egg-mongodb.json
│   ├── egg-surrealdb.json
│   ├── egg-meilisearch.json
│   ├── egg-pocketbase.json
│   ├── egg-minio.json
│   └── egg-qdrant.json
├── Dockerfile                      # Universal runtime container image
├── entrypoint.sh                   # Container entrypoint & credential generator
├── run.sh                          # Universal database launcher & dispatcher
├── install.sh                      # Universal installation script
├── scripts/                        # Modular engine initialization handlers
│   ├── password-gen.sh             # Cryptographic secret & password generator
│   ├── db-init-mariadb.sh          # MariaDB & MySQL initialization handler
│   ├── db-init-postgres.sh         # PostgreSQL cluster initialization handler
│   ├── db-init-redis.sh            # Redis, Valkey, KeyDB, Dragonfly handler
│   ├── db-init-mongo.sh            # MongoDB & FerretDB auth handler
│   ├── db-init-surreal.sh          # SurrealDB handler
│   ├── db-init-search.sh           # Meilisearch, Typesense, Qdrant handler
│   └── db-init-storage.sh          # PocketBase, MinIO, InfluxDB handler
├── .github/workflows/
│   ├── docker-image.yml            # CI/CD: Builds multi-arch images (GHCR)
│   └── validate-eggs.yml           # CI: Validates egg JSON and shell syntax
├── LICENSE                         # MIT License
└── README.md                       # Documentation
```

---

## Docker Images (GHCR)

Pre-built multi-architecture Docker images (`linux/amd64` and `linux/arm64`) are continuously built and published to GitHub Container Registry:

- **Universal (All Engines)**: `ghcr.io/potenfyr-studios/database-eggs:latest`
- **MariaDB / MySQL**: `ghcr.io/potenfyr-studios/database-eggs:mariadb`
- **PostgreSQL**: `ghcr.io/potenfyr-studios/database-eggs:postgres`
- **Redis / Valkey**: `ghcr.io/potenfyr-studios/database-eggs:redis`
- **MongoDB**: `ghcr.io/potenfyr-studios/database-eggs:mongodb`
- **Search & Vector**: `ghcr.io/potenfyr-studios/database-eggs:search`

---

## Troubleshooting & FAQ

<details>
<summary><b>Where are my auto-generated credentials saved?</b></summary>

Credentials are saved in the root of your server files in three places:
1. `credentials.txt` (formatted overview)
2. `.env` (ready for application use)
3. `.db_credentials` (internal persistence store)

You can view them directly from the panel **File Manager**.
</details>

<details>
<summary><b>How do I change or reset my database password?</b></summary>

You can set your own custom password in the panel **Startup** tab under `DB_PASSWORD` or `DB_ROOT_PASSWORD`, or edit `.db_credentials` and restart your server.
</details>

<details>
<summary><b>How do I connect external applications (like a Discord bot or website)?</b></summary>

Ensure your server node's firewall allows incoming connections on the assigned database port, or use the container's internal Docker IP (`INTERNAL_IP`) if the application is hosted on the same node.
</details>

<details>
<summary><b>How do I backup my database?</b></summary>

You can create panel backups (which archive the `./data` directory) or use standard CLI dump tools:
- MariaDB/MySQL: `mysqldump -u root -p database > backup.sql`
- PostgreSQL: `pg_dump -U postgres database > backup.sql`
- MongoDB: `mongodump --out=./backup/`
- Redis: `redis-cli bgsave` (creates `dump.rdb`)
</details>

---

## License

This project is licensed under the [MIT License](LICENSE) — developed and maintained by **[PotenFYR Studios](https://github.com/PotenFYR-Studios)**.