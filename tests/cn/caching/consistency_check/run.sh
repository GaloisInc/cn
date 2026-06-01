#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "=== Test: Consistency Checking Caching ==="
echo

rm -rf .cn

echo "1. Initial verification without consistency checking:"
OUTPUT1=$(cn verify --use-db foo.c 2>&1)
echo "$OUTPUT1" | grep -E "^\[|pass|fail|cached"
if ! echo "$OUTPUT1" | grep -q "identity.*pass"; then
  echo "✗ FAIL: Function should have passed"
  exit 1
fi
echo "✓ PASS: Function verified"
echo

echo "2. Query database to check consistency_checked status (should be 0):"
if sqlite3 .cn/verification.db "SELECT consistency_checked FROM functions WHERE name='identity'" | grep -q "0"; then
  echo "✓ PASS: consistency_checked=0 (not checked)"
else
  echo "✗ FAIL: Expected consistency_checked=0"
  exit 1
fi
echo

echo "3. Re-run without consistency checking (should cache):"
OUTPUT2=$(cn verify --use-db foo.c 2>&1)
echo "$OUTPUT2" | grep -E "^\[|pass|fail|cached"
if ! echo "$OUTPUT2" | grep -q "identity.*cached"; then
  echo "✗ FAIL: Function should have been cached"
  exit 1
fi
echo "✓ PASS: Function cached"
echo

echo "4. Run with consistency checking enabled:"
OUTPUT3=$(cn verify --use-db --check-consistency foo.c 2>&1)
echo "$OUTPUT3" | grep -E "^\[|pass|fail|cached"
# Verification should still be cached since function content didn't change
# Consistency checking runs as a separate pass before verification
if ! echo "$OUTPUT3" | grep -q "identity.*cached"; then
  echo "✗ FAIL: Function verification should be cached"
  exit 1
fi
echo "✓ PASS: Function verification cached (consistency checking is separate)"
echo

echo "5. Query database to check consistency_checked status (should be 1):"
if sqlite3 .cn/verification.db "SELECT consistency_checked FROM functions WHERE name='identity'" | grep -q "1"; then
  echo "✓ PASS: consistency_checked=1 (checked)"
else
  echo "✗ FAIL: Expected consistency_checked=1"
  exit 1
fi
echo

echo "6. Re-run with consistency checking (should cache both passes):"
OUTPUT4=$(cn verify --use-db --check-consistency foo.c 2>&1)
echo "$OUTPUT4" | grep -E "^\[|pass|fail|cached"
if ! echo "$OUTPUT4" | grep -q "identity.*cached"; then
  echo "✗ FAIL: Function should be cached"
  exit 1
fi
echo "✓ PASS: Function cached"
echo

echo "✓ Test PASSED: Consistency checking is cached correctly"
