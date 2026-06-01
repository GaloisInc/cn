#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "=== Test: Spec Change (should re-verify) ==="
echo

rm -f .cn/verification.db foo.c

echo "1. Initial verification with foo_1.c:"
cp foo_1.c foo.c
OUTPUT1=$(cn verify --use-db foo.c 2>&1)
echo "$OUTPUT1" | grep -E "^\[|pass|fail|cached"
../check_test_result.sh verified "$OUTPUT1"
echo

echo "2. Re-run with same file (should cache):"
OUTPUT2=$(cn verify --use-db foo.c 2>&1)
echo "$OUTPUT2" | grep -E "^\[|pass|fail|cached"
../check_test_result.sh cached "$OUTPUT2"
echo

echo "3. Change spec (requires x >= 0 → requires x >= 1) and re-run:"
cp foo_2.c foo.c
OUTPUT3=$(cn verify --use-db foo.c 2>&1)
echo "$OUTPUT3" | grep -E "^\[|pass|fail|cached"
../check_test_result.sh verified "$OUTPUT3"
echo

echo "✓ Test PASSED: Spec changes trigger re-verification"
