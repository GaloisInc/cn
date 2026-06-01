#!/bin/bash

echo "=== Test: Function Call Dependencies (caller depends on callee SPEC) ==="
echo
echo "Setup: caller() calls helper()"
echo "       When only helper's BODY changes, caller should cache"
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

echo "3. Change helper BODY (return x + 1 → int tmp = x + 1; return tmp):"
cp foo_2.c foo.c
RESULT3=$(cn verify --use-db foo.c 2>&1)
echo "$RESULT3" | grep -E "^\[|cached|pass|fail"

# Check helper was re-verified (not cached)
if echo "$RESULT3" | grep -q "helper.*pass" && ! echo "$RESULT3" | grep -q "helper.*cached"; then
  echo "   ✓ helper re-verified (body changed)"
else
  echo "   ✗ helper should have been re-verified!"
  exit 1
fi

# Check caller was cached (its body and spec didn't change, helper's spec is same)
if echo "$RESULT3" | grep -q "caller.*cached"; then
  echo "   ✓ caller cached (its code unchanged, helper spec unchanged)"
  echo
  echo "✓ SUCCESS: Body changes don't affect independent functions!"
  exit 0
else
  echo
  echo "✗ BUG: caller should be cached when only helper's body changes!"
  echo "       caller depends on helper's SPEC, not its body"
  exit 1
fi
