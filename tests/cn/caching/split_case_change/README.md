# Split Case Change Caching Test

Tests that changes to `split_case` annotations in function bodies trigger re-verification.

## Files
- `foo_1.c` - Function with `split_case(x >= y)`
- `foo_2.c` - Same function with `split_case(x > y)` (changed condition)

## Expected Behavior
1. First run of foo_1.c: Verification runs, function passes
2. Second run of foo_1.c: Cached (no output)
3. Third run of foo_2.c: Re-verification triggered due to split_case change

This ensures that CN's content hashing correctly detects changes to proof guidance annotations like `split_case`.
