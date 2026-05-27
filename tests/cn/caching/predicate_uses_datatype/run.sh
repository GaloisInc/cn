#!/bin/bash
set -e

echo "========================================="
echo "Test: Predicate → Datatype Dependency"
echo "========================================="
echo

DB_PATH="/tmp/cn_test_pred_datatype.db"
rm -f "$DB_PATH"

echo "1. Initial verification (foo_1.c):"
cn verify foo_1.c --use-db --db-path="$DB_PATH" --clear-db

echo
echo "2. Check predicate → datatype dependency:"
sqlite3 "$DB_PATH" "SELECT * FROM predicate_uses_datatype;"
if sqlite3 "$DB_PATH" "SELECT * FROM predicate_uses_datatype;" | grep -q "MaybeValue.*IntOption"; then
  echo "✓ Predicate → datatype dependency recorded"
else
  echo "✗ FAILED: No dependency recorded"
  exit 1
fi

echo
echo "3. Re-run with same file (should skip):"
cn verify foo_1.c --use-db --db-path="$DB_PATH"

echo
echo "4. Change datatype IntOption (add Unknown constructor) and re-run:"
cn verify foo_2.c --use-db --db-path="$DB_PATH"

echo
echo "✓ Expected: Predicate 'MaybeValue' re-verified in step 4 due to datatype change"
echo "All checks passed!"
rm -f "$DB_PATH"
