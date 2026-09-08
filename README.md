# Database Eggs

One egg with a shared database runtime. The dispatcher contains **46 database/cache/search/storage entries plus 5 ancillary services**, excluding aliases and `custom`. These are implemented code paths, **not 51 verified engines or a promise of every upstream version**. Installation and startup depend on the engine, version, CPU architecture, available upstream artifacts, and container libraries. The runtime includes credential generation, tuning, panel detection, diagnostics, and version switching for panel-managed containers and native Docker.

[![GitHub License](https://img.shields.io/github/license/PotenFYR-Studios/Database-Eggs?style=for-the-badge&color=blue)](LICENSE)
[![Docker Image](https://img.shields.io/badge/Docker-GHCR-blue?style=for-the-badge&logo=docker)](https://github.com/PotenFYR-Studios/Database-Eggs/pkgs/container/database-eggs)
[![Panels](https://img.shields.io/badge/Panels-Pterodactyl%20%7C%20Pelican%20%7C%20Feather%20%7C%20Wisp-brightgreen?style=for-the-badge)](https://github.com/PotenFYR-Studios/Database-Eggs)

---

## Contents

#### Getting Started

1. [What Is This?](#what-is-this)
2. [Quick Start in 5 Minutes](#quick-start-in-5-minutes)
3. [Choosing Your Database](#choosing-your-database)
4. [Picking a Version](#picking-a-version)

#### Everyday Use

- [Connecting to Your Database](#connecting-to-your-database)
- [Switching Engines or Versions Safely](#switching-engines-or-versions-safely)
- [All Startup Variables](#all-startup-variables)

#### Reliability & Operations

- [Performance Auto-Tuning](#performance-auto-tuning)
- [Security Model](#security-model)
- [Architecture & OS Support](#architecture--os-support)
- [Panel Compatibility & Detection](#panel-compatibility--detection)
- [Troubleshooting Guide](#troubleshooting-guide)

#### Expert Zone

- [Advanced Configuration](#advanced-configuration)
- [Custom Engines & Binary URLs](#custom-engines--binary-urls)
- [Air-Gapped / Offline Fleets](#air-gapped--offline-fleets)
- [Testing Suite & CI/CD](#testing-suite--cicd)
- [Repository Layout](#repository-layout)
- [License](#license)

---

## What Is This?

A single egg plus a shared container image with engine-specific installation and startup handlers:

- You set two variables: `DATABASE_TYPE` and `DB_VERSION`.
- On boot, the runtime attempts to obtain that engine/version **inside your container/server volume**, then runs the engine-specific initialization and startup handler. Provisioning and tuning coverage vary by engine.
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
| Document/Backend | `mongodb` `ferretdb` `arangodb` `orientdb` `ravendb` `couchdb` `pocketbase` |
| In-Memory/KV | `redis` `valkey` `keydb` `dragonfly` `memcached` `etcd` `immudb` |
| Vector/Search | `meilisearch` `typesense` `qdrant` `elasticsearch` `opensearch` `solr` `manticoresearch` `milvus` `weaviate` `quickwit` |
| Time-Series | `influxdb` `clickhouse` `victoriametrics` `questdb` |
| Object Storage | `minio` `seaweedfs` `garage` |
| Graph/Ledger | `neo4j` `dgraph` `surrealdb` |
| Wide-Column/Misc | `cassandra` `aerospike` `rethinkdb` `sqld` `sqlite` |
| Ancillary services (not counted as database entries) | `nats` `kafka` `prometheus` `consul` `loki` |
| Anything else | `custom` |

### Coverage, not certification

Static audit of `run.sh`, `scripts/install-db-version.sh`, and the `db-init-*.sh` handlers:

- **51 distinct named dispatch targets**: 46 database/cache/search/storage entries and 5 ancillary services. Storage systems, caches, search engines, the PocketBase backend, and the FerretDB compatibility layer are included in the broader catalog; they are not all independent database servers.
- All named targets route to initialization/startup code. A handler existing does not prove its configuration or provisioning works for every release.
- **49 targets have explicit installer branches** (44 of the 46 catalog entries, plus the 5 services). Several branches are best-effort downloads rather than validated installations.
- **SQLite** uses the image's distro `sqlite3` package; there is no version-specific SQLite installer or network database daemon. **CouchDB** has a startup handler but neither a dedicated version installer nor a baked package in this Dockerfile: supply a compatible installation yourself.
- Aliases `postgres`, `mongo`, `cockroach`, `yugabyte`, `manticore`, `weed`, and `libsql` do not add engines. `custom` and companion tools such as Litestream do not add engines either.
- `RUNTIME_VARIANT=all` is a shared base, not every catalog binary preinstalled. Apt supplies MariaDB, PostgreSQL, Redis, Memcached, and SQLite; other build-time downloads are best-effort. MongoDB and most extended targets are provisioned at runtime. The `mysql` image variant bakes MariaDB, not Oracle MySQL; the `postgres` variant uses Ubuntu's PostgreSQL package, not a guaranteed 16+ release.

The version examples below describe intended requests, not a tested release matrix. In particular, Milvus may lack a standalone upstream artifact, and several extended installers still use architecture-specific or fallback asset patterns. Validate your exact engine/version/platform combination before production use.

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
| CouchDB | `couchdb` | externally supplied | 5984 | Startup handler only; no built-in installer |
| Redis | `redis` | `6.2`-`7.4` | 6379 | RDB+AOF, io-threads |
| Valkey | `valkey` | `latest` | 6379 | Best-effort baked source build or runtime install |
| KeyDB | `keydb` | `latest` | 6379 | Multithreaded (source build) |
| Dragonfly | `dragonfly` | `latest` | 6379 | Modern ultra-fast |
| Memcached | `memcached` | distro/runtime-dependent | 11211 | In-memory cache |
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
| SQLite | `sqlite` | distro package | none | Embedded file database; optional Litestream |
| PocketBase | `pocketbase` | `latest` | 8090 | Backend + admin UI |
| Kafka | `kafka` | `latest` | 9092 | Ancillary event-streaming service |
| Prometheus | `prometheus` | `latest` | 9090 | Ancillary monitoring service |
| Consul | `consul` | `latest` | 8500 | Ancillary service discovery |
| Loki | `loki` | `latest` | 3100 | Ancillary log service |
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

These are request forms, not a guarantee that an upstream artifact exists. Resolution and verification coverage differ by engine; unavailable builds, ABI mismatches, or missing dependencies can prevent startup. Do not assume a successful image build proves a requested database version works.

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

The Dockerfile uses **Ubuntu 22.04 (glibc)**. A live `docker manifest inspect ubuntu:22.04` audit found all six Linux platforms below (attestation entries marked `unknown/unknown` are not platforms). A base-image manifest is **not** evidence that every package, upstream binary, full runtime image, or database release works on that platform.

| Image platform | Base manifest | Verification in this audit |
| :--- | :--- | :--- |
| `linux/amd64` | Present | Native Ubuntu container execution and targeted Dockerfile architecture-stage build passed; no full universal build |
| `linux/arm64` | Present (`v8`) | Mapping and Meilisearch `aarch64` asset name checked; no native/emulated execution |
| `linux/arm/v7` | Present | Shell mapping checked only; package/engine execution unverified |
| `linux/s390x` | Present | Shell mapping checked only; package/engine execution unverified |
| `linux/ppc64le` | Present | Shell mapping checked only; package/engine execution unverified |
| `linux/riscv64` | Present | Shell mapping checked only; package/engine execution unverified |

- The audit host had amd64 Docker but no Buildx. Foreign-architecture builds/runs were unavailable in this audit; no privileged emulation was installed. Supplying `TARGETARCH=arm64` to a native shell test checks string selection, **not** ARM execution.
- CI requests these six platforms. Successful CI publication and the resulting GHCR manifest must be checked separately; the workflow matrix alone is not proof of a published multi-arch image. `docker pull` selects a matching platform only when that image tag actually publishes one.
- Standalone downloads in the Dockerfile mostly tolerate failure. A successful build can therefore omit optional binaries, even on amd64. Runtime installers also have engine-specific gaps; there is no universal source-build or compatible-system-binary fallback.
- Keep `STRICT_VERSION=1` when an exact release matters, and verify the actual binary/version and readiness. Disabling strict checking does not make an incompatible architecture or ABI usable.
- Host distribution does not change the container's libc: Ubuntu containers on Alpine hosts still use Ubuntu/glibc userspace. Replacing the base with Alpine/musl or another distribution is not a verified build path. Java-based engines still need a compatible JRE and sometimes native libraries.

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
egg-database-multi.json      Shared egg (see audited coverage above)
Dockerfile                   Multi-arch universal image
entrypoint.sh                Panel detection, secrets, crash safety bootstrap
run.sh                       Dispatcher: version contract + data instances
scripts/
├── lib-diagnostics.sh       Central logging/traces/crash library
├── install-db-version.sh    Engine-specific installers + version resolver
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
