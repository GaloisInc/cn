#!/bin/bash
set -e

echo "=== Test: Argument Rename (currently re-verifies, shouldn't with alpha-renaming) ==="
echo

rm -f .cn/verification.db foo.c

echo "1. Initial verification with foo_1.c:"
cp foo_1.c foo.c
cn verify --use-db foo.c 2>&1 | grep -E "^\[|pass|fail" || echo "(all verified)"
echo

echo "2. Re-run with same file (should skip):"
cn verify --use-db foo.c 2>&1 | grep -E "^\[|pass|fail" || echo "(all skipped)"
echo

echo "3. Rename arguments (x→a, y→b) and re-run:"
cp foo_2.c foo.c
cn verify --use-db foo.c 2>&1 | grep -E "^\[|pass|fail" || echo "(re-verified)"
echo

echo "✗ Current: re-verifies in step 3"
echo "✓ Desired: should skip (semantically equivalent after alpha-renaming)"
