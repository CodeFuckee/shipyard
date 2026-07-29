#!/usr/bin/env bash
set -e

echo "=== CI Selenium Test Runner ==="

echo "[1/7] docker version check"
docker --version
docker compose version

echo "[2/7] verify files"
ls -la docker-compose.test.yml Dockerfile.selenium.cn

echo "[3/7] compose config"
docker compose -f docker-compose.test.yml config

echo "[4/7] build images"
export BUILDKIT_PROGRESS=plain
docker compose -f docker-compose.test.yml build

echo "[5/7] start app service"
docker compose -f docker-compose.test.yml up -d app

echo "[6/7] wait for app"
for i in $(seq 1 30); do
  if curl -sf http://localhost:9000/info > /dev/null 2>&1; then
    echo "app ready"
    break
  fi
  echo "wait $i/30"
  sleep 1
done

echo "[7/7] run tests"
docker compose -f docker-compose.test.yml run --rm selenium-tests sh -c "pytest tests/ -v --html=reports/report.html --self-contained-html"

echo "=== cleanup ==="
docker compose -f docker-compose.test.yml down
echo "=== ALL DONE ==="
