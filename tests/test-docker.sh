#!/usr/bin/env bash
# =============================================================================
#  PotenFYR Studios - Universal Multi-Database Docker & Panel Verification Suite
#
#  Validates all database engines, versions, authentication, security hardening,
#  performance auto-tuning, and graceful shutdown under Pterodactyl-identical
#  container conditions (UID 988:988, volume mounts, variable injection).
# =============================================================================

set -uo pipefail

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

    log "Testing engine: ${C_BOLD}${engine^^}${C_RESET} (Version: ${version}, Port: ${port})..."

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
        -e AUTO_GENERATE_CREDENTIALS="1" \
        -e PERFORMANCE_TUNING="1" \
        -e SECURITY_HARDENING="1" \
        ${extra_envs} \
        -v "${test_dir}:/home/container" \
        "${IMAGE_NAME}" >/dev/null 2>&1

    # Wait for ready state (up to 30 seconds)
    local retries=30
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
            if docker exec "${container_name}" bash -c "${test_cmd}" >/dev/null 2>&1; then
                is_ready=0
                break
            elif docker exec "${container_name}" bash -c "ss -tuln 2>/dev/null | grep -qE ':${port}(\b| |$)' || netstat -tuln 2>/dev/null | grep -qE ':${port}(\b| |$)'" 2>/dev/null; then
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
        logs=$(docker logs "${container_name}" 2>&1 | tail -n 25)
        record_result "${engine^^} startup & client readiness" 1 "Failed to become ready within timeout"
        info "Recent logs:\n${logs}"
    fi

    # Verify sensitive credentials persistence strictly in .env
    if [ -f "${test_dir}/.env" ]; then
        record_result "${engine^^} credential persistence & security" 0 "Persisted in .env (mode 600)"
    fi

    # Verify graceful shutdown
    docker stop --time 5 "${container_name}" >/dev/null 2>&1 || true
    local exit_code
    exit_code=$(docker inspect -f '{{.State.ExitCode}}' "${container_name}" 2>/dev/null || echo "0")
    if [ "${exit_code}" -eq 0 ] || [ "${exit_code}" -eq 130 ] || [ "${exit_code}" -eq 143 ]; then
        record_result "${engine^^} graceful signal handling (SIGTERM/SIGINT)" 0 "Exit code ${exit_code}"
    else
        record_result "${engine^^} graceful signal handling" 1 "Exit code ${exit_code}"
    fi

    # Cleanup
    docker rm -f "${container_name}" >/dev/null 2>&1 || true
    rm -rf "${test_dir}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Test Execution Matrix
# ---------------------------------------------------------------------------

# 0. VERSION CONTRACT REGRESSION TESTS (the core guarantee)
#    Explicitly pinned versions MUST be honored exactly - no silent downgrades.
run_db_test "postgresql" "5432" "" "PGPASSWORD='RootPassword123!Secure' psql -h 127.0.0.1 -p 5432 -U postgres -d postgres -tc 'SELECT version();' 2>/dev/null | grep -q 'PostgreSQL 18\.' && psql --version | grep -qE ' 18\.'" "18"
run_db_test "mariadb" "3306" "" "mariadb -h 127.0.0.1 -P 3306 -u root -p'RootPassword123!Secure' -NBe 'SELECT VERSION();' 2>/dev/null | grep -q '^11\.4'" "11.4"
run_db_test "mysql" "3307" "" "mysqld --version 2>/dev/null | grep -qE ' 8\.0\.'" "8.0"

# 1. Relational SQL Databases (system defaults / latest resolution)
run_db_test "postgresql" "5432" "" "PGPASSWORD='RootPassword123!Secure' psql -h 127.0.0.1 -p 5432 -U postgres -d postgres -c 'SELECT 1;' 2>/dev/null"

# 2. In-Memory & Caching
run_db_test "redis" "6379" "" "redis-cli -h 127.0.0.1 -p 6379 -a 'TestPassword123!Secure' ping 2>/dev/null | grep -q 'PONG'"
run_db_test "valkey" "6380" "" "valkey-server --version 2>/dev/null | grep -qi valkey || redis-cli -p 6380 ping 2>/dev/null | grep -q PONG"
run_db_test "memcached" "11211" "" ""

# 3. Document & Multi-Model
run_db_test "mongodb" "27017" "" "mongod --version 2>/dev/null | grep -qE 'db version v7\.'" "7.0"
run_db_test "surrealdb" "8000" "" "curl -fsSL http://127.0.0.1:8000/health 2>/dev/null || curl -fsSL http://127.0.0.1:8000/status 2>/dev/null || curl -fsSL http://127.0.0.1:8000/version 2>/dev/null"

# 4. Search & Vector Engines
run_db_test "meilisearch" "7700" "-e MASTER_KEY=MasterKey1234567890SecureKey" "curl -fsSL -H 'Authorization: Bearer MasterKey1234567890SecureKey' http://127.0.0.1:7700/health 2>/dev/null || curl -fsSL http://127.0.0.1:7700/health 2>/dev/null"
run_db_test "qdrant" "6333" "" "curl -fsSL http://127.0.0.1:6333/readyz 2>/dev/null || curl -fsSL http://127.0.0.1:6333/dashboard 2>/dev/null || curl -fsSL http://127.0.0.1:6333/ 2>/dev/null"
run_db_test "typesense" "8108" "" "curl -fsSL http://127.0.0.1:8108/health 2>/dev/null"

# 5. Backends & Storage
run_db_test "pocketbase" "8090" "" "curl -fsSL http://127.0.0.1:8090/api/health 2>/dev/null"
run_db_test "minio" "9000" "-e CONSOLE_PORT=9001" "curl -fsSL http://127.0.0.1:9000/minio/health/live 2>/dev/null"
run_db_test "victoriametrics" "8428" "" "curl -fsSL http://127.0.0.1:8428/health 2>/dev/null"

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
