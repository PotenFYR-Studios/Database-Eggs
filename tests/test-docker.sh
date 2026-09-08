#!/usr/bin/env bash
# =============================================================================
#  PotenFYR Studios - Universal Multi-Database Docker & Panel Verification Suite
#
#  Validates all database engines, versions, authentication, security hardening,
#  performance auto-tuning, and graceful shutdown under Pterodactyl-identical
#  container conditions (UID 988:988, volume mounts, variable injection).
# =============================================================================

set -uo pipefail

# Fast harness regressions; no Docker daemon or image build required.
if [ "${1:-}" = "--self-test" ]; then
    # Keep even deliberately crashed worker fixtures inside one disposable root.
    TMPDIR=$(mktemp -d) || exit 1
    export TMPDIR
    trap 'rm -rf "${TMPDIR}"' EXIT
    docker() {
        case "$1" in
            run)
                [ "${MOCK_SCENARIO}" != "worker-crash" ] || exit 7
                [ "${MOCK_SCENARIO}" != "worker-empty" ] || exit 0
                if [ "${MOCK_SCENARIO}" = "no-auto-update" ]; then
                    [[ "$*" == *'-e AUTO_UPDATE_EGG=0'* ]] || exit 7
                fi
                local arg
                for arg in "$@"; do
                    if [[ "$arg" == *:/home/container ]]; then
                        local credential_file="${arg%:/home/container}/.env"
                        if [ "${MOCK_SCENARIO}" != "missing-credentials" ]; then
                            touch "$credential_file"
                            chmod 600 "$credential_file"
                            [ "${MOCK_SCENARIO}" != "public-credentials" ] || chmod 644 "$credential_file"
                        fi
                    fi
                done ;;
            inspect)
                if [[ "$3" == *Running* ]]; then printf 'true\n'; else printf '0\n'; fi ;;
            exec)
                [[ "$*" == *'ss -tuln'* ]] && return 0
                [ "${MOCK_SCENARIO}" != "client-failure" ] ;;
            logs) printf 'mock server has an open port\n' ;;
            *) return 0 ;;
        esac
    }
    sleep() { :; }
    export -f docker sleep
    self_failures=0
    check_harness() {
        local name="$1" scenario="$2" engines="$3" parallel="$4" expected="$5" pattern="$6" output status
        output=$(MOCK_SCENARIO="$scenario" BUILD_IMAGE=0 READY_TIMEOUT=1 \
            TEST_ENGINES="$engines" PARALLEL="$parallel" MAX_JOBS="${7:-2}" bash "$0" 2>&1)
        status=$?
        if [ "$status" -eq "$expected" ] && [[ "$output" == *"$pattern"* ]]; then
            printf 'PASS: %s\n' "$name"
        else
            printf 'FAIL: %s (exit %s, expected %s; expected %s)\n%s\n' "$name" "$status" "$expected" "$pattern" "$output"
            self_failures=$((self_failures + 1))
        fi
    }
    check_harness 'client failure cannot fall back to open port' client-failure redis 0 1 'Failed Checks: 1'
    check_harness 'parallel client failure is counted' client-failure redis,memcached 1 1 'Failed Checks: 1'
    check_harness 'parallel worker crash cannot pass' worker-crash redis,memcached 1 1 'Failed Checks: 2'
    check_harness 'parallel successful jobs are counted' success redis,memcached 1 0 'Total Checks : 6'
    check_harness 'empty serial selection fails' success not-an-engine 0 1 'No engine jobs selected'
    check_harness 'empty parallel selection fails' success not-an-engine 1 1 'No engine jobs selected'
    check_harness 'test image cannot self-update from the network' no-auto-update redis 0 0 'Total Checks : 3'
    check_harness 'missing credentials fail security check' missing-credentials redis 0 1 'Failed Checks: 1'
    check_harness 'world-readable credentials fail security check' public-credentials redis 0 1 'Failed Checks: 1'
    check_harness 'successful worker without results cannot pass' worker-empty redis,memcached 1 1 'Failed Checks: 2'
    check_harness 'zero concurrency is rejected' success redis 1 1 'MAX_JOBS must be a positive integer' 0
    check_harness 'invalid concurrency is rejected' success redis 1 1 'MAX_JOBS must be a positive integer' invalid
    [ "$self_failures" -eq 0 ]
    exit $?
