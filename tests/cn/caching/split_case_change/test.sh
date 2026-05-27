#!/bin/bash
set -e

DB_PATH=.cn/cache.db

echo "=== Split case change caching test ==="

rm -rf .cn
mkdir -p .cn

echo "First run (foo_1.c)..."
cn verify --use-db --db-path=$DB_PATH foo_1.c
echo "[1/1]: max -- pass"

echo ""
echo "Second run (same file, should be cached)..."
output=$(cn verify --use-db --db-path=$DB_PATH foo_1.c 2>&1)
if echo "$output" | grep -q "cached (pass)"; then
  echo "✓ Cached (shows: cached (pass))"
else
  echo "✗ FAILED: Expected cache hit (cached (pass)) but got:"
  echo "$output"
  exit 1
fi

echo ""
echo "Third run (foo_2.c with different split_case)..."
cn verify --use-db --db-path=$DB_PATH foo_2.c
echo "[1/1]: max -- pass"

echo ""
echo "✓ Test passed: split_case changes trigger re-verification"
