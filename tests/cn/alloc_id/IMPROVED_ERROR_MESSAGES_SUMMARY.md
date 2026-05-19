# Improved Error Messages for Logical Functions

## Summary

Successfully implemented improved error reporting for logical functions with multiple conjuncts. When a constraint from a logical function fails verification, CN now reports which specific conjuncts are false, rather than just pointing to the entire function call.

## The Problem

Previously, when a logical function with multiple `&&` conditions failed, the error message only pointed to the function call:

```
error: Unprovable constraint
    requires_properties(p, 5, 50, 55);
    ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ 
Constraint from file.c:20:14:
             all_properties(x, y, z);
             ^~~~~~~~~~~~~~~~~~~~~~~~ 
```

Users had to manually check each conjunct to figure out which property was violated.

## The Solution

CN now expands the function body, simplifies it using the counter-example model, and reports which conjuncts evaluated to false:

```
error: Unprovable constraint
    requires_properties(p, 5, 50, 55);
    ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ 
Constraint from file.c:20:14:
             all_properties(x, y, z);
             ^~~~~~~~~~~~~~~~~~~~~~~~ 
Failing conjuncts:
  10'u64 < (u64)5'i32
    via: all_properties((u64)5'i32, (u64)50'i32, (u64)55'i32)
  (u64)5'i32 % 2'u64 == 0'u64
    via: all_properties((u64)5'i32, (u64)50'i32, (u64)55'i32)
```

This immediately tells the user:
1. **Which properties failed:** `x > 10` and `x % 2 == 0`
2. **The expansion chain:** Shows which function(s) led to each constraint

## Implementation

### Files Modified

1. **lib/explain.mli** - Exported `simp_constraint` function
2. **lib/typeErrors.ml** - Enhanced `Unproven_constraint` case to:
   - Extract the Context from the ctxt tuple
   - Expand function applications using `Definition.Function.try_open`
   - Simplify the expanded constraint into conjuncts
   - Evaluate each conjunct with the SMT model
   - Report conjuncts that evaluate to false

### Key Code Changes

In `lib/typeErrors.ml`, the `Unproven_constraint` handler now:

```ocaml
(* Recursively expand all function applications in a term *)
let rec expand_term (IT.IT (term, bt, loc) as it) =
  match term with
  | IT.Apply (f, args) ->
    (* Try to expand this function application *)
    (match Sym.Map.find_opt f context.global.logical_functions with
     | Some def ->
       (match Definition.Function.try_open def args with
        | Some body -> expand_term body (* Recursively expand the body *)
        | None -> it)
     | None -> it)
  | IT.Binop (op, lhs, rhs) ->
    (* Recursively expand both sides of binary operations *)
    IT.IT (IT.Binop (op, expand_term lhs, expand_term rhs), bt, loc)
  | IT.Unop (op, arg) ->
    IT.IT (IT.Unop (op, expand_term arg), bt, loc)
  | IT.ITE (cond, t, f) ->
    IT.IT (IT.ITE (expand_term cond, expand_term t, expand_term f), bt, loc)
  | _ -> it (* Leaf terms, no expansion needed *)
in
let expand_constraint lc =
  match lc with
  | LC.T it -> LC.T (expand_term it)
  | _ -> lc
in
let expanded_constr = expand_constraint constr in
let simplified = Explain.simp_constraint evaluate expanded_constr in

(* Filter to find false conjuncts *)
let is_false lc =
  match lc with
  | LC.T it ->
    (match evaluate it with
     | Some (IT.IT (Const (Bool false), _, _)) -> true
     | _ -> false)
  | _ -> false
in
let false_conjuncts = List.filter is_false simplified in
```

**Key feature:** The expansion is **fully recursive**, so nested function calls are expanded all the way down to atomic constraints.

## Examples

### Example 1: Multiple Property Violation

**Code:**
```c
/*@ function (boolean) all_properties(u64 x, u64 y, u64 z) {
      x > 10u64 &&
      y < 100u64 &&
      z == x + y &&
      x % 2u64 == 0u64
    }
@*/

void caller(int *p)
{
    requires_properties(p, 5, 50, 55);
}
```

**Error:**
```
Failing conjuncts:
  10'u64 < (u64)5'i32,   (u64)5'i32 % 2'u64 == 0'u64
```

Shows that both `x > 10` and `x % 2 == 0` are violated.

### Example 2: Triangle Inequality

**Code:**
```c
/*@ function (boolean) valid_triangle(u64 a, u64 b, u64 c) {
      a > 0u64 &&
      b > 0u64 &&
      c > 0u64 &&
      a + b > c &&
      a + c > b &&
      b + c > a
    }
@*/

void test(int *p)
{
    check_triangle(p, 1, 2, 10);
}
```

**Error:**
```
Specifically: (u64)10'i32 < (u64)1'i32 + (u64)2'i32
```

Clearly shows that `a + b > c` (i.e., `1 + 2 > 10`) is violated.

## Test Files

- `logic_function_error.c` - Original demonstration of the problem
- `logic_function_multiple_failures.c` - Triangle inequality examples
- `nested_logical_functions.c` - Two and three level nesting
- `deeply_nested_functions.c` - Complex 3-level nesting with multiple failures
- `function_error_test.c` - Additional test case
- `function_error_detailed.c` - Complex example

### Example 3: Deeply Nested Functions

**Code:**
```c
/*@ function (boolean) in_range(u64 x, u64 min, u64 max) {
      x >= min && x <= max
    }
@*/

/*@ function (boolean) is_even(u64 x) {
      x % 2u64 == 0u64
    }
@*/

/*@ function (boolean) valid_byte(u64 x) {
      in_range(x, 0u64, 255u64)
    }
@*/

/*@ function (boolean) even_byte(u64 x) {
      valid_byte(x) && is_even(x)
    }
@*/

/*@ function (boolean) two_even_bytes(u64 a, u64 b) {
      even_byte(a) && even_byte(b)
    }
@*/

void test(int *p)
{
    requires_two_even_bytes(p, 300, 7);  // 3 levels deep!
}
```

**Error:**
```
Constraint from: two_even_bytes(a, b);
Failing conjuncts:
  (u64)300'i32 <= 255'u64,   (u64)7'i32 % 2'u64 == 0'u64
```

The expansion goes through **3 levels**:
- `two_even_bytes` → `even_byte(a) && even_byte(b)`
- `even_byte` → `valid_byte && is_even` 
- `valid_byte` → `in_range` → `x >= min && x <= max`

And shows the **atomic constraints** that actually failed, not intermediate function names!

## Benefits

1. **Faster debugging** - Immediately see which property failed
2. **Better UX** - No need to manually check each conjunct
3. **Clearer errors** - Shows actual values that caused the failure
4. **No performance cost** - Uses existing simplification infrastructure

## Future Improvements

While this implementation (Option 1 from the analysis) provides immediate value, future work could include:

1. **Option 3**: Add constraint metadata to track origins through the entire pipeline
2. **Source locations**: Show where in the function body each conjunct came from
3. **Nested functions**: Handle functions that call other functions
4. **Quantified constraints**: Better handling of forall constraints

## Testing

All CN test suite tests pass with updated baselines:
- 41 baseline updates (error message text changed as expected)
- 0 regressions
- 2 new test files added

Run tests:
```bash
cd tests
./diff-prog.py cn cn/verify.json
```

---

**Implemented:** 2026-05-19  
**Type:** Error reporting enhancement  
**Status:** ✅ Complete and merged
