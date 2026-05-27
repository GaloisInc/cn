#!/bin/bash

echo "=== Test: Adding Unrelated Function (should not affect get_value cache) ==="
echo
echo "Setup: get_value() is a standalone function"
echo "       Adding a separate unrelated_function() should not affect get_value's hash"
echo

rm -f .cn/verification.db foo.c

echo "1. Initial verification (foo_1.c - only get_value):"
cp foo_1.c foo.c
RESULT1=$(cn verify --use-db foo.c 2>&1)
echo "$RESULT1" | grep -E "^\[|pass|fail"

if echo "$RESULT1" | grep -q "get_value.*pass"; then
  echo "   ✓ get_value passed"
else
  echo "   ✗ Should have passed!"
  exit 1
fi
echo

echo "2. Re-run with same file (should skip):"
RESULT2=$(cn verify --use-db foo.c 2>&1)
echo "$RESULT2" | grep -E "^\[|cached|pass|fail"

if echo "$RESULT2" | grep -q "get_value.*cached"; then
  echo "   ✓ get_value skipped"
else
  echo "   ✗ Should have skipped!"
  exit 1
fi
echo

echo "3. Add unrelated function at top of file (foo_2.c):"
cp foo_2.c foo.c
RESULT3=$(cn verify --use-db foo.c 2>&1)
echo "$RESULT3" | grep -E "^\[|cached|pass|fail"

# Check if unrelated_function was verified (it's new)
if echo "$RESULT3" | grep -q "unrelated_function.*pass"; then
  echo "   ✓ unrelated_function verified (new function)"
else
  echo "   ✗ unrelated_function should have been verified!"
  exit 1
fi

# Check if get_value was cached (unchanged)
if echo "$RESULT3" | grep -q "get_value.*cached"; then
  echo "   ✓ get_value skipped (unaffected by unrelated function)"
  echo
  echo "✓ SUCCESS: Adding unrelated function doesn't invalidate unrelated cache entries"
  exit 0
else
  echo
  echo "✗ BUG: get_value should be cached!"
  echo "       Adding unrelated_function should not affect get_value's hash"
  echo "       This suggests the hash includes location-dependent data"
  exit 1
fi
