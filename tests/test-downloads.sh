#!/usr/bin/env bash
# Offline regression tests; --stall runs real curl/wget against loopback in Docker.
set -eu
cd "$(dirname "$0")/.."
INST=scripts/install-db-version.sh
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
extract_fn() { awk -v fn="$1" '$0 ~ "^"fn"\\(\\)" { p=1 } p { print } p && /^}/ { exit }' "$INST"; }
extract_case() { awk -v engine="$1" '$0 == "    "engine")" { p=1 } p { print } p && /^        ;;$/ { exit }' "$INST"; }
have() { command -v "$1" >/dev/null 2>&1; }
warn() { printf '%s\n' "$*" >&2; }
log() { :; }
ok() { :; }
fail() { warn "$*"; exit 1; }
if [ "${1:-}" = --stall ]; then
    eval "$(extract_fn fetch)"
    # A drip feed never reaches wget's idle timeout. No external network needed.
    perl -MIO::Socket::INET -e '
      $s=IO::Socket::INET->new(LocalAddr=>"127.0.0.1",LocalPort=>0,Listen=>8,ReuseAddr=>1) or die $!;
      open F,">",$ARGV[0] or die $!; print F $s->sockport; close F;
      $SIG{CHLD}="IGNORE";
      while($c=$s->accept){ if(fork()==0){close $s; $c->autoflush(1); print $c "HTTP/1.0 200 OK\r\nContent-Length: 99999\r\n\r\n"; for(1..40){print $c "x"; select undef,undef,undef,0.1} close $c; exit} close $c }
    ' "$TMP/port" &
    server=$!
    trap 'kill "$server" 2>/dev/null || true; rm -rf "$TMP"' EXIT
    for i in {1..100}; do [ -s "$TMP/port" ] && break; sleep .02; done
    url="http://127.0.0.1:$(<"$TMP/port")/drip"
    for client in curl wget; do
        (
            if [ "$client" = wget ]; then
                mkdir -p "$TMP/shim"
                printf '#!/bin/sh\nexit 1\n' > "$TMP/shim/curl"
                chmod +x "$TMP/shim/curl"
                PATH="$TMP/shim:$PATH"
            fi
            PF_DOWNLOAD_TIMEOUT=1
            start=$SECONDS
            printf original > "$TMP/output"
            if fetch "$url" "$TMP/output"; then fail "$client accepted incomplete response"; fi
            elapsed=$((SECONDS-start))
            [ "$elapsed" -le 3 ] || fail "$client exceeded total budget: ${elapsed}s"
            [ "$(<"$TMP/output")" = original ] || fail 'atomic destination overwritten'
            compgen -G "$TMP/output.dl.*" >/dev/null && fail 'partial file leaked'
            printf 'PASS: %s bounded drip download (%ss), atomic cleanup\n' "$client" "$elapsed"
        )
    done
    exit
fi
if [ "${1:-}" = --minio ]; then
    eval "$(extract_fn resolve_version)"
    ENGINE=minio; VERSION=latest; ARCH_TYPE=amd64
    validate_version_input() { :; }
    fetch() { printf '%064d minio.RELEASE.2025-09-07T16-13-09Z\n' 0; }
    resolve_version
    [ "$RESOLVED" = RELEASE.2025-09-07T16-13-09Z ] || fail "MinIO latest was not resolved from published binary metadata: $RESOLVED"
    fetch() { return 1; }
    resolve_version
    [ "$RESOLVED" = latest ] || fail 'MinIO metadata outage invented an old latest'
    printf 'PASS: MinIO published metadata and outage policy\n'
    exit
fi
ensure_single_binary_version() { :; }
seal_binary() { :; }
INSTALL_DIR="$TMP"; RESOLVED=v1.53.1; ARCH_TYPE=arm64; ARCH_ALT=aarch64
probe_url() { printf '%s' "$1" > "$TMP/primary"; return 0; }
fetch() { return 0; }
eval "case meilisearch in $(extract_case meilisearch) esac"
[ "$(<"$TMP/primary")" = 'https://github.com/meilisearch/meilisearch/releases/download/v1.53.1/meilisearch-linux-aarch64' ] || fail "wrong Meilisearch primary: $(<"$TMP/primary")"
printf 'PASS: Meilisearch arm64 primary uses aarch64\n'
