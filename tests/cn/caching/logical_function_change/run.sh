#!/bin/bash
set -e

echo "=== Test: Logical Function Change (should re-verify dependents) ==="
echo

rm -f .cn/verification.db foo.c

echo "1. Initial verification with foo_1.c:"
cp foo_1.c foo.c
cn verify --use-db foo.c 2>&1 | grep -E "^\[|pass|fail" || echo "(all verified)"
echo

echo "2. Re-run with same file (should skip):"
cn verify --use-db foo.c 2>&1 | grep -E "^\[|pass|fail" || echo "(all skipped)"
echo

echo "3. Change logical function (x+x → x*2) and re-run:"
cp foo_2.c foo.c
cn verify --use-db foo.c 2>&1 | grep -E "^\[|pass|fail" || echo "(unexpected result)"
echo

echo "✓ Expected: use_func re-verified in step 3 due to logical function dependency change"
