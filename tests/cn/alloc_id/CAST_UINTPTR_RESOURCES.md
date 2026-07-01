# Resources at Cast uintptr_t Values

## Summary

**You cannot use `RW<T>((pointer)uintptr_value)` to access memory through `(T*)uintptr_value` in C code.**

Even if you have `RW<int>((pointer)addr)` in your function's requires clause, trying to dereference `(int*)addr` in the code will fail with "Missing resource for reading/writing".

## The Problem

Each integer-to-pointer cast creates a **fresh pointer value** with an independent allocation ID:

- `(pointer)addr` in the **spec** → `bits_to_ptr(addr, alloc_id_1)` 
- `(int*)addr` in the **C code** → `bits_to_ptr(addr, alloc_id_2)`

Where `alloc_id_1` and `alloc_id_2` are **different** unconstrained fresh values.

CN's resource matching requires:
```
addr(requested) == addr(available) AND
alloc_id(requested) == alloc_id(available)
```

The address check passes (`addr == addr`), but the alloc_id check fails (`alloc_id_1 ≠ alloc_id_2`).

## Test Demonstrating the Issue

```c
void test(uintptr_t addr)
/*@ requires take P = RW<int>((pointer)addr);
    ensures  take Q = RW<int>((pointer)addr);
@*/
{
    int *p = (int *)addr;
    *p = 42;  // ERROR: Missing resource W<signed int>(intToPtr)
}
```

**Error:** `Missing resource for writing W<signed int>(intToPtr)`

Even though we have `RW<int>((pointer)addr)`, CN cannot prove that `intToPtr` (the runtime cast) equals `(pointer)addr` (the spec cast).

## Provenance is NOT Tracked Through Round Trips

Even when CN knows the cast history, provenance is lost:

```c
void roundtrip(int *p)
/*@ requires take P = RW<int>(p);
    ensures  take Q = RW<int>(p);
@*/
{
    uintptr_t addr = (uintptr_t)p;  // CN knows: addr = (u64)p
    int *q = (int *)addr;            // CN creates: q = bits_to_ptr(addr, fresh_id)
    
    *q = 42;  // ERROR: Missing resource
    
    // CN CANNOT prove:
    /*@ assert(ptr_eq(p, q)); @*/              // FAILS
    /*@ assert((alloc_id)p == (alloc_id)q); @*/ // FAILS
}
```

From the VIP testsuite: **"VIP roundtrip provenance is not preserved via operations"**

This is a fundamental design decision - provenance must be explicitly restored, it is not automatically tracked through integer operations.

## What DOES Work

### 1. Use `copy_alloc_id` Explicitly

```c
void works_with_copy_alloc_id(int *p)
/*@ requires take P = RW<int>(p);
    ensures  take Q = RW<int>(p);
@*/
{
    uintptr_t addr = (uintptr_t)p;
    int *q = __cerbvar_copy_alloc_id(addr, p);  // Explicitly copy provenance
    
    *q = 42;  // OK - q has same alloc_id as p
}
```

### 2. Provide Both Original Pointer and Cast in Spec

```c
void works_with_witness(int *witness, uintptr_t addr)
/*@ requires (u64)witness == addr;
             take P1 = RW<int>(witness);
             take P2 = RW<int>((pointer)addr);
    ensures  take Q1 = RW<int>(witness);
             take Q2 = RW<int>((pointer)addr);
@*/
{
    int *p = (int *)addr;
    *p = 42;  // OK - has both resources
}
```

But this requires having the original pointer available, which defeats the purpose.

### 3. Specify the Resource Directly at the Runtime Cast

If the pointer will ONLY be used through the cast (never the original), you can specify the resource at the cast location:

```c
void external_function(uintptr_t addr);
/*@ spec external_function(u64 addr);
    requires take P = RW<int>((pointer)addr);
    ensures  take Q = RW<int>((pointer)addr);
@*/
```

But callers must provide the resource at `(pointer)addr`, which means they also can't use regular pointers without similar issues.

## Why Casts Have Fresh Alloc IDs

In the SMT encoding (lib/solver.ml:989):

```ocaml
| Loc (), Bits _ ->  (* Integer to pointer cast *)
  CN_Pointer.bits_to_ptr ~bits:addr ~alloc_id:(default Alloc_id)
```