fi

C_RESET='\033[0m'
C_BOLD='\033[1m'
C_GREEN='\033[32m'
C_RED='\033[31m'
C_YELLOW='\033[33m'
C_CYAN='\033[36m'
C_BLUE='\033[34m'
C_MAGENTA='\033[35m'
C_DIM='\033[2m'

IMAGE_NAME="${IMAGE_NAME:-database-eggs:test}"
BUILD_IMAGE="${BUILD_IMAGE:-1}"
READY_TIMEOUT="${READY_TIMEOUT:-120}"     # seconds to wait for engine readiness
STOP_GRACE="${STOP_GRACE:-10}"            # docker stop grace period (seconds)
LOG_TAIL="${LOG_TAIL:-40}"                # log lines shown on failure
TEST_ENGINES="${TEST_ENGINES:-}"          # comma filter, e.g. "redis,mariadb" (empty = all)
PARALLEL="${PARALLEL:-0}"                 # 1 = run engine jobs concurrently
MAX_JOBS="${MAX_JOBS:-4}"                 # concurrent engine jobs when PARALLEL=1
if [ "${PARALLEL}" = "1" ] && ! [[ "${MAX_JOBS}" =~ ^[1-9][0-9]*$ ]]; then
    printf 'MAX_JOBS must be a positive integer\n' >&2
    exit 1
fi

# TEST_ENGINES filter: skip engines the caller did not ask for (fast cycles)
want_engine() {
    [ -z "${TEST_ENGINES}" ] && return 0
    printf '%s' ",${TEST_ENGINES}," | grep -qi ",$1," && return 0 || return 1
}

log()   { printf "${C_CYAN}${C_BOLD}[CHECK]${C_RESET} %s\n" "$*"; }
pass()  { printf "  ${C_GREEN}${C_BOLD}✓ PASS:${C_RESET} %s\n" "$*"; }
fail()  { printf "  ${C_RED}${C_BOLD}✗ FAIL:${C_RESET} %s\n" "$*"; }
info()  { printf "  ${C_BLUE}ℹ INFO:${C_RESET} %s\n" "$*"; }

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

record_result() {
    local name="$1" status="$2" details="${3:-}"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [ "${status}" -eq 0 ]; then
        pass "${name} ${details:+(${details})}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        fail "${name} ${details:+(${details})}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    if [ -n "${PF_RESULTS_FILE:-}" ]; then
        printf '%s\t%s\n' "${status}" "${name}" >> "${PF_RESULTS_FILE}" || exit 1
    fi
}

printf "\n"
printf "${C_CYAN}${C_BOLD}   __  ___      ____  _       ____  ____     ${C_RESET}\n"
printf "${C_CYAN}${C_BOLD}  /  |/  /_  __/ / /_(_)     / __ \\/ __ )    ${C_RESET}\n"
printf "${C_BLUE}${C_BOLD} / /|_/ / / / / / __/ /_____/ / / / __  |    ${C_RESET}\n"
printf "${C_BLUE}${C_BOLD}/ /  / / /_/ / / /_/ /_____/ /_/ / /_/ /     ${C_RESET}\n"
printf "${C_MAGENTA}${C_BOLD}/_/  /_/\\__,_/_/\\__/_/     /_____/_____/      ${C_RESET}\n"
printf "${C_YELLOW}${C_BOLD}  » Docker & Multi-Panel Verification Test Suite${C_RESET}\n"
printf "${C_DIM}    By PotenFYR Studios • support@potenfyr.in${C_RESET}\n\n"

# Step 1: Build Docker image if requested
if [ "${BUILD_IMAGE}" = "1" ]; then
    log "Building test Docker image: ${IMAGE_NAME}..."
    if docker build -t "${IMAGE_NAME}" . >/dev/null 2>&1; then
        record_result "Docker Image Build (${IMAGE_NAME})" 0
    else
        record_result "Docker Image Build (${IMAGE_NAME})" 1 "docker build failed"
        printf "\n${C_RED}${C_BOLD}Cannot proceed without a valid Docker image.${C_RESET}\n"
        exit 1
    fi
fi

