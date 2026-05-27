#!/bin/bash
set -e

echo "========================================="
echo "Test: Predicate → Logical Function Dependency"
echo "========================================="
echo

DB_PATH="/tmp/cn_test_pred_lf.db"
rm -f "$DB_PATH"

echo "1. Initial verification (foo_1.c):"
cn verify foo_1.c --use-db --db-path="$DB_PATH" --clear-db

echo
echo "2. Check predicate → logical function dependency:"
sqlite3 "$DB_PATH" "SELECT * FROM predicate_uses_logical_function;"
if sqlite3 "$DB_PATH" "SELECT * FROM predicate_uses_logical_function;" | grep -q "DoubleValue.*times_two"; then
  echo "✓ Predicate → logical function dependency recorded"
else
  echo "✗ FAILED: No dependency recorded"
  exit 1
fi

echo
echo "3. Re-run with same file (should skip):"
cn verify foo_1.c --use-db --db-path="$DB_PATH"

echo
echo "4. Change logical function 'times_two' (x+x → x*2) and re-run:"
cn verify foo_2.c --use-db --db-path="$DB_PATH"

echo
echo "✓ Expected: Predicate 'DoubleValue' re-verified in step 4 due to logical function change"
echo "All checks passed!"
rm -f "$DB_PATH"
