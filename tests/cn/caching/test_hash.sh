#!/bin/bash

# Test the alpha-renaming hashing on tricky test case

BASE=/Users/guso/tools/cn/tests/cn/caching

echo "=== Testing tricky test case ==="
echo

echo "Computing hash for foo_1.c (returns x_1):"
cd $BASE/tricky && CN_DEBUG_HASH=1 cn wf foo_1.c --cache-status --db-path ver.db 2>&1 | grep -A 20 "Pre-normalization\|Content hash:" || echo "(parsing only)"

echo
echo "Computing hash for foo_2.c (returns x_2):"
cd $BASE/tricky && CN_DEBUG_HASH=1 cn wf foo_2.c --cache-status --db-path ver.db 2>&1 | grep -A 20 "Pre-normalization\|Content hash:" || echo "(parsing only)"

echo
echo "=== Testing assert_in_loop test case ==="
echo

echo "Computing hash for foo_1.c (assert i & s == s):"
cd $BASE/assert_in_loop && CN_DEBUG_HASH=1 cn wf foo_1.c --cache-status --db-path ver.db 2>&1 | grep -A 20 "Pre-normalization\|Content hash:" || echo "(parsing only)"

echo
echo "Computing hash for foo_2.c (assert i & s == ~s):"
cd $BASE/assert_in_loop && CN_DEBUG_HASH=1 cn wf foo_2.c --cache-status --db-path ver.db 2>&1 | grep -A 20 "Pre-normalization\|Content hash:" || echo "(parsing only)"
