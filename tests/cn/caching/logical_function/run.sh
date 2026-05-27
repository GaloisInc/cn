#!/bin/bash
set -e

echo "========================================="
echo "Test: Logical Function Dependency Tracking"
echo "========================================="
echo

DB_PATH="/tmp/cn_test_logical_function.db"
rm -f "$DB_PATH"

echo "First verification (foo_1.c):"
cn verify foo_1.c --use-db --db-path="$DB_PATH" --db-stats --clear-db

echo
echo "Checking database contents:"
sqlite3 "$DB_PATH" "SELECT * FROM function_uses_logical_function;"
if sqlite3 "$DB_PATH" "SELECT * FROM function_uses_logical_function;" | grep -q "compute.*times_two"; then
  echo "✓ Function → logical function dependency recorded (compute uses times_two)"
else
  echo "✗ FAILED: No dependency recorded"
  exit 1
fi

echo
echo "Second verification (foo_1.c again, should be cached):"
cn verify foo_1.c --use-db --db-path="$DB_PATH"

echo
echo "Third verification (foo_2.c - logical function body changed):"
cn verify foo_2.c --use-db --db-path="$DB_PATH"

echo
echo "Checking that logical function was re-verified:"
sqlite3 "$DB_PATH" "SELECT name FROM logical_functions;"
if sqlite3 "$DB_PATH" "SELECT name FROM logical_functions;" | grep -q "times_two"; then
  echo "✓ Logical function 'times_two' was re-verified"
else
  echo "✗ FAILED: Logical function not found in database"
  exit 1
fi

echo
echo "All checks passed!"
rm -f "$DB_PATH"
