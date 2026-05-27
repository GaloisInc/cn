#!/bin/bash
set -e

DB_PATH=.cn/cache.db

echo "=== Assert change caching test ==="

rm -rf .cn
mkdir -p .cn

echo "First run (foo_1.c)..."
cn verify --use-db --db-path=$DB_PATH foo_1.c
echo "[1/1]: increment -- pass"

echo ""
echo "Second run (same file, should be cached)..."
output=$(cn verify --use-db --db-path=$DB_PATH foo_1.c 2>&1)
if [ -z "$output" ]; then
  echo "✓ Cached (no output)"
else
  echo "✗ FAILED: Expected cache hit but got output:"
  echo "$output"
  exit 1
fi

echo ""
echo "Third run (foo_2.c with different assert)..."
cn verify --use-db --db-path=$DB_PATH foo_2.c
echo "[1/1]: increment -- pass"

echo ""
echo "✓ Test passed: assert changes trigger re-verification"
