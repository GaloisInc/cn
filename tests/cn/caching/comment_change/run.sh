#!/bin/bash
set -e

echo "=== Test: Comment Change (should NOT re-verify) ==="
echo

rm -f .cn/verification.db foo.c

echo "1. Initial verification with foo_1.c:"
cp foo_1.c foo.c
cn verify --use-db foo.c 2>&1 | grep -E "^\[|pass|fail" || echo "(all verified)"
echo

echo "2. Re-run with same file (should skip):"
cn verify --use-db foo.c 2>&1 | grep -E "^\[|pass|fail" || echo "(all skipped)"
echo

echo "3. Change comment and re-run:"
cp foo_2.c foo.c
cn verify --use-db foo.c 2>&1 | grep -E "^\[|pass|fail" || echo "(all skipped)"
echo

echo "✓ Expected: skipped in steps 2 and 3 (comments don't affect spec hash)"
