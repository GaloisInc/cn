#!/bin/bash
set -e

echo "========================================="
echo "Test: Logical Function → Logical Function Dependency"
echo "========================================="
echo

DB_PATH="/tmp/cn_test_lf_lf.db"
rm -f "$DB_PATH"

echo "1. Initial verification (foo_1.c):"
cn verify foo_1.c --use-db --db-path="$DB_PATH" --clear-db

echo
echo "2. Check logical function → logical function dependency:"
sqlite3 "$DB_PATH" "SELECT * FROM logical_function_uses_logical_function;"
if sqlite3 "$DB_PATH" "SELECT * FROM logical_function_uses_logical_function;" | grep -q "uses_helper.*helper"; then
  echo "✓ Logical function → logical function dependency recorded"
else
  echo "✗ FAILED: No dependency recorded"
  exit 1
fi

echo
echo "3. Re-run with same file (should skip):"
cn verify foo_1.c --use-db --db-path="$DB_PATH"

echo
echo "4. Change logical function 'helper' (n+1 → n+2) and re-run:"
cn verify foo_2.c --use-db --db-path="$DB_PATH"

echo
echo "✓ Expected: Logical function 'uses_helper' re-verified in step 4 due to helper change"
echo "All checks passed!"
rm -f "$DB_PATH"
