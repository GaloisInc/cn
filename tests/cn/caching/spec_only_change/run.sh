#!/bin/bash
set -e

echo "=== Test: Spec-Only Change (should re-verify) ==="
echo ""

# Clean database
rm -rf .cn

echo "1. Initial verification with foo_1.c:"
cn verify --verification-db foo_1.c

echo ""
echo "2. Re-run with same file (should skip):"
cn verify --verification-db foo_1.c

echo ""
echo "3. Change spec (add upper bound constraint) and re-run:"
cn verify --verification-db foo_2.c

echo ""
echo "✓ Expected: get_value re-verified in step 3 due to spec change"
