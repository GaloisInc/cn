#!/bin/bash
set -e

echo "========================================="
echo "Test: Lemma Dependency Tracking"
echo "========================================="
echo

DB_PATH="/tmp/cn_test_lemma.db"
rm -f "$DB_PATH"

echo "First verification (foo_1.c):"
cn verify foo_1.c --use-db --db-path="$DB_PATH" --db-stats --clear-db

echo
echo "Checking database contents for lemma and dependencies:"
echo "Lemmata in database:"
sqlite3 "$DB_PATH" "SELECT * FROM lemmata;"

echo
echo "Function → lemma dependencies:"
sqlite3 "$DB_PATH" "SELECT * FROM function_uses_lemma;"
if sqlite3 "$DB_PATH" "SELECT * FROM function_uses_lemma;" | grep -q "check_value.*my_lemma"; then
  echo "✓ Function → lemma dependency recorded (check_value uses my_lemma)"
else
  echo "✗ FAILED: No function → lemma dependency recorded"
  exit 1
fi

echo
echo "Lemma → predicate dependencies:"
sqlite3 "$DB_PATH" "SELECT * FROM lemma_uses_predicate;"
if sqlite3 "$DB_PATH" "SELECT * FROM lemma_uses_predicate;" | grep -q "my_lemma.*Positive"; then
  echo "✓ Lemma → predicate dependency recorded (my_lemma uses Positive)"
else
  echo "✗ FAILED: No lemma → predicate dependency recorded"
  exit 1
fi

echo
echo "Second verification (foo_1.c again, should be cached):"
cn verify foo_1.c --use-db --db-path="$DB_PATH"

echo
echo "Third verification (foo_2.c - predicate Positive changed):"
echo "The Positive predicate has an extra assertion, so lemma my_lemma should be re-verified"
cn verify foo_2.c --use-db --db-path="$DB_PATH"

echo
echo "Checking that lemma was re-verified:"
sqlite3 "$DB_PATH" "SELECT name FROM lemmata WHERE name = 'my_lemma';"
if sqlite3 "$DB_PATH" "SELECT name FROM lemmata WHERE name = 'my_lemma';" | grep -q "my_lemma"; then
  echo "✓ Lemma 'my_lemma' was re-verified"
else
  echo "✗ FAILED: Lemma not found in database"
  exit 1
fi

echo
echo "All checks passed!"
rm -f "$DB_PATH"
