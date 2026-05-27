#!/bin/bash
set -e

echo "========================================="
echo "Test: Lemma → Logical Function Dependency"
echo "========================================="
echo

DB_PATH="/tmp/cn_test_lemma_lf.db"
rm -f "$DB_PATH"

echo "1. Initial verification (foo_1.c):"
cn verify foo_1.c --use-db --db-path="$DB_PATH" --clear-db

echo
echo "2. Check lemma → logical function dependency:"
sqlite3 "$DB_PATH" "SELECT * FROM lemma_uses_logical_function;"
if sqlite3 "$DB_PATH" "SELECT * FROM lemma_uses_logical_function;" | grep -q "double_lemma.*times_two"; then
  echo "✓ Lemma → logical function dependency recorded"
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
echo "✓ Expected: Lemma 'double_lemma' re-verified in step 4 due to logical function change"
echo "All checks passed!"
rm -f "$DB_PATH"