The `default Alloc_id` creates a fresh unconstrained SMT variable. There are no axioms connecting:
- The alloc_id of the result to any existing pointer's alloc_id
- Multiple casts of the same integer value to have the same alloc_id

Each cast is independent.

## Spec vs Code Cast Values

Casts in the spec and casts in the code are **different values**:

```c
void demonstrate_difference(uintptr_t addr)
/*@ requires take P = RW<int>((pointer)addr); @*/
{
    int *p = (int *)addr;
    
    // Both have the same address:
    /*@ assert((u64)p == addr); @*/                    // PASSES
    /*@ assert((u64)((pointer)addr) == addr); @*/      // PASSES
    
    // But they are not the same pointer:
    /*@ assert(ptr_eq(p, (pointer)addr)); @*/          // FAILS
    /*@ assert((alloc_id)p == (alloc_id)((pointer)addr)); @*/ // FAILS
}
```

## Checking Provenance

You CAN check whether a cast pointer has provenance:

```c
void check_provenance(uintptr_t addr)
/*@ requires take P = RW<int>((pointer)addr); @*/
{
    /*@ assert(has_alloc_id((pointer)addr)); @*/  // PASSES
    
    int *p = (int *)addr;
    /*@ assert(has_alloc_id(p)); @*/               // FAILS - p has no provable alloc_id
}
```

The spec cast `(pointer)addr` is treated as having *some* alloc_id (from the SMT solver's perspective), but after the runtime cast in code, CN cannot prove the result has any alloc_id.

## Implications for API Design

### Problem Pattern

```c
// BAD: Cannot be used
void api_function(uintptr_t addr)
/*@ requires take P = RW<int>((pointer)addr);
    ensures  take Q = RW<int>((pointer)addr);
@*/
{
    int *p = (int *)addr;
    *p = 42;  // ERROR - cannot use the resource
}
```

### Solution 1: Take a Real Pointer

```c
// GOOD: Use real pointers in API
void api_function(int *p)
/*@ requires take P = RW<int>(p);
    ensures  take Q = RW<int>(p);
@*/
{
    *p = 42;  // OK
}
```

### Solution 2: Take Both Pointer and Address with Relationship

```c
// GOOD: Take both with constraint
void api_function(int *p, uintptr_t addr)
/*@ requires (u64)p == addr;
             take P = RW<int>(p);
    ensures  take Q = RW<int>(p);
@*/
{
    // Can use either p or cast addr if we use copy_alloc_id
    int *q = __cerbvar_copy_alloc_id(addr, p);
    *q = 42;
}
```

### Solution 3: Use copy_alloc_id with Provenance Source

```c
// GOOD: Require a provenance source
void api_function(uintptr_t addr, void *prov_source)
/*@ requires has_alloc_id(prov_source);
             take A = Alloc(prov_source);
             A.base <= addr;
             addr + 4u64 <= A.base + A.size;
    ensures  take A2 = Alloc(prov_source);
             A2 == A;
@*/
{
    int *p = __cerbvar_copy_alloc_id(addr, prov_source);
    
    // Now need to get RW<int>(p) somehow - but p is fresh!
    // This pattern needs more thought...
}
```

## Related Files

- `tests/cn/pointer_cast_resource_matching.error.c` - Demonstrates resource matching failures
- `tests/cn/pointer_cast_roundtrip_tracking.c` - Shows provenance is not tracked through round trips
- `tests/cn/resource_at_cast_in_requires.c` - Shows having resource at cast in requires doesn't help
- `tests/cn/alloc_id/uintptr_to_pointer_resource.c` - Comprehensive tests of cast pointer resources
- `tests/cn/alloc_id/resource_at_cast_pointer.c` - Shows the witness pattern that does work

## Key Takeaways

1. **Cast pointers get fresh alloc_ids** - Each `(pointer)uintptr_value` creates a new independent alloc_id
2. **Spec casts ≠ Code casts** - `(pointer)x` in spec and `(T*)x` in code are different pointer values
3. **No automatic tracking** - CN does not track provenance through integer operations
4. **Must use copy_alloc_id** - Provenance must be explicitly restored with `__cerbvar_copy_alloc_id`
5. **API design matters** - Functions should take real pointers, not uintptr_t values that need casting

## See Also

- `provenance_separation_guide.md` - General guide to CN's provenance model
- `pointer_integer_casts_guide.md` - Guide to using pointer/integer conversions
- `PROVENANCE_AND_RESOURCES.md` - How provenance interacts with resources
