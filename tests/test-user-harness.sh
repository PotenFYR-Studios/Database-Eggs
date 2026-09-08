#!/bin/bash
# Offline behavioral regressions for the Docker users harness.
# No Docker; no network.  Passes when every regression guard fires.
set -eu
cd "$(dirname "$0")/.."
python3 - <<'PY'
import pathlib, subprocess, tempfile, os, textwrap

source = pathlib.Path('tests/test-users.sh').read_text().split('\nselect_engines "$@"')[0].split('\nVOL=')[0]
# Neutralize docker_bounded so our override wins.
source = source.replace('docker_bounded() { timeout --kill-after=2 "$DOCKER_TIMEOUT" docker "$@"; }',
                        'docker_bounded() { docker "$@"; }')

def run(body, env=None):
    with tempfile.TemporaryDirectory() as tmp:
        stub = pathlib.Path(tmp) / 'docker'
        stub.write_text('#!/bin/bash\ndocker "$@"\n')
        stub.chmod(0o700)
        # Body defines docker() then exports it so subprocs inherit it.
        full = source + '\n' + body
        return subprocess.run(['bash', '-c', full], text=True,
                              capture_output=True, timeout=8,
                              env={**os.environ, **(env or {}), 'PATH': tmp + ':' + os.environ['PATH']})

checks = [
  ('stopped containers fail immediately', '''
  docker() { case "$1" in inspect) printf false;; exec) echo exec >> "$TRACE"; return 1;; esac; }
  export -f docker
  sleep() { :; }
  wait_ready stopped 'true' 2 && exit 1
  test ! -s "$TRACE"
  '''),
  ('selected version and offline mode reach Docker', '''
  docker() { case "$1" in inspect) printf true;; *) printf '%s\\n' "$@" >> "$TRACE";; esac; }
  export -f docker
  boot sample /tmp mariadb 13306 alice secret
  python3 -c 'import os; s=open(os.environ["TRACE"]).read(); assert "DB_VERSION=10.11" in s; assert "SKIP_VERSION_INSTALL=1" in s'
  '''),
  ('readiness command has a wall clock bound', '''
  docker() { case "$1" in inspect) printf true;; exec) return 1;; esac; }
  export -f docker
  wait_ready sample 'true' 1 && exit 1
  exit 0
  '''),
]

failed = 0
for title, body in checks:
    with tempfile.TemporaryDirectory() as tmp:
        try:
            result = run(body, {'TRACE': tmp + '/trace', 'MARIADB_VERSION': '10.11',
                                'SKIP_VERSION_INSTALL': '1', 'READY_TIMEOUT': '1',
                                'READY_INTERVAL': '0.1', 'DOCKER_TIMEOUT': '1'})
            ok = result.returncode == 0
        except subprocess.TimeoutExpired:
            ok = False
        print(('PASS: ' if ok else 'FAIL: ') + title)
        if not ok:
            print('  stdout:', (result.stdout or '')[-200:])
            print('  stderr:', (result.stderr or '')[-200:])
        failed += not ok

# Invalid engine selection rejects before Docker is called.
r2 = subprocess.run(['bash', 'tests/test-users.sh', 'nonesuch'],
                    capture_output=True, text=True, timeout=5)
ok2 = r2.returncode != 0 and 'Unknown engine' in (r2.stdout + r2.stderr)
print(('PASS: ' if ok2 else 'FAIL: ') + 'invalid engine rejected')
if not ok2:
    print('  exit:', r2.returncode, 'out:', (r2.stdout or '')[-200:], 'err:', (r2.stderr or '')[-200:])
failed += not ok2

raise SystemExit(bool(failed))
PY
