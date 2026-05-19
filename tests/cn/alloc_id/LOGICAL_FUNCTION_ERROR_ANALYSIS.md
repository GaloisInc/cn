# Logical Function Error Message Analysis

## Problem

When a logical function with multiple conjuncts fails verification, CN reports "Unprovable constraint" pointing to the function call, but doesn't indicate which specific conjunct failed.

### Example

```c
/*@ function (boolean) all_properties(u64 x, u64 y, u64 z) {
      x > 10u64 &&      // Property A
      y < 100u64 &&     // Property B
      z == x + y &&     // Property C
      x % 2u64 == 0u64  // Property D
    }
@*/

void caller(int *p)
/*@ requires take P = RW<int>(p);
    ensures  take P2 = RW<int>(p);
             P2 == P;
@*/
{
    requires_properties(p, 5, 50, 55);  // Fails: x=5 doesn't satisfy x > 10
}
```

**Current error:**
```
error: Unprovable constraint
    requires_properties(p, 5, 50, 55);
    ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ 
Constraint from /path/to/file.c:20:14:
             all_properties(x, y, z);
             ^~~~~~~~~~~~~~~~~~~~~~~~ 
```

The error points to the entire `all_properties(x, y, z)` call but doesn't tell us that the failing conjunct is `x > 10u64`.

## Root Cause Analysis

### Constraint Construction

When a logical function is applied (lib/check.ml:2216-2222):

```ocaml
(match Definition.Function.unroll_once def args with
 | None -> (* error: uninterpreted function *)
 | Some body -> add_c loc (LC.T (eq_ (apply_ f args def.return_bt loc, body) loc)))
```

The function body is expanded by substituting arguments, creating a single IndexTerm. For `all_properties(5, 50, 55)`, this produces:

```
5 > 10 && 50 < 100 && 55 == 5 + 50 && 5 % 2 == 0
```

This entire expression becomes one `IT.t` term with `Binop(And, ...)` nodes. It's added as a single constraint `LC.T(...)`.

### Constraint Representation

Looking at lib/logicalConstraints.ml:

```ocaml
type t =
  | T of IT.t
  | Forall of (Sym.t * BT.t) * IT.t
```

Constraints don't preserve the structure of individual conjuncts. A constraint is just an `IT.t` term. The && operation is represented as nested `IT.IT(Binop(And, lhs, rhs), bt, loc)` nodes in the term tree.

### Error Reporting

When SMT solving fails (lib/typeErrors.ml:527-544):

```ocaml
| Unproven_constraint { constr; requests; info; ctxt; model } ->
    let short = !^"Unprovable constraint" in
    let state =
      Explain.trace ctxt model Explain.{ no_ex with unproven_constraint = Some constr }
    in
    let descr =
      let spec_loc, odescr = info in
      let head, pos = Locations.head_pos_of_location spec_loc in
      let doc =
        match odescr with
        | None -> !^"Constraint from" ^^^ !^head ^/^ !^pos
        | Some descr -> !^"Constraint from" ^^^ !^descr ^^^ !^head ^/^ !^pos
      in
      ...
```

The error receives:
- `constr`: The entire constraint (the whole && expression)
- `info`: Source location (points to the function call in requires clause)
- `model`: Counter-example from SMT solver

The error system reports the constraint as a whole. It doesn't attempt to identify which sub-formula failed.

### Simplification

lib/explain.ml:92-116 has `simp_constraint` which simplifies constraints using a model:

```ocaml
let simp_constraint eval lct =
  let eval_to_bool it =
    match eval it with Some (IT.IT (Const (Bool b1), _, _)) -> Some b1 | _ -> None
  in
  let is b it = match eval_to_bool it with Some b1 -> Bool.equal b b1 | _ -> false in
  let rec go (IT.IT (term, bt, loc)) =
    ...
    match term with
    | Const (Bool true) -> []
    | Binop (Or, lhs, rhs) when is false lhs -> go rhs
    | Binop (Or, lhs, rhs) when is false rhs -> go lhs
    | Binop (And, lhs, rhs) -> List.append (go lhs) (go rhs)  (* IMPORTANT *)
    ...
```

