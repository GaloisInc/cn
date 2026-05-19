# Expansion Chain Display in Error Messages

## Feature Summary

CN now displays the **expansion chain** when logical functions fail, showing exactly which nested function calls led to each atomic constraint failure.

## The Problem We Solved

When deeply nested logical functions failed, users could see:
- The top-level function that was called
- The atomic constraints that failed

But they **couldn't see** how those atomic constraints related to the top-level function through intermediate function calls.

## The Solution

Error messages now include `via:` lines showing the complete chain of function expansions that led to each failing constraint.

## Example

### Code

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
    requires_two_even_bytes(p, 300, 7);
}
```

### Error Message

```
error: Unprovable constraint
    requires_two_even_bytes(p, 300, 7);
    ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ 
Constraint from: two_even_bytes(a, b);

Failing conjuncts:
  (u64)300'i32 <= 255'u64
    via: two_even_bytes((u64)300'i32, (u64)7'i32)
    via: even_byte((u64)300'i32)
    via: valid_byte((u64)300'i32)
    via: in_range((u64)300'i32, 0'u64, 255'u64)
  
  (u64)7'i32 % 2'u64 == 0'u64
    via: two_even_bytes((u64)300'i32, (u64)7'i32)
    via: even_byte((u64)7'i32)
    via: is_even((u64)7'i32)
```

### What The Error Shows

**For the first failure (`300 <= 255`):**
- Started with `two_even_bytes(300, 7)`
- Called `even_byte(300)`
- Which called `valid_byte(300)`
- Which called `in_range(300, 0, 255)`
- Which expanded to `300 >= 0 && 300 <= 255`
- The `300 <= 255` part is false

**For the second failure (`7 % 2 == 0`):**
- Started with `two_even_bytes(300, 7)`
- Called `even_byte(7)`
- Which called `is_even(7)`
- Which expanded to `7 % 2 == 0`
- This is false

## Benefits

### 1. Understand Complex Failures

With 3+ levels of nesting, it's not obvious how an atomic constraint relates to the top-level function. The chain makes it clear.

### 2. Debug More Quickly

No need to manually trace through function definitions to understand which intermediate function introduced a constraint.

### 3. Identify the Right Function to Fix

If a failure comes from deep in a chain, you can see exactly which intermediate function needs attention.

### 4. Better Code Navigation

The chain shows function names with their actual arguments, making it easy to search for the relevant definitions.

## How It Works

### Implementation

The error reporting system now:

1. **Tracks chains during expansion** - As logical functions are recursively expanded, we build a list of `(function_name, arguments)` pairs

2. **Associates chains with atomic constraints** - Each atomic constraint (like `x <= 255`) is associated with the chain of function calls that led to it

3. **Displays chains for failures** - When a constraint evaluates to false in the SMT model, its chain is displayed

### Key Code

The expansion function returns pairs of `(atomic_constraint, chain)`:

```ocaml
let rec expand_and_collect (chain : (Sym.t * IT.t list) list) (IT.IT (term, bt, loc) as it) =
  match term with
  | IT.Apply (f, args) ->
    (* Expand function and add to chain *)
    (match Definition.Function.try_open def args with
     | Some body ->
       let new_chain = (f, args) :: chain in
       expand_and_collect new_chain body  (* Recurse with extended chain *)
     | None -> [(it, List.rev chain)])
  | IT.Binop (And, lhs, rhs) ->
    (* For And, collect from both sides *)
    List.append (expand_and_collect chain lhs) (expand_and_collect chain rhs)
  | _ ->
    (* Atomic constraint - return with current chain *)
    [(it, List.rev chain)]
```

The chains are stored in a hashtable and looked up when formatting error messages.

## Edge Cases

### Single-Level Functions

For simple functions with no nesting:
```
Failing conjuncts:
  10'u64 < (u64)5'i32
    via: all_properties((u64)5'i32, (u64)50'i32, (u64)55'i32)
```

Shows just one `via:` line.

### Different Branches

When multiple conjuncts come from different branches of the same function, each gets its own chain:

```
Failing conjuncts:
  0'u64 < (u64)0'i32
    via: all_positive(0, 5, 0)
    via: both_positive(0, 5)
    via: positive(0)
  
  0'u64 < (u64)0'i32
    via: all_positive(0, 5, 0)
    via: positive(0)
```

The first went through `both_positive`, the second didn't.

### No Expansion

If a constraint has no function expansions (direct assertion), no `via:` lines appear:
```
Failing conjuncts:
  x > 10
```

## Test Coverage

### Test Files

- `deeply_nested_functions.c` - 3 levels: `two_even_bytes` → `even_byte` → `valid_byte` → `in_range`
- `nested_logical_functions.c` - 2 and 3 level nesting with multiple paths
- `logic_function_error.c` - Simple case with single-level expansion
- `logic_function_multiple_failures.c` - Multiple failing conjuncts from same function

### Verification

All CN test suite tests pass (300+ tests). The feature integrates seamlessly with existing error reporting.

## User Experience

### Before

```
Constraint from: two_even_bytes(a, b);
Failing conjuncts:
  (u64)300'i32 <= 255'u64
```

**Question:** "Where did this `<= 255` come from? Which function checks that?"

### After

```
Constraint from: two_even_bytes(a, b);
Failing conjuncts:
  (u64)300'i32 <= 255'u64
    via: two_even_bytes(...)
    via: even_byte(...)
    via: valid_byte(...)
    via: in_range(..., 0, 255)
```

**Answer:** "Oh, it's from `in_range` inside `valid_byte` inside `even_byte`!"

## Future Enhancements

Potential improvements:

1. **Source locations** - Show where in the source each function is defined
2. **Hyperlinks** - Make function names clickable in HTML output
3. **Highlight path** - In HTML trace, highlight the specific path through the function tree
4. **Collapsible chains** - For very deep nesting, allow collapsing parts of the chain
5. **Diff view** - Show which argument changed between chain entries

## Related Features

This builds on:
- Recursive function expansion (already implemented)
- Constraint simplification (`Explain.simp_constraint`)
- SMT model evaluation (`Solver.eval`)

Works with:
- HTML state files (trace still generated separately)
- All error reporting modes
- Both terminal and IDE output

---

**Implemented:** 2026-05-19  
**Type:** Error reporting enhancement  
**Status:** ✅ Complete and tested  
**Impact:** Dramatically improves debuggability of nested logical functions
