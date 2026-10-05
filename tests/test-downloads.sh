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

# pf_mariadb_urls: canonical archive.mariadb.org URL first, princeton mirror
# second, interleaved for the resolved version then fallback patches .9..0.
# Versions are deduplicated, so a resolved patch that already appears in the
# fallback range is not emitted twice.
eval "$(extract_fn pf_mariadb_urls)"
mariadb_urls=$(pf_mariadb_urls 11.4.5 amd64 amd64)
[ -n "$mariadb_urls" ] || fail 'pf_mariadb_urls produced no candidate URLs'
first=$(printf '%s\n' "$mariadb_urls" | sed -n 1p)
second=$(printf '%s\n' "$mariadb_urls" | sed -n 2p)
[ "$first" = 'https://archive.mariadb.org/mariadb-11.4.5/bintar-linux-systemd-x86_64/mariadb-11.4.5-linux-systemd-amd64.tar.gz' ] \
    || fail "pf_mariadb_urls primary is not the resolved archive URL: $first"
[ "$second" = 'https://mirror.math.princeton.edu/pub/mariadb/mariadb-11.4.5/bintar-linux-systemd-x86_64/mariadb-11.4.5-linux-systemd-amd64.tar.gz' ] \
    || fail "pf_mariadb_urls second is not the resolved princeton mirror URL: $second"
arch9=$(printf '%s\n' "$mariadb_urls" | grep -n 'archive.mariadb.org/mariadb-11.4.9/' | cut -d: -f1 | head -n1)
mir9=$(printf '%s\n' "$mariadb_urls" | grep -n 'mirror.math.princeton.edu/pub/mariadb/mariadb-11.4.9/' | cut -d: -f1 | head -n1)
[ -n "$arch9" ] && [ -n "$mir9" ] || fail 'pf_mariadb_urls is missing the 11.4.9 fallback pair'
[ "$arch9" -gt 2 ] || fail 'the 11.4.9 fallback did not appear after the resolved pair'
[ "$mir9" -eq "$((arch9 + 1))" ] || fail 'the 11.4.9 fallback is not archive-then-mirror'
count=$(printf '%s\n' "$mariadb_urls" | grep -c .)
[ "$count" -eq 20 ] || fail "pf_mariadb_urls expected 20 candidates (10 deduped versions x 2 mirrors), got $count"
printf 'PASS: pf_mariadb_urls archive-then-princeton interleave, fallback order and dedup (20 candidates)\n'

# install_mariadb(): the large bintar transfer gets a longer (still bounded)
# wall-clock budget than fetch()'s default, and the caller's value is restored
# afterwards. Structural/offline check -- no network or real download.
mariadb_fn=$(extract_fn install_mariadb)
[ -n "$mariadb_fn" ] || fail 'cannot extract install_mariadb()'
tfc_line=$(printf '%s\n' "$mariadb_fn" | grep -n 'try_fetch_candidates' | head -n1 | cut -d: -f1)
[ -n "$tfc_line" ] || fail 'install_mariadb() does not call try_fetch_candidates'
widen_line=$(printf '%s\n' "$mariadb_fn" | grep -n 'export PF_DOWNLOAD_TIMEOUT=1800' | head -n1 | cut -d: -f1)
[ -n "$widen_line" ] || fail 'install_mariadb() does not widen PF_DOWNLOAD_TIMEOUT to 1800'
[ "$widen_line" -lt "$tfc_line" ] || fail 'PF_DOWNLOAD_TIMEOUT=1800 is not set before the bintar transfer'
restore_line=$(printf '%s\n' "$mariadb_fn" | grep -n 'old_download_timeout' | tail -n1 | cut -d: -f1)
[ -n "$restore_line" ] || fail 'install_mariadb() does not restore old_download_timeout'
[ "$restore_line" -gt "$tfc_line" ] || fail 'old_download_timeout is not restored after the bintar transfer'
printf '%s\n' "$mariadb_fn" | sed -n "${restore_line}p" | grep -q 'unset PF_DOWNLOAD_TIMEOUT' \
    || fail 'restore does not unset PF_DOWNLOAD_TIMEOUT when it was previously unset'
