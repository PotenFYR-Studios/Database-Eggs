<!-- Thanks for contributing to Database-Eggs! -->

## What does this PR change?

<!-- One or two sentences: engine addition, egg variable change, script fix, docs… -->

## Type of change

- [ ] 🥚 Egg JSON change (`egg-database-multi.json`: variables, startup, config)
- [ ] 🗄️ New engine support (`run.sh` dispatch + `scripts/db-init-*.sh`)
- [ ] 🔧 Runtime script fix (`entrypoint.sh`, `run.sh`, `scripts/*`)
- [ ] 🐳 Docker image (`Dockerfile`)
- [ ] 📚 Documentation / docs site (`docs/`)
- [ ] 🧪 Tests / CI
- [ ] Other

## Checklist

- [ ] `jq empty egg-database-multi.json` passes (for egg changes)
- [ ] `bash -n` passes for every script I touched
- [ ] Egg changes keep the PTDL_v2 contract (see [CONTRIBUTING.md](../CONTRIBUTING.md)):
      every variable has `env_variable`, `rules`, `default_value`; secrets are
      `user_viewable: false`
- [ ] `meta.update_url` / remote-fetch URLs still point at the `master` branch
- [ ] New variables are documented in the variable `description` (it feeds the
      docs-site catalog automatically)
- [ ] I tested against a panel or `./tests/test-docker.sh` (or explained why not)

## Evidence

<!-- Console output, screenshots of the panel, or test results. Redact secrets. -->
