<!-- markdownlint-disable -->
<div align="center">

<img src="https://capsule-render.vercel.app/api?type=waving&color=0:8b5cf6,50:ec4899,100:f97316&height=220&section=header&text=Database%20Eggs&fontSize=48&fontColor=ffffff&fontAlignY=34&desc=Universal%20Multi-Database%20Runtime%20%C2%B7%2050%2B%20Engines%20%C2%B7%20Zero-Leak%20Security&descSize=18&descAlignY=55&animation=twinkling" width="100%" alt="Database Eggs Banner"/>

[![Typing SVG](https://readme-typing-svg.demolab.com?font=Fira+Code:wght@600&size=19&pause=1200&color=8B5CF6&center=true&vCenter=true&width=800&lines=One+Universal+Egg+for+Pterodactyl%2C+Pelican%2C+Feather+%26+Docker;50%2B+Production-Ready+Databases%2C+Caches+%26+Search+Engines;Hardware-Aware+Dynamic+RAM+%26+CPU+Auto-Tuning;Strict+Version+Contracts+%26+Zero-Leak+Security;By+PotenFYR+Studios+%E2%80%94+support%40potenfyr.in)](https://github.com/PotenFYR-Studios/Database-Eggs)

<p align="center">
  <a href="https://potenfyr.in"><img src="https://img.shields.io/badge/Website-potenfyr.in-8b5cf6?style=for-the-badge&logo=googlechrome&logoColor=white&labelColor=1c1e26" alt="Website" /></a>
  <a href="https://discord.com/invite/zUaN2FPBec"><img src="https://img.shields.io/badge/Discord-Join%20us-5865F2?style=for-the-badge&logo=discord&logoColor=white&labelColor=1c1e26" alt="Discord" /></a>
  <a href="mailto:support@potenfyr.in"><img src="https://img.shields.io/badge/Email-support%40potenfyr.in-f97316?style=for-the-badge&logo=gmail&logoColor=white&labelColor=1c1e26" alt="Email" /></a>
  <a href="https://github.com/PotenFYR-Studios/Database-Eggs"><img src="https://komarev.com/ghpvc/?username=PotenFYR-Studios-Database-Eggs&color=ec4899&style=for-the-badge&label=VIEWS&labelColor=1c1e26" alt="Views" /></a>
</p>

[![Test Docker & Engines](https://github.com/PotenFYR-Studios/Database-Eggs/actions/workflows/test-docker.yml/badge.svg)](https://github.com/PotenFYR-Studios/Database-Eggs/actions/workflows/test-docker.yml)
[![Build Universal Image](https://github.com/PotenFYR-Studios/Database-Eggs/actions/workflows/docker-image.yml/badge.svg)](https://github.com/PotenFYR-Studios/Database-Eggs/actions/workflows/docker-image.yml)
[![Validate Eggs & Scripts](https://github.com/PotenFYR-Studios/Database-Eggs/actions/workflows/validate-eggs.yml/badge.svg)](https://github.com/PotenFYR-Studios/Database-Eggs/actions/workflows/validate-eggs.yml)
[![Databases & Engines](https://img.shields.io/badge/Databases%20%26%20Engines-50%2B%20Supported-orange?style=flat-square&logo=databricks)](https://github.com/PotenFYR-Studios/Database-Eggs#-supported-engines--tech-stack)
[![Docker Image](https://img.shields.io/badge/Docker%20Image-GHCR-blue?style=flat-square&logo=docker)](https://github.com/PotenFYR-Studios/Database-Eggs/pkgs/container/database-eggs)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](LICENSE)
[![Platforms](https://img.shields.io/badge/Architectures-amd64%20%7C%20arm64%20%7C%20arm%2Fv7%20%7C%20s390x%20%7C%20ppc64le%20%7C%20riscv64-darkgreen?style=flat-square)](https://github.com/PotenFYR-Studios/Database-Eggs)
[![Panels](https://img.shields.io/badge/Panels-Pterodactyl%20%7C%20Pelican%20%7C%20Feather%20%7C%20Wisp%20%7C%20Docker-9cf?style=flat-square)](https://github.com/PotenFYR-Studios/Database-Eggs)

<p align="center">
  <b>Deploy, tune, isolate, and version-switch any database with a single egg.</b><br>
  No bespoke images. No host root needed. Automated cryptographic credentials, hardware-aware performance tuning, and strict version regression guarantees.
</p>

<p align="center">
  <a href="#-quick-start-in-5-minutes">Quick Start</a> •
  <a href="#-supported-engines--tech-stack">Supported Engines</a> •
  <a href="#-architecture--lifecycle-flow">Architecture</a> •
  <a href="#-startup-variables">Variables</a> •
  <a href="#-security--hardening">Security</a> •
  <a href="#-activity-star-history--metrics">Live Graphs</a> •
  <a href="#-troubleshooting">Troubleshooting</a>
</p>

---

</div>

## 📑 Contents

<details open>
<summary><b>Click to expand / collapse contents</b></summary>

- [✨ Highlights & Core Philosophy](#-highlights--core-philosophy)
- [🚀 Quick Start in 5 Minutes](#-quick-start-in-5-minutes)
- [🧩 Architecture & Lifecycle Flow](#-architecture--lifecycle-flow)
- [🗄️ Supported Engines & Tech Stack](#-supported-engines--tech-stack)
  - [Engine Categories](#engine-categories)
  - [Audited Coverage & Scope](#audited-coverage--scope)
  - [Complete Engine Matrix](#complete-engine-matrix)
- [🎯 Version Resolution & Contract](#-version-resolution--contract)
  - [Version Selector Format](#version-selector-format)
  - [Strict Version Contract](#strict-version-contract)
- [🔌 Connecting to Your Database](#-connecting-to-your-database)
- [🔄 Safe Multi-Instance Version Switching](#-safe-multi-instance-version-switching)
- [⚙️ All Startup Variables](#-all-startup-variables)
  - [Core Settings](#core-settings)
  - [Behavior & Control](#behavior--control)
  - [Expert Knobs](#expert-knobs)
- [⚡ Performance Auto-Tuning](#-performance-auto-tuning)
- [🛡️ Security & Hardening Model](#-security--hardening-model)
- [💻 Architecture & OS Platform Support](#-architecture--os-platform-support)
- [🖥️ Panel Compatibility & Detection](#-panel-compatibility--detection)
- [🔧 Troubleshooting & Diagnostics](#-troubleshooting--diagnostics)
- [🧪 Testing Suite & CI/CD](#-testing-suite--cicd)
- [📈 Activity, Star History & Metrics](#-activity-star-history--metrics)
- [🤝 Community & Contributing](#-community--contributing)
- [📂 Repository Structure](#-repository-structure)
- [📜 License](#-license)

</details>

---

## ✨ Highlights & Core Philosophy

<table>
  <tr>
    <td width="50%">
      <h3>🎯 Single Universal Egg</h3>
      <p>Manage all your databases across Pterodactyl, Pelican, Feather, Wisp, and Docker using one single egg file and container image. Forget maintaining dozens of stale single-database eggs.</p>
    </td>
    <td width="50%">
      <h3>🔒 Zero-Leak Security</h3>
      <p>High-entropy passwords auto-generated via <code>openssl / urandom</code> on first boot, persisted with <code>chmod 600</code> in <code>.env</code>, sanitized from console and crash logs, with SCRAM-SHA-256 and auth enforced.</p>
    </td>
  </tr>
  <tr>
    <td width="50%">
      <h3>🚀 Auto-Tuning From Container Limits</h3>
      <p>Dynamic engine buffer and cache sizing computed from container memory limits (<code>SERVER_MEMORY</code>) and CPU quotas (WiredTiger, InnoDB, shared_buffers, maxmemory).</p>
    </td>
    <td width="50%">
      <h3>🛡️ Strict Version Contract</h3>
      <p>Pins like <code>18</code>, <code>11.4</code>, <code>7.0</code> are verified against running daemon binaries. If upstream fails or mismatches, boot halts with diagnostics—never a silent downgrade.</p>
    </td>
  </tr>
</table>

---

## 🚀 Quick Start in 5 Minutes

```mermaid
graph LR
    A[Download egg-database-multi.json] --> B[Import into Panel]
    B --> C[Set DATABASE_TYPE & DB_VERSION]
    C --> D[Allocate Port & Start]
    D --> E[Read Secure Credentials Card]
```

1. **Download the Egg**: Get [`egg-database-multi.json`](egg-database-multi.json).
2. **Import into Your Panel**:
   - **Pterodactyl / Jexactyl**: *Admin -> Nests -> Create Nest (or pick existing) -> Import Egg*
   - **Pelican**: *Admin -> Eggs -> Import*
   - **Feather / Wisp / Convoy / Docker**: Compatible with any Wings/Pterodactyl daemon.
3. **Create Server**: Select the egg and use the container image `ghcr.io/potenfyr-studios/database-eggs:latest`. Allocate your database port.
4. **Set Startup Variables**:
   - `DATABASE_TYPE`: e.g. `postgresql`, `mariadb`, `redis`, `mongodb`, `surrealdb`
   - `DB_VERSION`: e.g. `latest`, `18`, `11.4`, `7.0`, `8.0`
5. **Start Your Server**: On first boot, the engine is downloaded, tuned, provisioned, and prints the connection card:

```text
┌─────────────────────────────────────────────────────────────┐
│  ✓  DATABASE READY - SECURE CONNECTION DETAILS             │
├─────────────────────────────────────────────────────────────┤
│  Engine           : POSTGRESQL (v18.6)                     │
│  Host (Internal)  : 172.17.0.2                             │
│  Port             : 5432                                   │
│  Database         : testdb                                 │
│  Username         : testuser                               │
│  Total Users      : 1 (see .db-users/credentials)          │
│  User Password    : •••••••••••• [Protected]               │
│  Root Password    : •••••••••••• [Protected]               │
│  Credentials      : Saved in .env & Startup Environment    │
└─────────────────────────────────────────────────────────────┘

 Quick Connection Examples (Zero-Leak Security):
   CLI (Pre-Auth) : db-cli
   URI            : postgresql://testuser:<PASSWORD_IN_.ENV>@172.17.0.2:5432/testdb
```

> [!NOTE]
> All credentials are stored securely in `/home/container/.env` with file permissions `600`. Root & user secrets are permanently masked in stdout.

---

## 🧩 Architecture & Lifecycle Flow

```mermaid
flowchart TD
    subgraph Boot["1. Bootstrap & Detection"]
        Start([Container Start]) --> Entry["entrypoint.sh\nUID 988 Check & Signal Trap"]
        Entry --> Detect["Detect Host Panel\n(Pelican, Pterodactyl, Docker, etc.)"]
        Detect --> Secrets["Initialize High-Entropy Secrets\n(Persist mode 600 in .env)"]
    end

    subgraph Provision["2. Version Resolution & Provisioning"]
        Secrets --> Run["run.sh Dispatcher"]
        Run --> Res["scripts/install-db-version.sh\nMatch requested DB_VERSION"]
        Res -->|Cache Hit| Verify["Verify Binary & SHA256"]
        Res -->|Cache Miss| Fetch["Download from Upstream FastDL / CDN"]
        Fetch --> Verify
        Verify --> Contract{"STRICT_VERSION Check\nMatches requested major?"}
        Contract -->|No| Fail["Abort with Diagnostics & Suggestions"]
        Contract -->|Yes| Tune["scripts/performance-tuning.sh\nAuto-size Buffers from RAM & CPU"]
    end

    subgraph Service["3. Initialization & Supervision"]
        Tune --> Init["db-init-[engine].sh\nConfigure & Provision Auth/Users"]
        Init --> Daemon["Launch Daemon on 0.0.0.0:SERVER_PORT"]
        Daemon --> Supervise["Universal Supervisor & Signal Handler\n(Graceful SIGTERM / Panel Stop / STDIN)"]
    end
```

---

## 🗄️ Supported Engines & Tech Stack

<div align="center">

<p align="center">
  <img src="https://img.shields.io/badge/PostgreSQL-4169E1?style=for-the-badge&logo=postgresql&logoColor=white" alt="PostgreSQL" />
  <img src="https://img.shields.io/badge/MariaDB-003545?style=for-the-badge&logo=mariadb&logoColor=white" alt="MariaDB" />
  <img src="https://img.shields.io/badge/MySQL-4479A1?style=for-the-badge&logo=mysql&logoColor=white" alt="MySQL" />
  <img src="https://img.shields.io/badge/MongoDB-47A248?style=for-the-badge&logo=mongodb&logoColor=white" alt="MongoDB" />
  <img src="https://img.shields.io/badge/Redis-DC382D?style=for-the-badge&logo=redis&logoColor=white" alt="Redis" />
  <img src="https://img.shields.io/badge/SurrealDB-FF00A0?style=for-the-badge&logo=surrealdb&logoColor=white" alt="SurrealDB" />
  <img src="https://img.shields.io/badge/Meilisearch-FF4088?style=for-the-badge&logo=meilisearch&logoColor=white" alt="Meilisearch" />
  <img src="https://img.shields.io/badge/Qdrant-DC2626?style=for-the-badge&logo=qdrant&logoColor=white" alt="Qdrant" />
  <img src="https://img.shields.io/badge/MinIO-C72C48?style=for-the-badge&logo=minio&logoColor=white" alt="MinIO" />
  <img src="https://img.shields.io/badge/ClickHouse-FFCC01?style=for-the-badge&logo=clickhouse&logoColor=black" alt="ClickHouse" />
  <img src="https://img.shields.io/badge/InfluxDB-22ADF6?style=for-the-badge&logo=influxdb&logoColor=white" alt="InfluxDB" />
  <img src="https://img.shields.io/badge/Neo4j-008CC1?style=for-the-badge&logo=neo4j&logoColor=white" alt="Neo4j" />
</p>

### Complete Engine Category Directory (50+ Supported Engines & Services)

| Category | Supported Engines & Dispatched `DATABASE_TYPE` Values |
| :--- | :--- |
| **Relational & Distributed SQL** | `postgresql` `mariadb` `mysql` `cockroachdb` `yugabytedb` `tidb` `dolt` `sqlite` |
| **In-Memory & High-Speed Cache** | `redis` `valkey` `keydb` `dragonfly` `memcached` |
| **Document, Graph & Multi-Model** | `mongodb` `ferretdb` `arangodb` `orientdb` `ravendb` `couchdb` `neo4j` `dgraph` `surrealdb` `rethinkdb` `sqld` |
| **Vector, Full-Text & AI Search** | `meilisearch` `typesense` `qdrant` `elasticsearch` `opensearch` `solr` `manticoresearch` `milvus` `weaviate` `quickwit` |
| **Time-Series & Analytical OLAP** | `influxdb` `clickhouse` `victoriametrics` `questdb` |
| **Object & Blob Storage** | `minio` `seaweedfs` `garage` |
| **Consensus, Ledger & App Stores**| `pocketbase` `etcd` `immudb` `cassandra` `aerospike` |
| **Messaging & Ancillary Services** | `nats` `kafka` `prometheus` `consul` `loki` |
| **Extensible Custom Engine** | `custom` (Download & execute any engine tarball/binary via URL) |

</div>

### Audited Coverage & Architectural Implementation

- **51 Distinct Named Dispatch Targets**: 46 database/cache/search/storage engines plus 5 ancillary services, excluding aliases (`postgres`, `mongo`, `cockroach`, `yugabyte`, `manticore`, `weed`, `libsql`) and `custom`.
- **49 Explicit Installer Branches**: Automatic upstream binary resolution, SHA256 integrity verification, and runtime download into `/home/container/bin`.
- **System Distro Fallbacks**: MariaDB, PostgreSQL, Redis, Memcached, and SQLite are baked into the base image. Extended engines (MongoDB, SurrealDB, Meilisearch, Qdrant, Typesense, MinIO, VictoriaMetrics, etc.) are provisioned on-demand into `/home/container/bin` and cached across boots.

<details open>
<summary><b>🔍 Expand Full 50+ Engine Matrix (Ports, Defaults, & Highlights)</b></summary>

<br>

| Engine | `DATABASE_TYPE` | Example Versions | Default Port | Storage & Highlights |
| :--- | :--- | :--- | :--- | :--- |
| **PostgreSQL** | `postgresql` *(alias: `postgres`)* | `13` - `18`, `latest` | `5432` | SCRAM-SHA-256, auto-tuned `shared_buffers`, `pgvector`-ready |
| **MariaDB** | `mariadb` | `10.11`, `11.4`, `11.8` | `3306` | Official bintars, InnoDB auto-sizing, UTF8MB4 |
| **MySQL** | `mysql` | `8.0`, `8.4`, `latest` | `3306` | Official minimal tarballs, anonymous root purge |
| **CockroachDB** | `cockroachdb` *(alias: `cockroach`)* | `24.x`, `latest` | `26257` | Distributed SQL, single-node cluster, PostgreSQL wire-compatible |
| **YugabyteDB** | `yugabytedb` *(alias: `yugabyte`)* | `latest` | `5433` | Distributed SQL, PostgreSQL-compatible relational engine |
| **TiDB** | `tidb` | `7.5`, `latest` | `4000` | Cloud-native distributed HTAP database compatible with MySQL protocol |
| **Dolt** | `dolt` | `latest` | `3306` | Git-style versioned relational database with commit/branch/merge |
| **SQLite** | `sqlite` | distro package | *Embedded / file* | Transactional embedded database, zero-config, optional Litestream |
| **Redis** | `redis` | `6.2` - `7.4`, `latest` | `6379` | RDB+AOF persistence, memory limits, multi-core io-threads |
| **Valkey** | `valkey` | `7.2`, `8.0`, `latest` | `6379` | Open-source Redis fork with complete protocol & CLI parity |
| **KeyDB** | `keydb` | `latest` | `6379` | Multi-threaded high-throughput alternative to Redis |
| **Dragonfly** | `dragonfly` | `latest` | `6379` | Modern ultra-fast multi-threaded in-memory store |
| **Memcached** | `memcached` | distro default | `11211` | High-performance distributed memory object caching |
| **MongoDB** | `mongodb` *(alias: `mongo`)* | `6.0`, `7.0`, `8.0` | `27017` | WiredTiger container cache tuning, `mongosh` companion auto-provisioning |
| **FerretDB** | `ferretdb` | `latest` | `27017` | MongoDB wire-compatibility layer on top of PostgreSQL/SQLite |
| **SurrealDB** | `surrealdb` | `1.x`, `2.x`, `latest` | `8000` | Multi-model realtime database with REST, GraphQL & WebSocket APIs |
| **ArangoDB** | `arangodb` | `3.12`, `latest` | `8529` | Multi-model database (document, graph, key-value) with AQL |
| **OrientDB** | `orientdb` | `latest` | `2424` | Multi-model graph-document database with automated JRE companion |
| **RavenDB** | `ravendb` | `latest` | `8080` | ACID document database with high availability and fast querying |
| **CouchDB** | `couchdb` | custom / supplied | `5984` | Schema-free JSON document database with HTTP/JSON API |
| **Neo4j** | `neo4j` | `5.x`, `latest` | `7687` | Native graph database with Cypher query language (Bolt + HTTP 7474) |
| **Dgraph** | `dgraph` | `latest` | `8080` | Native distributed GraphQL graph database (HTTP + gRPC 9080) |
| **RethinkDB** | `rethinkdb` | `latest` | `28015` | Realtime database pushing concurrency and changefeeds to clients |
| **libSQL (sqld)** | `sqld` *(alias: `libsql`)* | `latest` | `8080` | Server-side networked fork of SQLite with remote replication |
| **Meilisearch** | `meilisearch` | `1.x`, `latest` | `7700` | Lightning-fast typo-tolerant search engine, Master Key auth |
| **Typesense** | `typesense` | `26.0`, `27.0`, `latest` | `8108` | Fast in-memory typo-tolerant search engine |
| **Qdrant** | `qdrant` | `latest`, exact tag | `6333` | Vector similarity search engine with payload filtering & web UI |
| **Elasticsearch** | `elasticsearch` | `8.x`, `latest` | `9200` | Distributed search & analytics engine with loopback security isolation |
| **OpenSearch** | `opensearch` | `2.x`, `latest` | `9200` | Community-driven distributed search & analytics suite |
| **Solr** | `solr` | `latest` | `8983` | Apache Lucene-based enterprise search platform |
| **Manticore Search**| `manticoresearch` *(alias: `manticore`)* | `latest` | `9306` | High-performance search database with MySQL protocol listener |
| **Milvus** | `milvus` | `latest` | `19530` | Scalable vector database for AI embedding search with embedded etcd |
| **Weaviate** | `weaviate` | `latest` | `8080` | Open-source AI-first vector search engine with hybrid search |
| **Quickwit** | `quickwit` | `latest` | `7280` | Sub-second distributed search and log analytics on cloud storage |
| **ClickHouse** | `clickhouse` | `23.x`, `24.x`, `latest` | `8123` | Blazing-fast columnar OLAP database for real-time analytics |
| **InfluxDB** | `influxdb` | `1.8`, `2.7`, `latest` | `8086` | Time-series database optimized for metrics, events, and IoT |
| **VictoriaMetrics** | `victoriametrics` | `latest` | `8428` | Prometheus-compatible, high-efficiency time-series metrics store |
| **QuestDB** | `questdb` | `latest` | `9000` | High-performance time-series database with SQL & Postgres wire (8812) |
| **MinIO** | `minio` | `latest` | `9000` | S3-compatible high-performance enterprise object storage (Console 9001) |
| **SeaweedFS** | `seaweedfs` *(alias: `weed`)* | `latest` | `9333` | Fast distributed blob & object storage with POSIX and S3 support (8333) |
| **Garage** | `garage` | `latest` | `3900` | Lightweight distributed S3 storage built for edge & self-hosting |
| **PocketBase** | `pocketbase` | `latest` | `8090` | Single-binary backend with embedded database & realtime Admin UI |
| **Etcd** | `etcd` | `3.5`, `latest` | `2379` | Distributed reliable key-value store for shared configuration |
| **Immudb** | `immudb` | `latest` | `3322` | High-speed immutable database with cryptographic verification |
| **Cassandra** | `cassandra` | `4.1`, `5.0`, `latest` | `9042` | Highly scalable distributed wide-column NoSQL database |
| **Aerospike** | `aerospike` | `7.x`, `latest` | `3000` | Real-time distributed NoSQL data store for sub-millisecond access |
| **NATS** | `nats` | `latest` | `4222` | Ultra-lightweight cloud native messaging system with JetStream |
| **Kafka** | `kafka` | `latest` | `9092` | Distributed event streaming platform with KRaft mode support |
| **Prometheus** | `prometheus` | `latest` | `9090` | Systems monitoring and alerting toolkit with time-series metrics |
| **Consul** | `consul` | `latest` | `8500` | Distributed service mesh, health check, and key-value platform |
| **Loki** | `loki` | `latest` | `3100` | Horizontally scalable, highly available log aggregation system |
| **Custom Engine** | `custom` | Direct URL / Binary | *Configurable* | Bring-your-own engine binary or archive with pre-run hooks |

</details>

---

## 🎯 Version Resolution & Contract

### Version Selector Format

You can pass standard aliases, semantic series, exact patch versions, or even direct URLs in `DB_VERSION`:

| Value Format | Example | Resolution Behavior |
| :--- | :--- | :--- |
| `latest` *(default)* | `latest` | Resolves newest stable release from upstream on each cold boot |
| **Major Series** | `18`, `7.0`, `11.4` | Pins to series and downloads the newest validated patch (e.g. 7.0.40) |
| **Exact Patch** | `8.0.40`, `11.4.5` | Pins precisely to that binary artifact |
| **Pre-release** | `beta`, `edge`, `rc` | Resolves newest pre-release tag; falls back to stable if unavailable |
| **Direct URL** | `https://...` | Downloads tarball or binary directly from your CDN/mirror |

### Strict Version Contract

With `STRICT_VERSION=1` (default):
- After downloading or resolving the binary, the runtime runs `--version` on the real executable.
- The reported version string is verified against your requested series.
- If an upstream asset fails to match, execution **halts immediately** with full diagnostic guidance. It will **never** silently downgrade your engine.
- Set `STRICT_VERSION=0` if you want warn-and-proceed semantics for bleeding-edge custom binaries.

---

## 🔌 Connecting to Your Database

Every successful boot prints an interactive connection card and exports connection details to `/home/container/.env`:

| Engine | In-Container CLI Shortcut | Connection String Format |
| :--- | :--- | :--- |
| **PostgreSQL** | `db-cli` | `postgresql://USER:PASSWORD@HOST:PORT/DATABASE` |
| **MariaDB / MySQL** | `db-cli` | `mysql://USER:PASSWORD@HOST:PORT/DATABASE` |
| **Redis / Valkey** | `db-cli` | `redis://:PASSWORD@HOST:PORT` |
| **MongoDB** | `db-cli` | `mongodb://USER:PASSWORD@HOST:PORT/DATABASE?authSource=admin` |
| **Meilisearch** | `curl` with Bearer key | `http://HOST:PORT` with `Authorization: Bearer <MASTER_KEY>` |
| **MinIO** | AWS CLI / S3 SDKs | Endpoint `http://HOST:PORT`, Key: `DB_USER`, Secret: `DB_ROOT_PASSWORD` |

---

## 🔄 Safe Multi-Instance Version Switching

All database data is partitioned by engine and major series inside `data/<engine>/<series>/`:

```text
data/
├── postgresql/
│   ├── 16/                 # PostgreSQL 16 cluster
│   └── 18/                 # Fresh PostgreSQL 18 cluster
├── mongodb/
│   └── 7/                  # MongoDB 7.0 WiredTiger dbPath
└── redis/
    └── default/            # dump.rdb and appendonly dir
```

- **Seamless Patch Upgrades**: Minor updates (e.g., `18.1` -> `18.2`) reuse the existing instance cleanly.
- **Breaking Major Upgrades**: Changing `DB_VERSION` from `16` to `18` automatically creates a fresh namespace `data/postgresql/18/`. **Old data is never deleted.**
- **PostgreSQL Data Mismatch Shield**: Attempting to boot PostgreSQL 18 on a PG 16 data directory renders an actionable migration guide in the console with safe upgrade options.

---

## ⚙️ All Startup Variables

### Core Settings

| Variable | Default | Description |
| :--- | :--- | :--- |
| `DATABASE_TYPE` | `mariadb` | Database engine to dispatch (e.g. `postgresql`, `redis`, `mongodb`) |
| `DB_VERSION` | `latest` | Version channel (`latest`), major series (`18`), exact patch (`7.0.40`), or URL |
| `DB_NAME` | `testdb` | Primary database name created on initial boot |
| `DB_USER` | `testuser` | Application user account created with full permissions on `DB_NAME` |
| `DB_PASSWORD` | `auto` | Application user password (`auto` generates 32-character crypto secret) |
| `DB_ROOT_PASSWORD`| `auto` | Root/admin password (`auto` generates 32-character crypto secret) |
| `AUTO_GENERATE_CREDENTIALS` | `1` | Automatically generate secure passwords if not explicitly specified |

### Behavior & Control

| Variable | Default | Description |
| :--- | :--- | :--- |
| `STRICT_VERSION` | `1` | Enforce exact version verification against daemon binary before start |
| `PERFORMANCE_TUNING` | `1` | Automatically size buffers, caches, and threads according to container RAM |
| `SECURITY_HARDENING` | `1` | Enable SCRAM auth, purge demo accounts, disable debug endpoints |
| `SAVE_TO_ENV` | `1` | Persist connection details into `/home/container/.env` (`chmod 600`) |
| `EXTRA_RUNTIMES` | *(empty)* | Comma-separated companions to inject (e.g. `python,nodejs,bun,mongosh,litestream`) |
| `EXTRA_ARGS` | *(empty)* | Raw command-line arguments appended directly to the daemon launch command |
| `DATA_DIR` | *(auto)* | Custom data directory override (bypasses automatic multi-instance manager) |

### Expert Knobs

| Variable | Default | Description |
| :--- | :--- | :--- |
| `BIND_ADDRESS` | `0.0.0.0` | Primary network listen interface |
| `SKIP_VERSION_INSTALL` | `0` | Air-gapped mode: skip network downloads and boot existing binaries |
| `ALLOW_SYSTEM_APT` | `0` | Allow root package updates if running in non-isolated custom Docker environments |
| `PF_CURL_UA` | `PotenFYR-Installer/1.0` | User-Agent header passed during upstream probes and artifact downloads |
| `PF_DEBUG` | `0` | Enable verbose trace logging across launcher and init scripts |

---

## ⚡ Performance Auto-Tuning

When `PERFORMANCE_TUNING=1`, the runtime inspects `SERVER_MEMORY` and allocated CPU cores to optimize performance automatically:

- **MariaDB & MySQL**:
  - `innodb_buffer_pool_size`: 60% of container memory
  - `innodb_log_file_size`: 25% of pool size
  - `innodb_flush_log_at_trx_commit`: 2 (high-performance write buffer)
- **PostgreSQL**:
  - `shared_buffers`: 25% of total memory
  - `effective_cache_size`: 75% of total memory
  - `work_mem`: dynamically scaled to connection quotas
- **MongoDB**:
  - `wiredTiger.engineConfig.cacheSizeGB`: dynamically sized from memory limits
  - Snappy block compression enabled by default
- **Redis & Valkey**:
  - `maxmemory`: 85% of container RAM limit
  - `io-threads`: scaled to allocated CPU cores

> [!TIP]
> Custom configuration files placed in `config/` (such as `config/mongod.conf`, `config/my.cnf`, or `config/postgresql.conf`) are always preserved.

---

## 🛡️ Security & Hardening Model

- **Least Privilege Execution**: Fully compliant with Pterodactyl container UID `988:988`. Never requires root inside the server container.
- **Credential Storage Isolation**: Secrets are written exclusively to `/home/container/.env` with strict `0600` permissions. Sockets are restricted to `/tmp/.db-sockets`.
- **Zero-Leak Logs**: Passwords, auth tokens, and API secrets are intercepted and masked across standard output and crash diagnostics.
- **Strict Authentication**: Remote password-less root logins are disabled across SQL and NoSQL engines. PostgreSQL enforces SCRAM-SHA-256.

---

## 💻 Architecture & OS Platform Support

The universal container is built on **Ubuntu 22.04 LTS (glibc)** and targets the following multi-architecture platforms:

<div align="center">

| Architecture | Platform String | Runtime Status | Supported Engine Distribution |
| :---: | :---: | :---: | :--- |
| **x86_64** | `linux/amd64` | **Tier 1 Verified** | All 51 engines & companions available |
| **ARM64** | `linux/arm64` | **Tier 1 Verified** | PostgreSQL, MariaDB, Redis, MongoDB, SurrealDB, Meilisearch, etc. |
| **ARMv7** | `linux/arm/v7` | Supported | Distro SQL, Redis, and portable runtime binaries |
| **IBM Z** | `linux/s390x` | Supported | Base platform packages and supported upstreams |
| **POWER8/9** | `linux/ppc64le` | Supported | Base platform packages and supported upstreams |
| **RISC-V** | `linux/riscv64` | Experimental | Distro packages & community build targets |

</div>

---

## 🖥️ Panel Compatibility & Detection

The runtime auto-detects panel environments through filesystem and environment fingerprints:

<div align="center">

| Panel | Auto-Detected | Identification Fingerprint |
| :--- | :---: | :--- |
| **Pelican** | Yes | `P_SERVER_UUID` and Wings v2 environment layout |
| **Pterodactyl** | Yes | Classic `/home/container` mount and Wings daemon vars |
| **Feather Panel** | Yes | Feather platform tokens and environment attributes |
| **Wisp Panel** | Yes | Wisp daemon markers and volume mappings |
| **Docker / Compose** | Yes | Native standalone container mode |
| **Kubernetes / OpenShift** | Yes | Downward API, dynamic high-UID execution |

</div>

---

## 🔧 Troubleshooting & Diagnostics

Whenever an issue occurs, full debug details are written to isolated log files before exiting:

| Log Path | Purpose & Contents |
| :--- | :--- |
| `logs/startup_error.log` | Crash reports, stack traces, and environment snapshots |
| `logs/installer.log` | Download traces, HTTP probe responses, and extraction records |
| `logs/mongod.log` / `logs/mariadb.log` | Engine daemon output and internal runtime events |

### Common Symptoms & Solutions

> [!WARNING]
> **Strict version verification failed**: Check `logs/installer.log`. Ensure the host has outbound internet connectivity to upstream distribution CDNs, or adjust `DB_VERSION` to an available release.

> [!TIP]
> **Could not bind to port**: Verify in your panel that the allocated server port matches `SERVER_PORT`. Secondary ports (such as MinIO console) bind to loopback unless explicitly assigned.

---

## 🧪 Testing Suite & CI/CD

Our test suite replicates Pterodactyl Wings container conditions (`-u 988:988`, strict volume mounts, memory constraints) and asserts startup, client readiness, credential isolation, and graceful shutdown signal traps:

```bash
# Run the integration test suite locally
./tests/test-docker.sh

# Run only specific engines (e.g. MongoDB and PostgreSQL)
TEST_ENGINES="mongodb,postgresql" ./tests/test-docker.sh

# Run self-test harness verification
./tests/test-docker.sh --self-test
```

---

## 📂 Repository Structure

```text
├── egg-database-multi.json       # Pterodactyl / Pelican universal egg definition
├── Dockerfile                    # Multi-stage universal container definition
├── entrypoint.sh                 # Container bootstrap, panel detection & secret init
├── run.sh                        # Engine dispatcher, instance router & lifecycle
├── scripts/
│   ├── install-db-version.sh     # Engine version installer & candidate resolver
│   ├── companion-loader.sh       # On-demand companion runtime injector
│   ├── performance-tuning.sh     # Dynamic RAM/CPU resource auto-tuner
│   ├── db-init-postgres.sh       # PostgreSQL setup and user management
│   ├── db-init-mariadb.sh        # MariaDB & MySQL configuration handler
│   ├── db-init-mongo.sh          # MongoDB & FerretDB initialization
│   ├── db-init-redis.sh          # Redis & Valkey handler
│   ├── db-init-search.sh         # Meilisearch, Typesense & Qdrant handler
│   ├── db-init-storage.sh        # MinIO & Object Storage handler
│   └── lib-diagnostics.sh        # Crash dumps, logging & error reporting
├── tests/
│   ├── test-docker.sh            # Pterodactyl-identical Docker integration test
│   ├── panel-test.sh             # Panel lifecycle and signal handling test
│   └── test-users.sh             # Multi-user reconciliation test harness
└── .github/workflows/
    ├── test-docker.yml           # GitHub Actions engine integration suite
    ├── docker-image.yml          # Multi-arch GHCR build & release pipeline
    └── validate-eggs.yml         # JSON schema & bash syntax verification
```

---

## 📈 Activity, Star History & Metrics

<div align="center">

<p align="center">
  <a href="https://github.com/PotenFYR-Studios/Database-Eggs/stargazers"><img src="https://img.shields.io/github/stars/PotenFYR-Studios/Database-Eggs?style=flat-square&logo=github&labelColor=1c1e26&color=eac54f" alt="GitHub Stars" /></a>
  <a href="https://github.com/PotenFYR-Studios/Database-Eggs/network/members"><img src="https://img.shields.io/github/forks/PotenFYR-Studios/Database-Eggs?style=flat-square&logo=github&labelColor=1c1e26&color=0078d7" alt="GitHub Forks" /></a>
  <a href="https://github.com/PotenFYR-Studios/Database-Eggs/issues"><img src="https://img.shields.io/github/issues/PotenFYR-Studios/Database-Eggs?style=flat-square&logo=github&labelColor=1c1e26&color=db61a2" alt="GitHub Issues" /></a>
  <a href="https://github.com/PotenFYR-Studios/Database-Eggs/pulls"><img src="https://img.shields.io/github/issues-pr/PotenFYR-Studios/Database-Eggs?style=flat-square&logo=github&labelColor=1c1e26&color=2ea043" alt="GitHub Pull Requests" /></a>
  <a href="https://github.com/PotenFYR-Studios/Database-Eggs/graphs/contributors"><img src="https://img.shields.io/github/contributors/PotenFYR-Studios/Database-Eggs?style=flat-square&labelColor=1c1e26&color=8957e5" alt="Contributors" /></a>
  <a href="https://github.com/PotenFYR-Studios/Database-Eggs/commits/main"><img src="https://img.shields.io/github/last-commit/PotenFYR-Studios/Database-Eggs?style=flat-square&logo=git&labelColor=1c1e26&color=2ea043" alt="Last Commit" /></a>
</p>

### 🌟 Real-time Star History

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=PotenFYR-Studios/Database-Eggs&type=Date&theme=dark">
  <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=PotenFYR-Studios/Database-Eggs&type=Date&theme=light">
  <img src="https://api.star-history.com/svg?repos=PotenFYR-Studios/Database-Eggs&type=Date&theme=light" alt="Database Eggs Star History Graph" width="100%">
</picture>

<sub>📈 Live graph rendered by <a href="https://star-history.com">star-history.com</a>. Updates in real-time as users star the repository.</sub>

</div>

---

## 🤝 Community & Contributing

We welcome contributions, feature suggestions, and engine feedback from the community!

- **Found a bug or missing engine feature?** [Open an issue](https://github.com/PotenFYR-Studios/Database-Eggs/issues) on GitHub.
- **Want to contribute code or test scenarios?** Submit a [Pull Request](https://github.com/PotenFYR-Studios/Database-Eggs/pulls).
- **Need help with your panel setup?** Join our vibrant community on Discord!

<div align="center">

[![Discord Server](https://img.shields.io/badge/Discord-Community_Server-5865F2?style=for-the-badge&logo=discord&logoColor=white&labelColor=1c1e26)](https://discord.com/invite/zUaN2FPBec)
[![Support Server](https://img.shields.io/badge/Support-Discord_Server-5865F2?style=for-the-badge&logo=discord&logoColor=white&labelColor=1c1e26)](https://discord.com/invite/PRJASTKqwD)
[![Website](https://img.shields.io/badge/Official_Website-potenfyr.in-8b5cf6?style=for-the-badge&logo=googlechrome&logoColor=white&labelColor=1c1e26)](https://potenfyr.in)

</div>

---

## 📜 License

This project is licensed under the [MIT License](LICENSE).

<div align="center">

<p><b>Crafted with passion by <a href="https://github.com/PotenFYR-Studios">PotenFYR Studios</a></b><br>
<i>Support & Inquiries: <a href="mailto:support@potenfyr.in">support@potenfyr.in</a></i></p>

<img src="https://capsule-render.vercel.app/api?type=waving&color=0:f97316,50:ec4899,100:8b5cf6&height=120&section=footer&text=Made%20with%20%E2%9D%A4%EF%B8%8F%20by%20PotenFYR%20Studios&fontSize=22&fontColor=ffffff&animation=twinkling" width="100%" alt="PotenFYR footer banner"/>

</div>
