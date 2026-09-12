# Security Policy

## Supported versions

Database-Eggs ships a rolling universal image and egg: only the latest `master` and the `latest` image tag receive security fixes:

| Artifact | Supported |
| :--- | :--- |
| `egg-database-multi.json` on `master` | ✅ |
| `ghcr.io/potenfyr-studios/database-eggs:latest` | ✅ |
| Pinned `sha-<ref>` image tags | ❌ (rebuilt artifacts, not maintained) |

Pinned engine versions (e.g. PostgreSQL 16 vs 18) all receive the same runtime hardening; engine-level CVEs should be reported upstream too, but we will help you move to a patched release via `DB_VERSION`.

## Reporting a vulnerability

**Do not open a public GitHub issue for security reports.**

- Email: **support@potenfyr.in** (add `[security]` to the subject), or
- GitHub: use [Private vulnerability reporting](https://github.com/PotenFYR-Studios/Database-Eggs/security/advisories/new) on this repository.

Include: affected file(s) or image digest, the panel/runtime environment, and a minimal reproduction. Please give us a reasonable window (90 days) before public disclosure; we will credit you in the advisory unless you prefer to stay anonymous.

## In scope

- The egg definition (`egg-database-multi.json`): variable handling, defaults, exported secrets.
- Runtime scripts (`entrypoint.sh`, `run.sh`, `scripts/*`): credential generation/storage, privilege handling, download integrity (SHA256 verification), injection into daemon command lines.
- The container image (`Dockerfile`, GHCR publishes): base packages, entrypoint, user privileges (UID 988).

## Out of scope

- Vulnerabilities in the database engines themselves (report upstream: PostgreSQL, MongoDB, Redis, …; we can still advise on mitigations via `EXTRA_ARGS` or version pinning).
- The hosting panels (Pterodactyl, Pelican, Feather, Wisp).
- Self-inflicted exposure: sharing your `.env`, weakening `SECURITY_HARDENING`, or disabling `SAVE_TO_ENV` then leaking process env.
- Social engineering against support email/Discord.

## Known design constraints

- The container intentionally runs as UID `988` without host root; host-level tuning (`REDIS_OVERCOMMIT_MEMORY`, `HOST_SOMAXCONN`, `HOST_DISABLE_THP`) can only ever *print guidance* when running unprivileged; it never elevates.
- Credentials are stored in `/home/container/.env` (mode `600`) inside the server volume; anyone with panel file access can read it. Treat panel access as credential access.
- `EXTRA_URLS` and `GIT_REPO_URL` fetch user-specified content at runtime; verify anything you point them at.
