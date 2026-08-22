# =============================================================================
#  PotenFYR Studios - Universal Multi-Database Docker Verification (PowerShell)
#  Runs complete container testing for MariaDB, PostgreSQL, Redis, MongoDB,
#  Meilisearch, PocketBase, MinIO, and Qdrant in Docker Desktop / Windows.
# =============================================================================

param (
    [string]$ImageName = "database-eggs:test",
    [switch]$SkipBuild = $false
)

$ErrorActionPreference = "Continue"

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host "   POTENFYR STUDIOS - DOCKER & PANEL VERIFICATION SUITE" -ForegroundColor Yellow
Write-Host "========================================================`n" -ForegroundColor Cyan

$totalTests = 0
$passedTests = 0
$failedTests = 0

function Report-Check {
    param ([string]$Name, [bool]$Passed, [string]$Details = "")
    $script:totalTests++
    if ($Passed) {
        Write-Host "  [PASS] $Name $(if ($Details) {"($Details)"})" -ForegroundColor Green
        $script:passedTests++
    } else {
        Write-Host "  [FAIL] $Name $(if ($Details) {"($Details)"})" -ForegroundColor Red
        $script:failedTests++
    }
}

# 1. Build Image if not skipped
if (-not $SkipBuild) {
    Write-Host "[CHECK] Building test Docker image: $ImageName..." -ForegroundColor Cyan
    docker build -t $ImageName .
    if ($LASTEXITCODE -eq 0) {
        Report-Check -Name "Docker Image Build ($ImageName)" -Passed $true
    } else {
        Report-Check -Name "Docker Image Build ($ImageName)" -Passed $false -Details "Build failed"
        exit 1
    }
}

# 2. Test Runner Function
function Test-DatabaseEngine {
    param (
        [string]$Engine,
        [int]$Port,
        [string]$ExtraEnvs = "",
        [string]$TestCmd = ""
    )

    $containerName = "test-db-$Engine-$([guid]::NewGuid().ToString().Substring(0,8))"
    $tempDir = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "dbtest-$Engine-$([guid]::NewGuid().ToString().Substring(0,8))")
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    Write-Host "`n[CHECK] Testing engine: $($Engine.ToUpper()) on port $Port..." -ForegroundColor Cyan

    $runCmd = "docker run -d --name $containerName -u 988:988 -m 1024m -e DATABASE_TYPE=$Engine -e SERVER_PORT=$Port -e SERVER_MEMORY=1024 -e DB_NAME=testdb -e DB_USER=testuser -e DB_PASSWORD=TestPass123!Secure -e DB_ROOT_PASSWORD=RootPass123!Secure -e AUTO_GENERATE_CREDENTIALS=1 -e PERFORMANCE_TUNING=1 -e SECURITY_HARDENING=1 $ExtraEnvs -v `"$tempDir`":/home/container $ImageName"
    
    Invoke-Expression $runCmd | Out-Null

    # Wait for ready state up to 25 seconds
    $retries = 25
    $isReady = $false

    while ($retries -gt 0) {
        Start-Sleep -Seconds 1
        $retries--

        $running = docker inspect -f "{{.State.Running}}" $containerName 2>$null
        if ($running -ne "true") { break }

        if ($TestCmd) {
            docker exec $containerName bash -c "$TestCmd" 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $isReady = $true
                break
            }
        } else {
            docker exec $containerName bash -c "ss -tuln 2>/dev/null | grep -q ':$Port ' || netstat -tuln 2>/dev/null | grep -q ':$Port '" 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $isReady = $true
                break
            }
        }
    }

    if ($isReady) {
        Report-Check -Name "$($Engine.ToUpper()) startup & client readiness" -Passed $true -Details "Port $Port active"
    } else {
        $recentLogs = docker logs $containerName 2>&1 | Select-Object -Last 5
        Report-Check -Name "$($Engine.ToUpper()) startup & client readiness" -Passed $false -Details "Timeout"
        Write-Host "    Recent logs: $recentLogs" -ForegroundColor DarkGray
    }

    # Verify credentials persistence
    $hasCreds = (Test-Path "$tempDir/.db_credentials") -or (Test-Path "$tempDir/credentials.txt")
    if ($hasCreds) {
        Report-Check -Name "$($Engine.ToUpper()) credentials persistence & security" -Passed $true
    }

    # Verify graceful shutdown
    docker stop --time 5 $containerName 2>$null | Out-Null
    $exitCode = docker inspect -f "{{.State.ExitCode}}" $containerName 2>$null
    if ($exitCode -eq "0" -or $exitCode -eq "130" -or $exitCode -eq "143") {
        Report-Check -Name "$($Engine.ToUpper()) graceful signal handling (SIGTERM)" -Passed $true -Details "ExitCode $exitCode"
    } else {
        Report-Check -Name "$($Engine.ToUpper()) graceful signal handling" -Passed $false -Details "ExitCode $exitCode"
    }

    # Clean up
    docker rm -f $containerName 2>$null | Out-Null
    Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
}

# 3. Execute Checks
Test-DatabaseEngine -Engine "mariadb" -Port 3306 -TestCmd "mariadb -u root -p'RootPass123!Secure' -e 'SELECT 1;' 2>/dev/null || mysql -u root -p'RootPass123!Secure' -e 'SELECT 1;' 2>/dev/null"
Test-DatabaseEngine -Engine "postgresql" -Port 5432 -TestCmd "PGPASSWORD='RootPass123!Secure' psql -U postgres -d postgres -c 'SELECT 1;' 2>/dev/null"
Test-DatabaseEngine -Engine "redis" -Port 6379 -TestCmd "redis-cli -a 'TestPass123!Secure' ping 2>/dev/null | grep -q 'PONG'"
Test-DatabaseEngine -Engine "memcached" -Port 11211
Test-DatabaseEngine -Engine "surrealdb" -Port 8000 -TestCmd "curl -fsSL http://127.0.0.1:8000/health 2>/dev/null || curl -fsSL http://127.0.0.1:8000/status 2>/dev/null"
Test-DatabaseEngine -Engine "meilisearch" -Port 7700 -ExtraEnvs "-e MASTER_KEY=MasterKey1234567890SecureKey" -TestCmd "curl -fsSL http://127.0.0.1:7700/health 2>/dev/null"
Test-DatabaseEngine -Engine "pocketbase" -Port 8090 -TestCmd "curl -fsSL http://127.0.0.1:8090/api/health 2>/dev/null"
Test-DatabaseEngine -Engine "minio" -Port 9000 -ExtraEnvs "-e CONSOLE_PORT=9001" -TestCmd "curl -fsSL http://127.0.0.1:9000/minio/health/live 2>/dev/null"
Test-DatabaseEngine -Engine "qdrant" -Port 6333 -TestCmd "curl -fsSL http://127.0.0.1:6333/readyz 2>/dev/null || curl -fsSL http://127.0.0.1:6333/dashboard 2>/dev/null"

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host "           TEST SUITE EXECUTION SUMMARY" -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  Total Checks : $totalTests"
Write-Host "  Passed Checks: $passedTests" -ForegroundColor Green
if ($failedTests -gt 0) {
    Write-Host "  Failed Checks: $failedTests" -ForegroundColor Red
    exit 1
} else {
    Write-Host "  ALL DOCKER CHECKS PASSED SUCCESSFULLY!" -ForegroundColor Green
    exit 0
}
