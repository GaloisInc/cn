#!/bin/bash
set -e

# Test loop invariant change triggers re-verification

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB="/tmp/cn_test_loop_inv.db"

echo "==========================================="
echo "=== Test: Loop Invariant Change (should re-verify) ==="
echo ""

rm -f "$DB"

echo "1. Initial verification with foo_1.c:"
cn verify --use-db --db-path="$DB" "$DIR/foo_1.c" 2>&1 | grep -E "^\[" || true
echo ""

echo "2. Re-run with same file (should skip):"
cn verify --use-db --db-path="$DB" "$DIR/foo_1.c" 2>&1 | grep -E "^\[|cached" || true
echo ""

echo "3. Change loop invariant (i*(i+1) → i*(i-1)) and re-run:"
cn verify --use-db --db-path="$DB" "$DIR/foo_2.c" 2>&1 | grep -E "^\[|cached" || true
echo ""

echo "4. Re-run with same changed file (should skip):"
cn verify --use-db --db-path="$DB" "$DIR/foo_2.c" 2>&1 | grep -E "^\[|cached" || true
echo ""

echo "✓ Expected: re-verified in step 3, skipped in steps 2 and 4"
echo "==========================================="
echo ""
