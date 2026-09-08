#!/usr/bin/env bash
# Focused real startup check; never builds an image or substitutes a version.
# Usage: IMAGE_NAME=database-eggs:test-redis bash tests/test-source-engines.sh redis 7.2.5 source
#        IMAGE_NAME=database-eggs:test-redis bash tests/test-source-engines.sh memcached 1.6.14 cached
# `source` requires a newly provisioned binary and source-build log evidence;
# `cached` explicitly permits the image's version-matching system binary.
set -euo pipefail
engine=${1:?Specify redis or memcached}
version=${2:?Specify an exact version or latest}
mode=${3:-source}
case "$engine" in redis) port=6379; binary=redis-server;; memcached) port=11211; binary=memcached;; *) exit 2;; esac
case "$mode" in source|cached) ;; *) exit 2;; esac
image=${IMAGE_NAME:-database-eggs:test-redis}
budget=${READY_TIMEOUT:-120}
[[ $budget =~ ^[1-9][0-9]*$ ]] || exit 2
root=$(cd "$(dirname "$0")/.." && pwd)
name="source-${engine}-$$"
log=${TEST_LOG:-/tmp/${name}.log}
cleanup() {
    docker logs "$name" > "$log" 2>&1 || true
    docker rm -f "$name" >/dev/null 2>&1 || true
}
trap cleanup EXIT
mounts=(-v "$root/entrypoint.sh:/entrypoint.sh:ro" -v "$root/run.sh:/usr/local/bin/run.sh:ro")
for file in "$root"/scripts/*.sh; do mounts+=(-v "$file:/usr/local/bin/${file##*/}:ro"); done
printf 'IMAGE=%s ENGINE=%s REQUEST=%s MODE=%s BUDGET=%ss LOG=%s\n' "$image" "$engine" "$version" "$mode" "$budget" "$log"
docker run -d --name "$name" --cpus=2 --memory=1536m -u 988:988 \
    "${mounts[@]}" -e AUTO_UPDATE_EGG=0 -e DATABASE_TYPE="$engine" \
    -e DB_VERSION="$version" -e SERVER_PORT="$port" -e SERVER_MEMORY=256 \
    -e DB_PASSWORD=SourceEngineTestOnly123 -e MAKE_ARGS=-j2 -e MAKEFLAGS=-j2 \
    -e PF_FAIL_FAST=1 -e PF_FAIL_SLEEP=0 "$image" >/dev/null
ready=0
deadline=$((SECONDS + budget))
while ((SECONDS < deadline)); do
    [[ $(docker inspect -f '{{.State.Running}}' "$name") == true ]] || break
    if [[ $engine == redis ]]; then
        if docker exec "$name" bash -c 'cli=/home/container/bin/redis-cli; [[ -x $cli ]] || cli=redis-cli; [[ $(REDISCLI_AUTH="$DB_PASSWORD" "$cli" --raw -p "$SERVER_PORT" PING 2>/dev/null) == PONG ]]' 2>/dev/null; then ready=1; break; fi
    else
        if docker exec "$name" timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/11211; printf "set sourcecheck 0 30 5\r\nhello\r\nget sourcecheck\r\n" >&3; IFS= read -r -t 2 a <&3; IFS= read -r -t 2 b <&3; IFS= read -r -t 2 c <&3; IFS= read -r -t 2 d <&3; [[ $a == $'"'"'STORED\r'"'"' && $b == $'"'"'VALUE sourcecheck 0 5\r'"'"' && $c == $'"'"'hello\r'"'"' && $d == $'"'"'END\r'"'"' ]]' 2>/dev/null; then ready=1; break; fi
    fi
    sleep 1
done
if [[ $ready != 1 ]]; then
    printf 'FAIL: protocol readiness (see %s)\n' "$log"
    exit 1
fi
actual=$(docker exec "$name" bash -c 'b=/home/container/bin/'"$binary"'; [[ -x $b ]] || b='"$binary"'; "$b" --version' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
printf 'ACTUAL=%s; protocol check passed\n' "$actual"
if [[ $version != latest && $actual != "$version" ]]; then
    printf 'FAIL: requested %s, actually running %s\n' "$version" "$actual"; exit 1
fi
if [[ $mode == source ]]; then
    docker exec "$name" test -x "/home/container/bin/$binary"
    # Reject successful distro/package fallback as proof of a native source build.
    (grep -Eq "Entering directory|[[:space:]]CC[[:space:]]|gcc |cc |make\[" "$log" 2>/dev/null) || {
        printf 'FAIL: no source compilation evidence\n'; exit 1;
    }
fi
if [[ $engine == redis ]]; then
    docker exec "$name" bash -c '[[ $(redis-cli --raw -p "$SERVER_PORT" PING 2>&1) == *NOAUTH* ]]'
    printf 'PASS: unauthenticated Redis request rejected\n'
fi
docker stop -t 10 "$name" >/dev/null
exit_code=$(docker inspect -f '{{.State.ExitCode}}' "$name")
[[ $exit_code == 0 ]] || { printf 'FAIL: shutdown exit=%s\n' "$exit_code"; exit 1; }
printf 'PASS: %s %s (%s), protocol and graceful stop exit=0\n' "$engine" "$actual" "$mode"