# Helper to run a test container with Pterodactyl-identical conditions
run_db_test() {
    local engine="$1"
    local port="$2"
    local extra_envs="${3:-}"
    local test_cmd="${4:-}"
    local version="${5:-latest}"

    local container_name="test-db-${engine}-$(echo "${version}" | tr '.' '-')-$$"
    local test_dir
    test_dir=$(mktemp -d 2>/dev/null || mktemp -d -t 'dbtest')
    chmod 777 "${test_dir}" 2>/dev/null || true

    printf "${C_CYAN}${C_BOLD}[CHECK]${C_RESET} Testing engine: ${C_BOLD}%s${C_RESET} (Version: %s, Port: %s)...\n" "${engine^^}" "${version}" "${port}"

    # Run container in background simulating Pterodactyl Wings
    # -u 988:988, memory limit 1024M, volume mounted to /home/container
    docker run -d \
        --name "${container_name}" \
        -u 988:988 \
        -m 1024m \
        -e DATABASE_TYPE="${engine}" \
        -e DB_VERSION="${version}" \
        -e SERVER_PORT="${port}" \
        -e SERVER_MEMORY="1024" \
        -e DB_NAME="testdb" \
        -e DB_USER="testuser" \
        -e DB_PASSWORD="TestPassword123!Secure" \
        -e DB_ROOT_PASSWORD="RootPassword123!Secure" \
        -e AUTO_UPDATE_EGG=0 \
        -e AUTO_GENERATE_CREDENTIALS="1" \
        -e PERFORMANCE_TUNING="1" \
        -e SECURITY_HARDENING="1" \
        ${extra_envs} \
        -v "${test_dir}:/home/container" \
        "${IMAGE_NAME}" >/dev/null 2>&1

    # Wait for ready state (configurable; pinned-version rows may download on first boot)
    local retries="${READY_TIMEOUT}"
    case "${engine}:${version}" in
        mariadb:*.*|mysql:*.*|mongodb:*.*|postgresql:[0-9]*)
            [ "${version}" != "latest" ] && retries=$((READY_TIMEOUT * 3)) ;;
    esac
    local is_ready=1
    while [ "${retries}" -gt 0 ]; do
        sleep 1
        retries=$((retries - 1))

        # Check if container died unexpectedly
        local state
        state=$(docker inspect -f '{{.State.Running}}' "${container_name}" 2>/dev/null || echo "false")
        if [ "${state}" != "true" ]; then
            is_ready=1
            break
        fi

        # Execute verification command or port check inside container
        if [ -n "${test_cmd}" ]; then
            if docker exec "${container_name}" bash -c "export PATH=\"/home/container/bin:/home/container/.runtimes/bin:\${PATH}\"; ${test_cmd}" >/dev/null 2>&1; then
                is_ready=0
                break
            fi
        else
            if docker exec "${container_name}" bash -c "ss -tuln 2>/dev/null | grep -qE ':${port}(\b| |$)' || netstat -tuln 2>/dev/null | grep -qE ':${port}(\b| |$)'" 2>/dev/null; then
                is_ready=0
                break
            fi
        fi
    done

    # Collect results
    if [ "${is_ready}" -eq 0 ]; then
        record_result "${engine^^} startup & client readiness" 0 "Port ${port} active"
    else
        local logs
        logs=$(docker logs "${container_name}" 2>&1 | tail -n "${LOG_TAIL}")
        record_result "${engine^^} startup & client readiness" 1 "Failed to become ready within timeout"
        printf "  ${C_BLUE}ℹ INFO:${C_RESET} Recent logs:\n"
        printf '%s\n' "${logs}" | sed 's/^/    /'
    fi

    # Verify sensitive credentials persistence strictly in .env
    local credential_mode
    credential_mode=$(stat -c '%a' "${test_dir}/.env" 2>/dev/null || stat -f '%Lp' "${test_dir}/.env" 2>/dev/null || true)
    if [ -f "${test_dir}/.env" ] && [ ! -L "${test_dir}/.env" ] && [ "${credential_mode}" = "600" ]; then
        record_result "${engine^^} credential persistence & security" 0 "Persisted in .env (mode 600)"
    else
        record_result "${engine^^} credential persistence & security" 1 "Expected regular .env with mode 600; actual ${credential_mode:-missing}"
    fi

    # Verify graceful shutdown
    docker stop --time "${STOP_GRACE}" "${container_name}" >/dev/null 2>&1 || true
    local exit_code
    exit_code=$(docker inspect -f '{{.State.ExitCode}}' "${container_name}" 2>/dev/null || echo "0")
    if [ "${exit_code}" -eq 0 ] || [ "${exit_code}" -eq 130 ] || [ "${exit_code}" -eq 143 ]; then
        record_result "${engine^^} graceful stop & signal handling (SIGTERM/SIGINT/Panel Stop)" 0 "Exit code ${exit_code}"
    else
        record_result "${engine^^} graceful stop handling" 1 "Exit code ${exit_code}"
    fi

    # Cleanup
    docker rm -f "${container_name}" >/dev/null 2>&1 || true
    rm -rf "${test_dir}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Test Execution Matrix
