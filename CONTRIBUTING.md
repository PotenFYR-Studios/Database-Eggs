# Contributing to Database-Eggs

Thanks for helping make Database-Eggs better! This repo holds the **Multi Database** egg: a single Pterodactyl/Pelican-compatible egg definition (`egg-*.json` at the repo root) plus the runtime scripts and Docker image that back it.

## Repository layout

```text
├── egg-database-multi.json     # The exported egg (PTDL_v2): the product
├── Dockerfile                  # Multi-variant universal container (RUNTIME_VARIANT=all)
├── entrypoint.sh               # Bootstrap: panel detection, secrets, .env sync
├── run.sh                      # Engine dispatcher & instance router
├── scripts/                    # install-db-version, db-init-* per engine family,
│                               # performance-tuning, companion-loader, lib-diagnostics
├── tests/                      # Docker integration + panel lifecycle suites
└── .github/workflows/          # validate-eggs, test-docker, docker-image, docs-pages
```

## Egg JSON contract

The egg file is exported in the **PTDL_v2** format. CI (`.github/workflows/validate-eggs.yml`) enforces the following, so please keep them true in PRs:

- `name`: non-empty string (displayed in the panel).
- `meta.version`: format identifier (`PTDL_v2`).
- `meta.update_url`: must point at the raw egg JSON on the **`master`** branch (the default branch).
- `docker_images`: a non-empty object of `label -> image reference`. This repo ships exactly one universal image: `ghcr.io/potenfyr-studios/database-eggs:latest`.
- `variables`: a non-empty array; **every** variable must have:
  - `name` and `env_variable` (non-empty strings; the env var is what the runtime reads),
  - `rules` (Laravel-style validation string, e.g. `required|string|max:32`),
  - `default_value`, `user_viewable`, `user_editable`, `field_type`.
- Secrets (like `GIT_TOKEN`) must be `user_viewable: false` and `user_editable: false`.

Docs note: the documentation site (`docs/`) regenerates its catalog from the egg JSON at build time (`docs/scripts/build-catalog.ts`), so **never hand-edit the site's egg/variable/engine content**: change the egg JSON instead.

## Local validation

The same checks CI runs:

```bash
# JSON syntax + structural contract
jq empty egg-database-multi.json
jq -e '(.name | type == "string") and (.docker_images | type == "object" and length > 0)
       and (.variables | type == "array" and length > 0)' egg-database-multi.json

# Shell syntax for any script you touched
bash -n entrypoint.sh
bash -n scripts/your-script.sh

# Full Docker integration suite (builds the image, boots real engines)
./tests/test-docker.sh
# ...or a subset:
TEST_ENGINES="postgresql,redis" ./tests/test-docker.sh
```

## Submitting changes

1. Fork and branch from `master`.
2. Keep one logical change per PR (one engine, one variable, one script fix…).
3. If you add a variable, update its `description`: it doubles as the docs-site catalog copy.
4. Run the validation commands above.
5. Open a PR using the template; CI will validate the egg JSON and shell syntax automatically.

For engine additions: add the dispatch branch in `run.sh` + a `db-init-*.sh` handler (or extend an existing one), and add the engine to the `DATABASE_TYPE` variable description so it appears in the catalog. If it needs binaries not in the base image, extend `scripts/install-db-version.sh`.

## Reporting issues

Use the [issue templates](.github/ISSUE_TEMPLATE/): pick the closest match (bug, feature request, documentation, question). For engine requests, include the engine's upstream download URL and versioning scheme. Security concerns: follow [SECURITY.md](SECURITY.md) instead of filing a public issue.

## License

By contributing, you agree that your contributions are licensed under the [Apache License 2.0 with the Commons Clause](LICENSE).