Notice line 105: `Binop (And, lhs, rhs) -> List.append (go lhs) (go rhs)` 

This **does** decompose && into individual conjuncts! The simplified constraint is a list of terms where each element that evaluates to false is potentially a failing conjunct.

However, this simplified form is only used in the HTML state file trace, not in the error message shown to the user.

## Architecture for Better Error Messages

To provide better error messages identifying which conjunct failed, CN would need:

### Option 1: Report Simplified Constraint in Error Text

**Changes needed:**

1. **lib/typeErrors.ml:527-544** - Modify `Unproven_constraint` case:
   ```ocaml
   | Unproven_constraint { constr; requests; info; ctxt; model } ->
       let model_val, _quantifier = model in
       let evaluate = Solver.eval model_val in
       
       (* Simplify and find failing conjuncts *)
       let simplified = Explain.simp_constraint evaluate constr in
       let failing_conjuncts = 
         List.filter (fun lc ->
           match lc with
           | LC.T it ->
             (match evaluate it with
              | Some (IT.IT (Const (Bool false), _, _)) -> true
              | Some (IT.IT (Const (Bool true), _, _)) -> false
              | _ -> true)  (* unknown, might be failing *)
           | _ -> true)
         simplified
       in
       
       (* Include failing conjuncts in error message *)
       let short = !^"Unprovable constraint" in
       let descr =
         let spec_loc, odescr = info in
         let head, pos = Locations.head_pos_of_location spec_loc in
         let base_doc =
           match odescr with
           | None -> !^"Constraint from" ^^^ !^head ^/^ !^pos
           | Some descr -> !^"Constraint from" ^^^ !^descr ^^^ !^head ^/^ !^pos
         in
         (* Add failing conjunct details *)
         match failing_conjuncts with
         | [] -> base_doc
         | [one] -> 
           base_doc ^^ hardline ^^
           !^"Specifically:" ^^^ LC.pp one
         | many ->
           base_doc ^^ hardline ^^
           !^"Failing conjuncts:" ^^ hardline ^^
           Pp.flow_map (fun lc -> !^"  -" ^^^ LC.pp lc) many
       in
       ...
   ```

**Pros:**
- Minimal changes
- Reuses existing simplification infrastructure
- Shows exact failing formulas with counter-example values

**Cons:**
- Only shows failing conjuncts from the top-level &&, not nested within the function body
- Requires model evaluation (SMT solver already provides this)

### Option 2: Try Proving Each Conjunct Separately

**Changes needed:**

1. **lib/check.ml:2216-2222** - When adding function body constraint, detect && and add each conjunct separately:
   ```ocaml
   | Some body ->
       let conjuncts = decompose_ands body in  (* new helper *)
       ListM.iterM (fun c -> add_c loc (LC.T c)) conjuncts
   ```
   
   Where `decompose_ands` would be:
   ```ocaml
   let rec decompose_ands (IT.IT (term, bt, loc) as it) =
     match term with
     | Binop (And, lhs, rhs) ->
       decompose_ands lhs @ decompose_ands rhs
     | _ -> [it]
   ```

2. **lib/solver.ml** - When a constraint fails, try to pinpoint which one:
   - If constraint C fails, and C was decomposed from a logical function
   - Report which specific conjunct within the function failed

**Pros:**
- Very precise error messages
- Each conjunct gets its own source location (if we track them)
- SMT solver tries each independently

**Cons:**
- More SMT queries (each conjunct checked separately)
- May reveal too much internal structure
- Logical functions might be intentionally opaque abstractions
- Complicates solver interface

### Option 3: Enhanced Constraint Metadata

**Changes needed:**

1. **lib/logicalConstraints.ml** - Add metadata to constraints:
   ```ocaml
   type origin =
     | Direct
     | FromFunction of { func : Sym.t; 
                         args : IT.t list; 
                         conjunct_index : int option }
   
   type t =
     | T of IT.t * origin
     | Forall of (Sym.t * BT.t) * IT.t * origin
   ```

2. **lib/check.ml:2216-2222** - Annotate constraints with origin:
   ```ocaml
   | Some body ->
       let conjuncts = decompose_ands body in
       ListM.iteri (fun i c ->
         add_c loc (LC.T (c, FromFunction { func = f; args; conjunct_index = Some i })))
         conjuncts
   ```