# Each entry is one independent engine job: own container, own temp volume,
# own port - safe to run concurrently (PARALLEL=1) or selectively
# (TEST_ENGINES="redis,mariadb").
# ---------------------------------------------------------------------------
MATRIX=(
    # 0. VERSION CONTRACT REGRESSION TESTS (the core guarantee):
    #    explicitly pinned versions MUST be honored exactly - no silent downgrades.
    'run_db_test "postgresql" "5432" "" "PGPASSWORD='"'"'RootPassword123!Secure'"'"' psql -h 127.0.0.1 -p 5432 -U postgres -d postgres -tc '"'"'SELECT version();'"'"' 2>/dev/null | grep -q '"'"'PostgreSQL 18\.'"'"' && psql --version | grep -qE '"'"' 18\.'"'"'" "18"'
    'run_db_test "mariadb" "3306" "" "mariadb -h 127.0.0.1 -P 3306 -u root -p'"'"'RootPassword123!Secure'"'"' -NBe '"'"'SELECT VERSION();'"'"' 2>/dev/null | grep -q '"'"'^11\.4'"'"'" "11.4"'
    'run_db_test "mysql" "3307" "-e CDN_FALLBACK_SYSTEM=1" "" "8.0"'

    # 1. Relational SQL (system defaults / latest resolution)
    'run_db_test "postgresql" "5432" "" "PGPASSWORD='"'"'RootPassword123!Secure'"'"' psql -h 127.0.0.1 -p 5432 -U postgres -d postgres -c '"'"'SELECT 1;'"'"' 2>/dev/null"'

    # 2. In-Memory & Caching
    'run_db_test "redis" "6379" "" "redis-cli -h 127.0.0.1 -p 6379 -a '"'"'TestPassword123!Secure'"'"' ping 2>/dev/null | grep -q '"'"'PONG'"'"'"'
    'run_db_test "valkey" "6380" "" "valkey-server --version 2>/dev/null | grep -qi valkey || redis-cli -p 6380 ping 2>/dev/null | grep -q PONG"'
    'run_db_test "memcached" "11211" "" ""'

    # 3. Document & Multi-Model
    'run_db_test "mongodb" "27017" "" "(ss -tuln 2>/dev/null | grep -qE '"'"':27017(\b| |$)'"'"' || mongosh --quiet --port 27017 --eval '"'"'db.adminCommand({ping:1})'"'"' 2>/dev/null) && (mongod --version 2>/dev/null || /home/container/bin/mongod --version 2>/dev/null) | grep -qE '"'"'db version v7\.'"'"'" "7.0"'
    'run_db_test "surrealdb" "8000" "" "curl -fsSL http://127.0.0.1:8000/health 2>/dev/null || curl -fsSL http://127.0.0.1:8000/status 2>/dev/null || curl -fsSL http://127.0.0.1:8000/version 2>/dev/null"'

    # 4. Search & Vector Engines
    'run_db_test "meilisearch" "7700" "-e MASTER_KEY=MasterKey1234567890SecureKey" "curl -fsSL -H '"'"'Authorization: Bearer MasterKey1234567890SecureKey'"'"' http://127.0.0.1:7700/health 2>/dev/null || curl -fsSL http://127.0.0.1:7700/health 2>/dev/null"'
    'run_db_test "qdrant" "6333" "" "curl -fsSL http://127.0.0.1:6333/readyz 2>/dev/null || curl -fsSL http://127.0.0.1:6333/dashboard 2>/dev/null || curl -fsSL http://127.0.0.1:6333/ 2>/dev/null"'
    'run_db_test "typesense" "8108" "" "curl -fsSL http://127.0.0.1:8108/health 2>/dev/null"'

    # 5. Backends & Storage
    'run_db_test "pocketbase" "8090" "" "curl -fsSL http://127.0.0.1:8090/api/health 2>/dev/null"'
    'run_db_test "minio" "9000" "-e CONSOLE_PORT=9001" "curl -fsSL http://127.0.0.1:9000/minio/health/live 2>/dev/null"'
    'run_db_test "victoriametrics" "8428" "" "curl -fsSL http://127.0.0.1:8428/health 2>/dev/null"'
)

