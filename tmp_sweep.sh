#!/usr/bin/env bash
bash -n scripts/install-db-version.sh && echo "syntax OK"
# simulate: existing install path now bundles missing extension libs
D=/tmp/pgbtest; rm -rf "$D"; mkdir -p "$D/lib-extra"
SERVER_DIR=/tmp/pgbtest INSTALL_DIR=/tmp/pgbtest/bin bash -c '
source scripts/install-db-version.sh --dry-run 2>/dev/null || true
' >/dev/null 2>&1
grep -n "bundle_pg_runtime_libs \"\${dest}/lib-extra\"" scripts/install-db-version.sh
