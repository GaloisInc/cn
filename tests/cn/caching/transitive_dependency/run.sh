#!/bin/bash
set -e

echo "=== Test: Transitive Dependency (use_middle → middle → base) ==="
echo

rm -f .cn/verification.db foo.c

echo "1. Initial verification:"
cp foo_1.c foo.c
cn verify --use-db foo.c 2>&1 | grep -E "^\[|pass|fail" || echo "(all verified)"
echo

echo "2. Re-run (should skip):"
cn verify --use-db foo.c 2>&1 | grep -E "^\[|pass|fail" || echo "(all skipped)"
echo

echo "3. Change 'base' function (x+1 → x+2):"
echo "   use_middle depends on middle, middle depends on base"
cp foo_2.c foo.c
cn verify --use-db foo.c 2>&1 | grep -E "^\[|pass|fail" || echo "(unexpected)"
echo

echo "Question: Should use_middle be re-verified when base changes?"
echo "Answer: No in current implementation (only direct dependencies checked)"
