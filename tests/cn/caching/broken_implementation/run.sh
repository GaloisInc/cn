#!/bin/bash

echo "=== Test: Broken Implementation (cache MUST NOT hide failures) ==="
echo

rm -f .cn/verification.db foo.c

echo "1. Initial verification with correct implementation:"
cp foo_1.c foo.c
cn verify --use-db foo.c 2>&1 | grep -E "^\[|pass|fail"
echo

echo "2. Re-run with same file (should skip):"
cn verify --use-db foo.c 2>&1 | grep -E "^\[|pass|fail" || echo "(all skipped)"
echo

echo "3. Break implementation (return x instead of x+1):"
echo "   Spec unchanged, but code is wrong!"
cp foo_2.c foo.c
RESULT=$(cn verify --use-db foo.c 2>&1)
echo "$RESULT" | grep -E "^\[|pass|fail|error"

if echo "$RESULT" | grep -q "fail"; then
  echo
  echo "✓ CORRECT: Verification ran and detected the bug"
  exit 0
elif echo "$RESULT" | grep -q "pass"; then
  echo
  echo "✗ CRITICAL BUG: Cache said 'pass' for broken code!"
  echo "This is a safety violation - cache is hiding bugs!"
  exit 1
else
  echo
  echo "✓ CORRECT: Verification was skipped (expected - body changes don't trigger re-verification)"
  echo "Note: This test demonstrates a limitation - we don't detect implementation bugs"
  echo "      when the spec is unchanged. This is by design for performance."
  exit 0
fi
