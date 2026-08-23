# Database Eggs

One egg. Every database. Every version. Every panel. Installs, auto-tunes, secures, and runs **55+ database engines** at **any upstream version** with everything isolated inside your container. Cryptographically strong secrets, performance auto-tuning, automatic panel detection, deep crash diagnostics, non-destructive version switching, and compatibility across **Pterodactyl, Pelican, Feather, Wisp, Convoy, Cytopanel, Jexactyl, PufferPanel, AMP**, Kubernetes/OpenShift, and native Docker.

[![GitHub License](https://img.shields.io/github/license/PotenFYR-Studios/Database-Eggs?style=for-the-badge&color=blue)](LICENSE)
[![Docker Image](https://img.shields.io/badge/Docker-GHCR-blue?style=for-the-badge&logo=docker)](https://github.com/PotenFYR-Studios/Database-Eggs/pkgs/container/database-eggs)
[![Panels](https://img.shields.io/badge/Panels-Pterodactyl%20%7C%20Pelican%20%7C%20Feather%20%7C%20Wisp-brightgreen?style=for-the-badge)](https://github.com/PotenFYR-Studios/Database-Eggs)

---

## Contents

**Getting Started**
1. [What Is This?](#what-is-this)
2. [Quick Start in 5 Minutes](#quick-start-in-5-minutes)
3. [Choosing Your Database](#choosing-your-database)
4. [Picking a Version](#picking-a-version)

**Everyday Use**
5. [Connecting to Your Database](#connecting-to-your-database)
6. [Switching Engines or Versions Safely](#switching-engines-or-versions-safely)
7. [All Startup Variables](#all-startup-variables)

**Reliability & Operations**
8. [Performance Auto-Tuning](#performance-auto-tuning)
9. [Security Model](#security-model)
10. [Architecture & OS Support](#architecture--os-support)
11. [Panel Compatibility & Detection](#panel-compatibility--detection)
12. [Troubleshooting Guide](#troubleshooting-guide)

**Expert Zone**
13. [Advanced Configuration](#advanced-configuration)
14. [Custom Engines & Binary URLs](#custom-engines--binary-urls)
15. [Air-Gapped / Offline Fleets](#air-gapped--offline-fleets)
16. [Testing Suite & CI/CD](#testing-suite--cicd)
17. [Repository Layout](#repository-layout)
18. [License](#license)

---

## What Is This?

A single egg plus a single container image that runs **any** of 55+ database engines at **any** released version:

- You set two variables: `DATABASE_TYPE` and `DB_VERSION`.
- On boot, the runtime downloads exactly that engine/version **into your own server folder** (nothing touches the host), configures tuned settings, provisions users/databases with strong random passwords, and starts it.
- Change either variable anytime: old data is never deleted; new instances are created alongside and the console tells you where everything lives.

No per-database eggs. No image rebuilds for new versions. No root required.

---

## Quick Start in 5 Minutes

1. Download [`egg-database-multi.json`](egg-database-multi.json).
2. Import into your panel:
   - *Pterodactyl / Jexactyl*: Admin -> Nests -> Create Nest -> Import Egg
   - *Pelican*: Admin -> Eggs -> Import
   - *Any wings-compatible panel*: identical flow
3. Create a server using the egg with image `ghcr.io/potenfyr-studios/database-eggs:latest`. Allocate one port.
4. Set two variables:
   - `DATABASE_TYPE` = e.g. `postgresql`, `mariadb`, `redis`, `mongodb`
   - `DB_VERSION` = e.g. `latest`, `18`, `11.4`, `8.0`
5. Start. First boot downloads the engine, then prints your connection card:

```text
Database Engine    : POSTGRESQL (v18.6)
Listen Address     : 0.0.0.0:5432
Allocated Memory   : 1024 MB
Detected Panel     : pelican
Security Mode      : Strict Cryptographic / SCRAM / Auth
```

Credentials appear in the console (masked), in `.env` (mode 600), and in startup environment variables.

---

## Choosing Your Database

| Category | Values for `DATABASE_TYPE` |
| :--- | :--- |
| SQL | `mariadb` `mysql` `postgresql` `cockroachdb` `yugabytedb` `tidb` `dolt` |
| Document | `mongodb` `ferretdb` `arangodb` `orientdb` `ravendb` `couchdb` |
| In-Memory/KV | `redis` `valkey` `keydb` `dragonfly` `memcached` `etcd` `nats` `immudb` |
| Vector/Search | `meilisearch` `typesense` `qdrant` `elasticsearch` `opensearch` `solr` `manticoresearch` `milvus` `weaviate` `quickwit` |
| Time-Series | `influxdb` `clickhouse` `victoriametrics` `questdb` |
| Object Storage | `minio` `seaweedfs` `garage` |
| Graph/Ledger | `neo4j` `dgraph` `surrealdb` |
| Wide-Column/Misc | `cassandra` `aerospike` `rethinkdb` `sqld` `sqlite` |
| Anything else | `custom` |

<details>
<summary><strong>Full Engine Matrix (ports + highlights)</strong></summary>

| Engine | Value | Version examples | Port | Highlights |
| :--- | :--- | :--- | :--- | :--- |
| MariaDB | `mariadb` | `11.4`, `11.8`, `10.11` | 3306 | Official bintars, InnoDB tuned |
| MySQL | `mysql` | `8.0`, `8.4` | 3306 | Official minimal tarballs |
| PostgreSQL | `postgresql` | `13`-`18`, exact | 5432 | Standalone builds, SCRAM, pgvector-ready |
| CockroachDB | `cockroachdb` | `latest`, `24.3` | 26257 | Single-node distributed SQL |
| YugabyteDB | `yugabytedb` | `latest` | 5433 | PG-compatible distributed SQL |
| TiDB | `tidb` | `latest`, `7.5` | 4000 | MySQL-compatible HTAP |
| Dolt | `dolt` | `latest` | 3306 | Git-style versioned SQL |
| MongoDB | `mongodb` | `6.0`, `7.0`, `8.0` | 27017 | WiredTiger, auto provisioning |
| FerretDB | `ferretdb` | `latest` | 27017 | Mongo protocol on SQLite/PG |
| ArangoDB | `arangodb` | `latest`, `3.12` | 8529 | Multi-model + AQL |
| OrientDB | `orientdb` | `latest` | 2424 | Graph/document (JRE injected) |
| RavenDB | `ravendb` | `latest` | 8080 | ACID documents |
| Redis | `redis` | `6.2`-`7.4` | 6379 | RDB+AOF, io-threads |
| Valkey | `valkey` | `latest` | 6379 | Baked binary, instant start |
| KeyDB | `keydb` | `latest` | 6379 | Multithreaded (source build) |
| Dragonfly | `dragonfly` | `latest` | 6379 | Modern ultra-fast |
| Etcd | `etcd` | `latest`, `3.5` | 2379 | v3 API single-node |
| NATS | `nats` | `latest` | 4222 | JetStream included |
| Immudb | `immudb` | `latest` | 3322 | Tamper-proof ledger |
| Meilisearch | `meilisearch` | `latest`, `1.x` | 7700 | Typo-tolerant search |
| Typesense | `typesense` | `latest`, `27.0` | 8108 | Fast search |
| Qdrant | `qdrant` | `latest` | 6333 | Vector search + dashboard |
| Elasticsearch | `elasticsearch` | `8.x`, `9.x` | 9200 | Bundled JDK, transport loopback-isolated |
| OpenSearch | `opensearch` | `2.x` | 9200 | Security plugin toggleable |
| Solr | `solr` | `latest` | 8983 | Lucene platform |
| Manticore | `manticoresearch` | `latest` | 9306 | MySQL protocol listener |
| Milvus | `milvus` | `latest` | 19530 | Embedded-etcd vector DB |
| Weaviate | `weaviate` | `latest` | 8080 | GraphQL vector hybrid |
| Quickwit | `quickwit` | `latest` | 7280 | Log analytics search |
| InfluxDB | `influxdb` | `latest`, `2.7` | 8086 | Time-series platform |
| ClickHouse | `clickhouse` | `latest`, `24.x` | 8123 | Columnar OLAP |
| VictoriaMetrics | `victoriametrics` | `latest` | 8428 | Prometheus-compatible |
| QuestDB | `questdb` | `latest` | 9000 | Time-series + PG wire |
| MinIO | `minio` | `latest` | 9000 | S3 API |
| SeaweedFS | `seaweedfs` | `latest` | 9333 | Distributed object store |
| Garage | `garage` | `latest` | 3900 | Lightweight S3 |
| Neo4j | `neo4j` | `latest`, `5.x` | bolt | Cypher graph DB |
| Dgraph | `dgraph` | `latest` | 8080 | GraphQL graph DB |
| SurrealDB | `surrealdb` | `latest`, `2.x` | 8000 | Multi-model realtime |
| Cassandra | `cassandra` | `4.1`, `5.0` | 9042 | Wide-column CQL |
| Aerospike | `aerospike` | `latest`, `7.x` | 3000 | Real-time NoSQL |
| RethinkDB | `rethinkdb` | `latest` | 28015 | Changefeeds |
| libSQL | `sqld` | `latest` | 8080 | Server-side SQLite |
| PocketBase | `pocketbase` | `latest` | 8090 | Backend + admin UI |
| Custom | `custom` | any URL | any | Bring your own |

</details>

---

## Picking a Version

| You set | You get |
| :--- | :--- |
| `latest` *(default)* | Newest stable release, resolved fresh upstream every boot |
| `stable` | Same as latest |
| `beta` / `alpha` / `nightly` / `edge` | Newest prerelease of that channel, else falls back to stable with a notice |
| `18` | Newest patch of major 18 |
| `11.4` | Newest patch of series 11.4 |
| `8.0.45` | Exactly that build |
| `v2.1.0` | Tag form accepted |
| `https://...` | Direct download URL (Custom Engines) |

Invalid values are rejected immediately with usage guidance. The server never boots "something close".

### Strict Version Contract

With `STRICT_VERSION=1` (default), after install the runtime runs the actual binary and compares its reported version against your request. Match -> boot proceeds with the verified number printed. Mismatch -> hard fail with remediation steps, never a silent older version. Set `STRICT_VERSION=0` for warn-and-continue semantics.

---
## Connecting to Your Database

The console prints a connection card every successful boot. Common patterns:

| Engine | Inside container (`db-cli`) | From your app |
| :--- | :--- | :--- |
| MariaDB/MySQL | `mariadb -h 127.0.0.1 -P PORT -u USER -p DB` | `mysql://USER:PASS@host:PORT/DB` |
| PostgreSQL | `psql -h 127.0.0.1 -p PORT -U postgres -d DB` | `postgresql://USER:PASS@host:PORT/DB` |
| Redis/Valkey | `redis-cli -p PORT -a PASS` | `redis://:PASS@host:PORT` |
| MongoDB | `mongosh "mongodb://USER:PASS@127.0.0.1:PORT/DB?authSource=admin"` | same URI |
| Meilisearch | curl + `Authorization: Bearer KEY` | `http://host:PORT` |
| MinIO/Garage | any S3 SDK, keys = `DB_USER`/`DB_ROOT_PASSWORD` | `http://host:PORT` |

Credential lifecycle: `auto` (default) generates a 32-char high-entropy secret on first boot; it persists in `.env` (mode 600) across restarts; everything is masked in console output.

---

## Switching Engines or Versions Safely

Data lives in per-instance folders: `data/<engine>/<series>/` (e.g. `data/postgresql/18/`).

| Scenario | Behavior |
| :--- | :--- |
| Restart, same engine+version | Reuses the identical instance instantly |
| Patch bump via `latest` | Same series folder keeps working |
| Breaking major switch (PG 14 -> 18) | Fresh instance under `data/postgresql/18`; old data untouched; console prints both paths |
| Engine switch (redis -> mongodb) | Separate instance namespace; nothing shared |

Nothing is ever deleted automatically. Delete old instance folders manually once migrated.

PostgreSQL special case: booting v18 against a v14 data dir shows a full-screen action box with three options (keep old version / fresh DATA_DIR / wipe after backup) instead of a cryptic crash.

---

## All Startup Variables

### Core
| Variable | Default | Purpose |
| :--- | :--- | :--- |
| `DATABASE_TYPE` | `mariadb` | Engine to run (see matrix) |
| `DB_VERSION` | `latest` | Version/channel/exact/URL |
| `DB_NAME` | `database` | Database/schema created at first boot |
| `DB_USER` | `dbuser` | Application user |
| `DB_PASSWORD` | `auto` | User password (auto = strong random) |
| `DB_ROOT_PASSWORD` | `auto` | Root/admin/master password |
| `AUTO_GENERATE_CREDENTIALS` | `1` | Generate secrets when blank/auto |

### Behavior & Control
| Variable | Default | Purpose |
| :--- | :--- | :--- |
| `STRICT_VERSION` | `1` | Refuse wrong-version boots |
| `SAVE_TO_ENV` | `1` | Persist credentials to `.env` (600) |
| `PERFORMANCE_TUNING` | `1` | Auto-size buffers/caches from RAM/CPU |
| `SECURITY_HARDENING` | `1` | SCRAM, purge test accounts, disable DEBUG |
| `EXTRA_ARGS` | - | Raw flags appended to daemon command |
| `DATA_DIR` | auto | Override data location (disables instance manager) |
| `EXTRA_RUNTIMES` | - | Companion tools: python, nodejs, bun, litestream, rclone, aws, mongosh... |
| `EXTRA_URLS` | - | Extra downloads (`dest/name\|url` per line) |

### Expert Knobs
| Variable | Default | Purpose |
| :--- | :--- | :--- |
| `BIND_ADDRESS` | `0.0.0.0` | Primary listen address |
| `SKIP_VERSION_INSTALL` | `0` | Air-gap mode: use system binaries only |
| `ALLOW_SYSTEM_APT` | `0` | Permit root apt fallbacks (container stays isolated by default) |
| `PF_CURL_UA` | PotenFYR-Installer/1.0 | Custom user agent for restrictive CDNs |
| `PF_DEBUG` / `PF_INSTALLER_DEBUG` | `0` | Verbose trace lines |
| `CONSOLE_PORT`, `TCP_PORT`, `GRPC_PORT`, etc. | unset | Expose secondary services (default loopback-only) |

Per-engine extras: `POSTGRES_USER`, `COCKROACH_SECURE`, `ARANGODB_AUTH`, `ES_SECURITY_ENABLED`, `OPENSEARCH_DISABLE_SECURITY`, `NEO4J_AUTH`, `MANTICORE_MYSQL_PORT`, `SEAWEED_S3_PORT`, `AEROSPIKE_NAMESPACE`, and more (grep handlers for `${ENGINE}_`).

---

## Performance Auto-Tuning

With `PERFORMANCE_TUNING=1`, settings scale automatically from `SERVER_MEMORY` and CPU count:

- MariaDB/MySQL: InnoDB buffer pool ~60% RAM, log file 25% of pool, flush-at-commit=2, connection/thread caches scaled
- PostgreSQL: shared_buffers 25%, effective_cache_size 75%, maintenance_work_mem capped 512MB, SSD-tuned planner costs
- Redis family: maxmemory 85% RAM, io-threads per core, lazy-free evictions
- MongoDB: WiredTiger cache sized to container, snappy compression
- Elasticsearch/OpenSearch: heap defaults safe for small allocations; Cassandra heap half of RAM

Set `PERFORMANCE_TUNING=0` to manage configs yourself (files under `config/` are respected and never overwritten except port fixes).

---

## Security Model

- Downloads verified via published SHA256 sidecars where available (checksum mismatch is fatal)
- All log/console output sanitized: passwords, tokens, API keys masked everywhere including crash dumps
- `.env` mode 600; data dirs 700; sockets in `/tmp/.db-sockets`
- SCRAM-SHA-256 enforced for PostgreSQL remote auth; MySQL anonymous/test accounts purged; Redis DEBUG removed; MongoDB authorization enabled; Immudb admin default-password eliminated
- Secondary admin/UI ports bind `127.0.0.1` unless you explicitly allocate them (single-port policy)
- Installs stay inside your server volume; system package managers only with explicit `ALLOW_SYSTEM_APT=1` + root
- Crash reports never contain plaintext credentials (env snapshot pre-filtered)

---

## Architecture & OS Support

| Host arch | Status |
| :--- | :--- |
| amd64 (x86_64) | Full: every engine, every version |
| arm64 (aarch64) | Full: native builds wherever upstream ships them |
| arm/v7 (armhf) | Broad: PG standalone builds; others fall back to system engines with clear notice |
| s390x (IBM Z) | Broad: MongoDB official builds + fallback elsewhere |
| ppc64le (Power) | Broad: MinIO/VictoriaMetrics + fallback |
| riscv64 | Emerging: source-built and Java-based engines compile on demand |

- Multi-arch manifest: plain `docker pull` selects the right variant.
- Engines without upstream builds for an arch print one honest warning and serve the container-provided engine (strict contract preserved wherever real builds exist).
- OS: any Linux base works. libc family (glibc vs musl) is auto-detected; musl hosts receive musl-linked builds (e.g. standalone PostgreSQL), glibc-only tarballs gracefully use system packages on Alpine-style hosts.

---

## Panel Compatibility & Detection

Detected automatically from environment signals and shown on the startup card:

Pelican (wings v2 `P_SERVER_*` vars), Pterodactyl (classic mount layout), Feather, Wisp, Convoy, Cytopanel, Jexactyl, PufferPanel, AMP (Cuberite panel signals), Kubernetes, OpenShift, plain Docker, and any wings-compatible daemon (reported as wings-family). Force identity with `PANEL_NAME` / `PANEL_TYPE_OVERRIDE`.

Requirements are just: bash + curl or wget inside the image (our official image guarantees both), one allocated port, and outbound network for first-time downloads.

---

## Troubleshooting Guide

All failures write detailed reports before exiting: stack trace, last command, sanitized env snapshot, disk/network state, recent engine logs.

| Log file | Contents |
| :--- | :--- |
| `logs/startup_error.log` | Launcher/entrypoint crash reports (rotated at 1MB) |
| `logs/installer.log` | Version-installer trace: every probe, download, checksum |
| `logs/mariadb_init.log`, `mongod_init.log`, etc. | First-boot provisioning output |

| Symptom | Cause -> Fix |
| :--- | :--- |
| `Strict version verification failed` | Requested version unavailable from this network -> check installer.log tail; fix egress, pick another pin, or set STRICT_VERSION=0 |
| `No downloadable build found` | CDN blocked HEAD+GET -> installer already retries with browser UA + direct GETs; verify outbound firewall allows github.com/cdn.mysql.com/archive.mariadb.org/fastdl.mongodb.org |
| PostgreSQL box: VERSION MISMATCH | Data dir initialized by another major -> follow the three printed options (keep old version / fresh DATA_DIR / wipe after backup) |
| `Permission denied` executing binary | Rare FS quirk -> delete `bin/<binary>` and restart (installer re-provisions with enforced exec bit) |
| Engine starts then stops immediately | Read the engine's own log listed above; EXTRA_ARGS typos are the most common cause |
| Wrong panel detected | Set `PANEL_TYPE_OVERRIDE` / `PANEL_NAME` |

Console shows `[fatal error]` plus the report path every time - start there.

---

## Advanced Configuration

**Custom config files**: files you place in `config/` are honored:
- `config/my.cnf`, `config/postgresql.conf`, `config/pg_hba.conf`, `config/mongod.conf`, `config/redis.conf`, `config/custom.env` (sourced before variable normalization)

**Instance layout**:
```text
data/
├── postgresql/18/          # PGDATA for major 18
├── mariadb/11/             # datadir for major 11
├── mongodb/7/              # dbPath for series 7.0
└── meilisearch/default/    # single-instance engines
bin/                        # downloaded binaries (+ pg-18/, opt/<engine>/ trees)
.runtimes/                  # JDK17, companion tools
.env                        # credentials, mode 600
```

**EXTRA_ARGS examples**: `--max-connections=500` (mariadb), `-E xpack.security.enabled=true` (ES), custom JVM flags, etc.

---

## Custom Engines & Binary URLs

Two routes:

1. `DATABASE_TYPE=custom` + `CUSTOM_DOWNLOAD_URL` (tarball/zip/binary) + `CUSTOM_BINARY_NAME` + `CUSTOM_COMMAND`.
2. Any engine: set `DB_VERSION=https://your-host/engine.tar.gz` - the installer unpacks it into `bin/` and the standard handler runs it.

Pre-run hook: `CUSTOM_PRE_RUN_SCRIPT` executes before dispatch.

---

## Air-Gapped / Offline Fleets

Set `SKIP_VERSION_INSTALL=1`: the installer short-circuits (no network calls), stamps state, and boots with container-provided binaries. Combine with a pre-baked volume containing `bin/` contents from an online staging host to run fully offline at pinned versions. Version stamps (`bin/.versions/*`) prevent any download attempt while still verifying binaries at boot.

---

## Testing Suite & CI/CD

`tests/test-docker.sh` boots each engine in Pterodactyl-identical containers (uid 988, memory-limited, tmpfs volumes) and asserts readiness, credential persistence, and graceful SIGTERM handling:

```bash
./tests/test-docker.sh                          # full suite, builds image first
IMAGE_NAME=myimg BUILD_IMAGE=0 ./tests/test-docker.sh
READY_TIMEOUT=300 ./tests/test-docker.sh        # slower networks
```

Includes **pinned-version regression rows**: PostgreSQL 18, MariaDB 11.4, MySQL 8.0, MongoDB 7.0 must report exactly those versions - the core "respect startup variables" guarantee, enforced on every push.

CI workflows: `docker-image.yml` (multi-arch build + publish + stale-version cleanup), `validate-eggs.yml` (JSON validity + bash syntax), `test-docker.yml` (integration suite).

---

## Repository Layout

```text
egg-database-multi.json      The universal egg (single egg, 55+ engines)
Dockerfile                   Multi-arch universal image
entrypoint.sh                Panel detection, secrets, crash safety bootstrap
run.sh                       Dispatcher: version contract + data instances
scripts/
├── lib-diagnostics.sh       Central logging/traces/crash library
├── install-db-version.sh    55+ engine installer + latest resolver
├── db-init-postgres.sh      PostgreSQL handler
├── db-init-mariadb.sh       MariaDB/MySQL handler
├── db-init-redis.sh         In-memory family
├── db-init-mongo.sh         MongoDB/FerretDB
├── db-init-search.sh        Search/vector family
├── db-init-storage.sh       Storage/time-series family
├── db-init-extra.sh         Extended catalog (cockroach, tidb, etcd...)
├── performance-tuning.sh    RAM/CPU-driven tuner
└── password-gen.sh          Crypto secrets
tests/test-docker.sh         Integration suite
.github/workflows/           Build, validate, test pipelines
```

---

## License

MIT - see [LICENSE](LICENSE).

Maintained by PotenFYR Studios - support@potenfyr.in
