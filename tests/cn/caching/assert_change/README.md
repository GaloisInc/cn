# Assert Change Caching Test

Tests that changes to `assert` statements in function bodies trigger re-verification.

## Files
- `foo_1.c` - Function with `assert(x < 50i32 || x >= 50i32)`
- `foo_2.c` - Same function with `assert(x < 25i32 || x >= 25i32)` (different boundary)

## Expected Behavior
1. First run of foo_1.c: Verification runs, function passes
2. Second run of foo_1.c: Cached (no output)
3. Third run of foo_2.c: Re-verification triggered due to assert change

This ensures that CN's content hashing correctly detects changes to assertion statements in function bodies.
