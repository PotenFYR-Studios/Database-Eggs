set -u
docker rm -f db-redis-fix >/dev/null 2>&1
docker run -d --name db-redis-fix -e P_SERVER_UUID=11111111-2222-3333-4444-555555555555 -e DATABASE_TYPE=redis -e DB_VERSION=8.2 -e SERVER_PORT=16379 -e SERVER_MEMORY=512 -e AUTO_UPDATE_EGG=0 -e "DB_PASSWORD=TestPassword123!Secure" -e "DB_ROOT_PASSWORD=RootPassword123!Secure" dbeggs-test >/dev/null
booted=0
for i in $(seq 1 240); do docker logs db-redis-fix 2>&1 | grep -q "Ready to accept connections" && { booted=1; break; }; sleep 1; done
echo "== boot: ${booted} =="
docker logs db-redis-fix 2>&1 | grep -aE "Provisioned redis|resolved for redis|Falling back|fallback|Verified|verified|Ready to accept|archived|cannot be compiled" | head -n 14
echo "== ping =="
docker exec db-redis-fix redis-cli -h 127.0.0.1 -p 16379 -a "TestPassword123!Secure" ping 2>/dev/null
echo "== provisioned binary =="
docker exec db-redis-fix /home/container/bin/redis-server --version 2>/dev/null || echo "(no bin/redis-server)"
docker exec db-redis-fix ls /home/container/bin 2>/dev/null | head -n 8
