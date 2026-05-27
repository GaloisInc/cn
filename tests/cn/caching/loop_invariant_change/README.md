# Loop Invariant Change Caching Test

Tests that changes to loop invariants trigger re-verification.

## Files
- `foo_1.c` - Function with loop invariant `s == (i * (i + 1)) / 2`
- `foo_2.c` - Same function with loop invariant `s == (i * (i - 1)) / 2` (different formula)

## Expected Behavior
1. First run of foo_1.c: Verification runs, function fails
2. Second run of foo_1.c: Cached (shows "cached (fail)")
3. Third run of foo_2.c: Re-verification triggered due to loop invariant change

This ensures that CN's content hashing correctly detects changes to loop specifications, which are part of the function body structure (not just the pre/post spec).
