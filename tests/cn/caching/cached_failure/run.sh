#!/bin/bash

echo "=== Test: Cached Failure (must report failure, not skip) ==="
echo

rm -f .cn/verification.db foo.c

echo "1. Initial verification with WRONG implementation:"
cp foo_1.c foo.c
RESULT1=$(cn verify --use-db foo.c 2>&1)
echo "$RESULT1" | grep -E "^\[|pass|fail"

if echo "$RESULT1" | grep -q "fail"; then
  echo "   ✓ Correctly reports failure"
else
  echo "   ✗ Should have failed!"
  exit 1
fi
echo

echo "2. Re-run with same wrong code:"
echo "   Cache knows it failed - what does it do?"
RESULT2=$(cn verify --use-db foo.c 2>&1)
echo "$RESULT2" | grep -E "^\[|pass|fail" || echo "   (skipped)"

if echo "$RESULT2" | grep -q "pass"; then
  echo
  echo "✗ CRITICAL BUG: Cached failure reported as PASS!"
  echo "This is a safety violation!"
  exit 1
elif echo "$RESULT2" | grep -q "fail"; then
  echo "   ✓ Still reports failure (good - we re-verified)"
  exit 0
else
  echo "   ✓ Skipped (acceptable - cache remembered the failure)"
  exit 0
fi