3. **lib/typeErrors.ml** - Use origin in error messages:
   ```ocaml
   | Unproven_constraint { constr = LC.T (it, origin); ... } ->
       match origin with
       | FromFunction { func; conjunct_index = Some i; ... } ->
         !^"Unprovable constraint from" ^^^ Sym.pp func ^^
         !^"(conjunct" ^^^ int i ^^^ !^"of" ^^^ int (count_conjuncts func) ^^^ !^")"
       | _ -> !^"Unprovable constraint"
   ```

**Pros:**
- Precise attribution without multiple SMT queries
- Preserves abstraction (function name shown, not full expansion)
- Can show "conjunct 3 of 4 in all_properties"

**Cons:**
- Significant refactoring of constraint type
- Need to thread origin through all constraint operations
- Index might not be meaningful if conjuncts are reordered during simplification

## Recommendation

**Short-term (Option 1):** Enhance error reporting to show failing conjuncts from `simp_constraint`. This is a localized change in typeErrors.ml that immediately helps users.

**Long-term (Option 3):** Add constraint metadata to track origins. This enables:
- Better errors for logical functions
- Better errors for lemmas
- Better errors for resource predicates
- Debugging information about constraint sources

## Implementation Steps

### For Option 1 (Quick Win):

1. Modify `lib/typeErrors.ml` Unproven_constraint case to:
   - Call `Explain.simp_constraint` on the failing constraint
   - Filter simplified results to find conjuncts that evaluate to false
   - Include these in the error message description

2. Test with `logic_function_error.c` to verify it now shows which conjunct failed

### For Option 3 (Complete Solution):

1. Extend `lib/logicalConstraints.ml` with origin tracking
2. Update all constraint construction sites to provide origin
3. Update constraint operations (subst, free_vars, etc.) to preserve origin
4. Enhance `lib/typeErrors.ml` to use origin in messages
5. Add regression tests for various error scenarios

## Test Cases

Created test files in `tests/cn/alloc_id/`:
- `logic_function_error.c` - Demonstrates the error message problem
- `function_error_detailed.c` - More complex example with multiple properties
- `function_error_test.c` - Simpler test case

Run with: `cn verify tests/cn/alloc_id/logic_function_error.c`

## Related Code Locations

- **Constraint type:** `lib/logicalConstraints.ml:5-8`
- **Function expansion:** `lib/check.ml:2216-2222`
- **Error reporting:** `lib/typeErrors.ml:527-544`
- **Constraint simplification:** `lib/explain.ml:92-116`
- **Function definition:** `lib/definition.ml:3-82`
- **Trace generation:** `lib/explain.ml:142-441`

---

## Implementation Status

**✅ IMPLEMENTED - Option 1**

Successfully implemented Option 1 (Show failing conjuncts in error messages).

### Changes Made

1. **lib/explain.mli** - Exported `simp_constraint` function
2. **lib/typeErrors.ml** - Modified `Unproven_constraint` case to:
   - Expand function applications to their bodies
   - Simplify constraints into conjuncts
   - Evaluate each conjunct with the counter-example model
   - Report specifically which conjuncts are false

### Example Output

**Before:**
```
error: Unprovable constraint
    requires_properties(p, 5, 50, 55);
    ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ 
Constraint from file.c:20:14:
             all_properties(x, y, z);
             ^~~~~~~~~~~~~~~~~~~~~~~~ 
```

**After:**
```
error: Unprovable constraint
    requires_properties(p, 5, 50, 55);
    ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ 
Constraint from file.c:20:14:
             all_properties(x, y, z);
             ^~~~~~~~~~~~~~~~~~~~~~~~ 
Failing conjuncts:
  10'u64 < (u64)5'i32,   (u64)5'i32 % 2'u64 == 0'u64
```

The error now clearly shows that `x > 10` and `x % 2 == 0` are the failing properties!

### Test Cases

- `logic_function_error.c` - Original test showing 2 failing conjuncts
- `logic_function_multiple_failures.c` - Triangle inequality example showing specific violations

---

**Created:** 2026-05-19  
**Status:** ✅ Implemented and tested
