#!/bin/bash
set -e

echo "=== Test: Struct Definition Change (should re-verify dependents) ==="
echo

rm -f .cn/verification.db foo.c

echo "1. Initial verification with foo_1.c:"
cp foo_1.c foo.c
cn verify --use-db foo.c 2>&1 | grep -E "^\[|pass|fail" || echo "(all verified)"
echo

echo "2. Re-run with same file (should skip):"
cn verify --use-db foo.c 2>&1 | grep -E "^\[|pass|fail" || echo "(all skipped)"
echo

echo "3. Change struct (add field z) and re-run:"
cp foo_2.c foo.c
cn verify --use-db foo.c 2>&1 | grep -E "^\[|pass|fail" || echo "(unexpected result)"
echo

echo "✓ Expected: get_x re-verified in step 3 due to struct Point change"
