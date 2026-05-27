#!/bin/bash
set -e

echo "=== Test: Spec Change (should re-verify) ==="
echo

# Clean slate
rm -f .cn/verification.db foo.c

# First run
echo "1. Initial verification with foo_1.c:"
cp foo_1.c foo.c
cn verify --use-db foo.c 2>&1 | grep -E "^\[|pass|fail" || echo "(all verified)"
echo

# Second run - no changes
echo "2. Re-run with same file (should skip):"
cn verify --use-db foo.c 2>&1 | grep -E "^\[|pass|fail" || echo "(all skipped)"
echo

# Third run - spec changed
echo "3. Change spec (x >= 0i32 → x >= 1i32) and re-run:"
cp foo_2.c foo.c
cn verify --use-db foo.c 2>&1 | grep -E "^\[|pass|fail" || echo "(unexpected result)"
echo

# Fourth run - no further changes
echo "4. Re-run with same changed file (should skip):"
cn verify --use-db foo.c 2>&1 | grep -E "^\[|pass|fail" || echo "(all skipped)"
echo

echo "✓ Expected: re-verified in step 3, skipped in steps 2 and 4"