# Overall search deadline: exported before the transfer, restored right after.
fd_widen_line=$(printf '%s\n' "$mariadb_fn" | grep -n 'export PF_FETCH_DEADLINE=3600' | head -n1 | cut -d: -f1)
[ -n "$fd_widen_line" ] || fail 'install_mariadb() does not set PF_FETCH_DEADLINE=3600'
[ "$fd_widen_line" -lt "$tfc_line" ] || fail 'PF_FETCH_DEADLINE=3600 is not set before the bintar transfer'
fd_restore_line=$(printf '%s\n' "$mariadb_fn" | grep -n 'old_fetch_deadline' | tail -n1 | cut -d: -f1)
[ -n "$fd_restore_line" ] || fail 'install_mariadb() does not restore old_fetch_deadline'
[ "$fd_restore_line" -gt "$tfc_line" ] || fail 'old_fetch_deadline is not restored after the bintar transfer'
printf '%s\n' "$mariadb_fn" | sed -n "${fd_restore_line}p" | grep -q 'unset PF_FETCH_DEADLINE' \
    || fail 'restore does not unset PF_FETCH_DEADLINE when it was previously unset'
printf '%s\n' "$(extract_fn fetch)" | grep -q '\${PF_DOWNLOAD_TIMEOUT:-300}' \
    || fail 'fetch() default PF_DOWNLOAD_TIMEOUT=300 changed'
printf 'PASS: install_mariadb() widens PF_DOWNLOAD_TIMEOUT/PF_FETCH_DEADLINE for the bintar transfer and restores both; fetch() default unchanged\n'

# try_fetch_candidates(): optional PF_FETCH_DEADLINE caps the TOTAL search (real
# GET attempts), not each attempt, and unset => today's behavior. Behavioral and
# hermetic: probe always "HEAD-ok", every real fetch fails after 1s, 8 candidates.
eval "$(extract_fn try_fetch_candidates)"
probe_url() { return 0; }
ATTEMPTS_FILE="$TMP/attempts"
: > "$ATTEMPTS_FILE"
fetch() { echo x >> "$ATTEMPTS_FILE"; sleep 1; return 1; }
urls8=(); for i in 1 2 3 4 5 6 7 8; do urls8+=("http://fake/$i"); done
PF_FETCH_DEADLINE=2
if try_fetch_candidates "$TMP/deadline_out" "${urls8[@]}"; then fail 'try_fetch_candidates wrongly succeeded when every fetch failed'; fi
[ ! -e "$TMP/deadline_out" ] || fail 'deadline stop left the outfile behind'
n_deadline=$(grep -c . "$ATTEMPTS_FILE" || true)
[ "$n_deadline" -ge 1 ] || fail 'PF_FETCH_DEADLINE run made no attempt at all'
[ "$n_deadline" -lt 8 ] || fail "PF_FETCH_DEADLINE did not stop the search (attempts=$n_deadline)"
: > "$ATTEMPTS_FILE"
unset PF_FETCH_DEADLINE
if try_fetch_candidates "$TMP/no_deadline_out" "${urls8[@]}"; then fail 'try_fetch_candidates wrongly succeeded without deadline'; fi
n_default=$(grep -c . "$ATTEMPTS_FILE" || true)
# No deadline => the guard is inert: all 8 phase-1 candidates are attempted (the
# phase-2 loop then adds up to 4 more), never cut short.
[ "$n_default" -ge 8 ] || fail "no-deadline default changed: attempted $n_default of 8 candidates"
printf 'PASS: try_fetch_candidates PF_FETCH_DEADLINE=2 stopped after %s/8 attempts; unset attempted all 8 candidates (%s total incl. phase 2)\n' "$n_deadline" "$n_default"