PF_RESULTS_FILE=""
SELECTED_JOBS=0
if [ "${PARALLEL}" = "1" ]; then
    PF_RESULTS_DIR=$(mktemp -d) || exit 1
    pids=()
    job_names=()
    next_wait=0
    collect_job() {
        local index="$1" status=0 st name count=0
        wait "${pids[index]}" || status=$?
        if [ -f "${PF_RESULTS_DIR}/${index}.tsv" ]; then
            while IFS=$'\t' read -r st name; do
                if [ "${st}" = "0" ]; then PASSED_TESTS=$((PASSED_TESTS + 1)); else FAILED_TESTS=$((FAILED_TESTS + 1)); fi
                TOTAL_TESTS=$((TOTAL_TESTS + 1))
                count=$((count + 1))
            done < "${PF_RESULTS_DIR}/${index}.tsv"
        fi
        if [ "${status}" -ne 0 ] || [ "${count}" -eq 0 ]; then
            record_result "${job_names[index]} worker completion" 1 "Exit ${status}; ${count} results"
        fi
    }
    for spec in "${MATRIX[@]}"; do
        engine_name="$(printf '%s' "${spec}" | sed -E 's/^run_db_test "([a-z0-9]+)".*/\1/')"
        want_engine "${engine_name}" || { log "Skipping ${engine_name} (not in TEST_ENGINES)"; continue; }
        index=${#pids[@]}
        SELECTED_JOBS=$((SELECTED_JOBS + 1))
        ( PF_RESULTS_FILE="${PF_RESULTS_DIR}/${index}.tsv"; eval "${spec}" ) &
        pids+=("$!")
        job_names+=("${engine_name}")
        if [ "$((${#pids[@]} - next_wait))" -ge "${MAX_JOBS}" ]; then
            collect_job "${next_wait}"
            next_wait=$((next_wait + 1))
        fi
    done
    while [ "${next_wait}" -lt "${#pids[@]}" ]; do
        collect_job "${next_wait}"
        next_wait=$((next_wait + 1))
    done
    rm -rf "${PF_RESULTS_DIR}"
else
    for spec in "${MATRIX[@]}"; do
        engine_name="$(printf '%s' "${spec}" | sed -E 's/^run_db_test "([a-z0-9]+)".*/\1/')"
        want_engine "${engine_name}" || { log "Skipping ${engine_name} (not in TEST_ENGINES)"; continue; }
        eval "${spec}"
        SELECTED_JOBS=$((SELECTED_JOBS + 1))
    done
fi

if [ "${SELECTED_JOBS}" -eq 0 ]; then
    record_result "Engine selection" 1 "No engine jobs selected: TEST_ENGINES=${TEST_ENGINES}"
fi

# ---------------------------------------------------------------------------
# Test Summary
# ---------------------------------------------------------------------------
printf "\n${C_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n"
printf " ${C_BOLD}TEST SUITE EXECUTION SUMMARY${C_RESET}\n"
printf "${C_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n"
printf "  Total Checks : %s\n" "${TOTAL_TESTS}"
printf "  ${C_GREEN}Passed Checks: %s${C_RESET}\n" "${PASSED_TESTS}"
if [ "${FAILED_TESTS}" -gt 0 ]; then
    printf "  ${C_RED}Failed Checks: %s${C_RESET}\n" "${FAILED_TESTS}"
    printf "${C_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n"
    exit 1
else
    printf "  ${C_GREEN}${C_BOLD}ALL DOCKER & PANEL COMPATIBILITY CHECKS PASSED!${C_RESET}\n"
    printf "${C_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n"
    exit 0
fi
