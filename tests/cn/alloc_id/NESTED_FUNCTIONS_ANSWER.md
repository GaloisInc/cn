# What Happens When a Failing Conjunct is Another Logical Function?

## Question

What happens if the failing conjunct of a logical function is itself another logical function?

## Answer

The implementation **recursively expands all nested logical functions** until it reaches atomic constraints. When a failing conjunct is another function call, it gets expanded and its body is further analyzed.

## How It Works

The error reporting uses recursive expansion that:

1. **Expands top-level function** - e.g., `two_even_bytes(a, b)` → `even_byte(a) && even_byte(b)`
2. **Recursively expands nested functions** - e.g., `even_byte(a)` → `valid_byte(a) && is_even(a)`
3. **Continues until atomic** - e.g., `valid_byte(a)` → `in_range(a, 0, 255)` → `a >= 0 && a <= 255`
4. **Reports atomic failures** - Shows actual comparison like `300 <= 255`, not function names

## Example: Three Levels of Nesting

```c
// Level 1: Basic properties
/*@ function (boolean) in_range(u64 x, u64 min, u64 max) {
      x >= min && x <= max
    }
@*/

/*@ function (boolean) is_even(u64 x) {
      x % 2u64 == 0u64
    }
@*/

// Level 2: Composite properties  
/*@ function (boolean) valid_byte(u64 x) {
      in_range(x, 0u64, 255u64)
    }
@*/

/*@ function (boolean) even_byte(u64 x) {
      valid_byte(x) && is_even(x)
    }
@*/

// Level 3: Complex property
/*@ function (boolean) two_even_bytes(u64 a, u64 b) {
      even_byte(a) && even_byte(b)
    }
@*/

void test(int *p)
{
    requires_two_even_bytes(p, 300, 7);
}
```

### Error Output

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

**The "via" lines show the expansion chain** - the sequence of function calls that led to each atomic constraint!

### What Got Expanded

The error shows **atomic constraints**, not intermediate function calls:

**For value 300:**
- `two_even_bytes(300, 7)` expands to `even_byte(300) && even_byte(7)`
- `even_byte(300)` expands to `valid_byte(300) && is_even(300)`
- `valid_byte(300)` expands to `in_range(300, 0, 255)`
- `in_range(300, 0, 255)` expands to `300 >= 0 && 300 <= 255`
- **Reports:** `300 <= 255` (the failing atomic constraint)

**For value 7:**
- `even_byte(7)` expands to `valid_byte(7) && is_even(7)`
- `is_even(7)` expands to `7 % 2 == 0`
- **Reports:** `7 % 2 == 0` (the failing atomic constraint)

## Benefits

1. **No intermediate functions** - You don't see `positive(0)` or `valid_byte(300)`, you see the actual constraint
2. **Works at any depth** - Tested with 3+ levels of nesting
3. **Shows root cause** - Immediately see what comparison failed
4. **Multiple failures** - Can show multiple atomic failures from different branches

## Implementation Details

The recursive expansion works by:

```ocaml
let rec expand_term (IT.IT (term, bt, loc) as it) =
  match term with
  | IT.Apply (f, args) ->
    (* Expand function and recursively expand its body *)
    (match Sym.Map.find_opt f context.global.logical_functions with
     | Some def ->
       (match Definition.Function.try_open def args with
        | Some body -> expand_term body  (* RECURSIVE *)
        | None -> it)
     | None -> it)
  | IT.Binop (op, lhs, rhs) ->
    (* Recursively expand both sides *)
    IT.IT (IT.Binop (op, expand_term lhs, expand_term rhs), bt, loc)
  | IT.Unop (op, arg) ->
    IT.IT (IT.Unop (op, expand_term arg), bt, loc)
  | IT.ITE (cond, t, f) ->
    IT.IT (IT.ITE (expand_term cond, expand_term t, expand_term f), bt, loc)
  | _ -> it (* Leaf - atomic constraint *)
```

Key points:
- **Recursive on function bodies** - When expanding `Apply(f, args)`, we recursively expand the result
- **Recursive on structure** - Also recurses through `Binop`, `Unop`, `ITE` to expand nested applications
- **Stops at atoms** - Stops when it hits non-function terms like comparisons, arithmetic, etc.

## Test Cases

- `nested_logical_functions.c` - Two and three level nesting
- `deeply_nested_functions.c` - Complex 3-level nesting with multiple property violations

## Comparison: Before vs After

### Before (Single-level expansion)

```
Constraint from: both_positive(x, y);
Specifically: positive((u64)0'i32)
```

You see the **intermediate function call** `positive(0)`, not what's actually false.

### After (Recursive expansion)

```
Constraint from: both_positive(x, y);
Specifically: 0'u64 < (u64)0'i32
```

You see the **actual atomic constraint** `0 < 0` that failed.

## Edge Cases

### Recursive Functions

If a logical function is recursive (uses `Rec_Def`), it won't be expanded (per `Definition.Function.try_open` which returns `None` for recursive definitions). This prevents infinite expansion.

### Uninterpreted Functions

Uninterpreted functions also won't be expanded (no body to expand), so they'll appear as-is in the error.

### Mixed Nesting

Works correctly with any combination:
- Function calling function calling function
- Function with multiple branches, each calling other functions
- Functions called in both sides of && or ||

---

**Summary:** Nested logical functions are fully expanded to atomic constraints, providing clear, actionable error messages no matter how deep the nesting.
