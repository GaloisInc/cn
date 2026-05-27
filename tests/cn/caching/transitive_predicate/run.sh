#!/bin/bash

echo "=== Test: Transitive Predicate Dependencies ==="
echo
echo "Setup: Predicate DoubledValue uses predicate BaseValue"
echo "       Function check_doubled uses DoubledValue"
echo "       When BaseValue changes, check_doubled should be re-verified"
echo

rm -f .cn/verification.db foo.c

echo "1. Initial verification:"
cp foo_1.c foo.c
RESULT1=$(cn verify --use-db foo.c 2>&1)
echo "$RESULT1" | grep -E "^\[|pass|fail"

if echo "$RESULT1" | grep -q "pass"; then
  echo "   ✓ Initial verification passed"
else
  echo "   ✗ Should have passed!"
  exit 1
fi
echo

echo "2. Modify BaseValue predicate (used transitively by check_doubled):"
echo "   BaseValue: x == v  →  x == v + 1i32"
cp foo_2.c foo.c
RESULT2=$(cn verify --use-db foo.c 2>&1)
echo "$RESULT2" | grep -E "^\[|pass|fail" || echo "   (skipped)"

if echo "$RESULT2" | grep -q "pass\|fail"; then
  echo "   ✓ Re-verified due to transitive dependency change"
  exit 0
else
  echo
  echo "✗ BUG: Should have re-verified check_doubled"
  echo "       BaseValue changed, DoubledValue depends on BaseValue,"
  echo "       check_doubled depends on DoubledValue"
  echo "       So check_doubled should be re-verified"
  exit 1
fi
