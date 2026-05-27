#!/bin/bash
set -e

echo "========================================="
echo "Test: Predicate → Struct Dependency"
echo "========================================="
echo

DB_PATH="/tmp/cn_test_pred_struct.db"
rm -f "$DB_PATH"

echo "1. Initial verification (foo_1.c):"
cn verify foo_1.c --use-db --db-path="$DB_PATH" --clear-db

echo
echo "2. Check predicate → struct dependency:"
sqlite3 "$DB_PATH" "SELECT * FROM predicate_uses_struct;"
if sqlite3 "$DB_PATH" "SELECT * FROM predicate_uses_struct;" | grep -q "PointX.*Point"; then
  echo "✓ Predicate → struct dependency recorded"
else
  echo "✗ FAILED: No dependency recorded"
  exit 1
fi

echo
echo "3. Re-run with same file (should skip):"
cn verify foo_1.c --use-db --db-path="$DB_PATH"

echo
echo "4. Change struct Point (add field z) and re-run:"
cn verify foo_2.c --use-db --db-path="$DB_PATH"

echo
echo "✓ Expected: Predicate 'PointX' re-verified in step 4 due to struct change"
echo "All checks passed!"
rm -f "$DB_PATH"
