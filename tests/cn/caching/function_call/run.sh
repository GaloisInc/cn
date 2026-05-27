#!/bin/bash

echo "=== Test: Function Call Dependencies (caller depends on callee SPEC) ==="
echo
echo "Setup: caller() calls helper()"
echo "       When helper's SPEC changes, caller should be re-verified"
echo

rm -f .cn/verification.db foo.c

echo "1. Initial verification:"
cp foo_1.c foo.c
RESULT1=$(cn verify --use-db foo.c 2>&1)
echo "$RESULT1" | grep -E "^\[|pass|fail"

if echo "$RESULT1" | grep -q "helper.*pass" && echo "$RESULT1" | grep -q "caller.*pass"; then
  echo "   ✓ Both functions passed"
else
  echo "   ✗ Should have passed!"
  exit 1
fi
echo

echo "2. Re-run with same file (should skip both):"
RESULT2=$(cn verify --use-db foo.c 2>&1)
echo "$RESULT2" | grep -E "^\[|cached|pass|fail"

# Check that both were cached (not freshly verified)
if echo "$RESULT2" | grep -q "helper.*cached" && echo "$RESULT2" | grep -q "caller.*cached"; then
  echo "   ✓ Both skipped"
else
  echo "   ✗ Should have skipped!"
  exit 1
fi
echo

echo "3. Change helper SPEC (add extra ensures clause):"
cp foo_2.c foo.c
RESULT3=$(cn verify --use-db foo.c 2>&1)
echo "$RESULT3" | grep -E "^\[|cached|pass|fail"

# Check helper was re-verified (not cached)
if echo "$RESULT3" | grep -q "helper.*pass" && ! echo "$RESULT3" | grep -q "helper.*cached"; then
  echo "   ✓ helper re-verified (spec changed)"
else
  echo "   ✗ helper should have been re-verified!"
  exit 1
fi

# Check caller was re-verified (not cached)
if echo "$RESULT3" | grep -q "caller.*pass" && ! echo "$RESULT3" | grep -q "caller.*cached"; then
  echo "   ✓ caller re-verified (callee spec changed)"
  echo
  echo "✓ SUCCESS: Function call dependency tracking works!"
  exit 0
else
  echo
  echo "✗ BUG: caller should be re-verified when helper's spec changes!"
  echo "       caller depends on helper, and helper's spec changed"
  exit 1
fi
