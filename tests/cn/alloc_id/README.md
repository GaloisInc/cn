# Provenance Tests and Documentation

This directory contains tests and documentation for CN's provenance separation features.

## Documentation

### ✅ Complete Documentation

- **`provenance_separation_guide.md`** - Comprehensive guide to provenance in CN
  - How pointers are represented (address + allocation ID)
  - Available operations: `(u64)ptr`, `(alloc_id)ptr`, `has_alloc_id(ptr)`
  - Use cases: MMIO, tagged pointers, integer arithmetic
  - Best practices and limitations

- **`pointer_integer_casts_guide.md`** - Guide to pointer/integer conversions
  - How casts work (ptr→int preserves, int→ptr loses provenance)
  - Using `__cerbvar_copy_alloc_id` builtin
  - Patterns from VIP testsuite

- **`copy_alloc_id_spec_findings.md`** - Investigation into spec-level copy_alloc_id
  - Why `copy_alloc_id` is not available in spec language
  - Why `cn_function` wrapper doesn't work
  - Workarounds and current limitations

## Test Files

### ✅ Positive Tests (Should Pass)

- **`provenance_demo_simple.c`** - **16/16 pass**
  - Main working example file
  - Demonstrates all provenance operations without __cerbvar_copy_alloc_id
  - Examples:
    - Extract address: `(u64)ptr`
    - Extract allocation ID: `(alloc_id)ptr`
    - Check provenance: `has_alloc_id(ptr)`
    - Compare addresses vs full pointer equality
    - Work with stored addresses (uintptr_t fields)
    - MMIO pattern with trusted functions
    - Allocation metadata with `Alloc` predicate
  
  **To verify:** `cn verify claude_scratch/provenance_demo_simple.c`

- **`copy_alloc_id_with_spec.c`** - **5/5 pass**
  - Tests __cerbvar_copy_alloc_id with proper spec
  - roundtrip, pointer_with_offset, set_tag_bit, clear_tag_bit, align_down
  
- **`copy_alloc_id_complete_demo.c`** - **9/9 pass**
  - Complete demonstration with __cerbvar_copy_alloc_id
  - All provenance operations including tagged pointers

### ❌ Negative Tests (Should Fail)

- **`copy_alloc_id_negative_tests.c`** - **10/10 fail correctly**
  - Verifies safety properties are enforced
  - Tests out-of-bounds, wrong allocation, missing resources, etc.
  - See `NEGATIVE_TESTS_SUMMARY.md` for details

**Total: 30 positive tests pass, 10 negative tests fail correctly ✅**

## Incomplete/Deprecated Test Files

### ⚠️ INCOMPLETE - Uses Unspecified Builtins

- **`provenance_demo.c`** - Comprehensive examples using `__cerbvar_copy_alloc_id`
  - **Status:** Many examples will FAIL because `__cerbvar_copy_alloc_id` lacks CN spec
  - **Purpose:** Shows what WOULD work with proper builtin spec
  - **Includes:**
    - Tagged pointers (set/clear tag bits)
    - Pointer arithmetic via integers
    - XOR linked lists
    - Array offset calculations
  - **See instead:** `provenance_demo_simple.c` for working examples

### ❌ NEGATIVE TESTS - Expected to Fail

These files demonstrate what DOESN'T work and why:

- **`cn_function_minimal.c`** - Minimal cn_function wrapper attempt
  - **Expected error:** "not a function with a pure/logical interpretation"
  - **Demonstrates:** `__cerbvar_copy_alloc_id` cannot be wrapped with `cn_function`

- **`cn_function_copy_alloc_id.c`** - Initial cn_function attempt
  - **Expected error:** Same as minimal
  - **Demonstrates:** Various syntax attempts, all fail

- **`cn_function_copy_alloc_id_v2.c`** - Refined cn_function attempt
  - **Expected error:** Same as minimal
  - **Demonstrates:** Trying to use in predicates, still fails

- **`cn_function_copy_alloc_id_v3.c`** - Final attempt with predicates
  - **Expected error:** Predicate parsing errors
  - **Demonstrates:** Even correct syntax can't work due to fundamental limitation

- **`copy_alloc_id_spec_test.c`** - Direct spec-level usage attempt
  - **Expected error:** Parser errors
  - **Demonstrates:** `copy_alloc_id(addr, ptr)` is not a spec function

## Quick Reference

### What Works in CN Specs

✅ **Extract address:**
```c
/*@ assert((u64)ptr == expected_addr); @*/
```

✅ **Extract allocation ID:**
```c
/*@ assert((alloc_id)ptr == (alloc_id)other_ptr); @*/
```

✅ **Check provenance exists:**
```c
/*@ requires has_alloc_id(ptr); @*/
```

✅ **Access allocation metadata:**
```c
/*@ requires take A = Alloc(ptr);
             A.base <= (u64)ptr;
             (u64)ptr + size <= A.base + A.size;
@*/
```

✅ **Compare addresses only:**
```c
/*@ assert((u64)p == (u64)q); @*/  // Ignores provenance
```

✅ **Full pointer equality:**
```c
/*@ assert(ptr_eq(p, q)); @*/  // Address AND provenance
```

### What Doesn't Work

❌ **Construct pointers in specs:**
```c
/*@ let new_ptr = copy_alloc_id(addr, old_ptr); @*/  // NOT AVAILABLE
```

❌ **Use in cn_function:**
```c
// Cannot wrap __cerbvar_copy_alloc_id with cn_function
```

❌ **Direct Pointer constructor:**
```c
/*@ let ptr = Pointer(alloc_id, addr); @*/  // NOT AVAILABLE
```

### Workaround Pattern

Use C builtin and assert properties in spec:

```c
int* reconstruct(uintptr_t addr, void *prov_source)
/*@ requires has_alloc_id(prov_source);
    ensures  (u64)return == addr;
             (alloc_id)return == (alloc_id)prov_source;
@*/
{
    return __cerbvar_copy_alloc_id(addr, prov_source);
}
```

## Testing Commands

```bash
# Verify working examples
cn verify claude_scratch/provenance_demo_simple.c

# Try negative tests (expect failures)
cn verify claude_scratch/cn_function_minimal.c
cn verify claude_scratch/copy_alloc_id_spec_test.c

# View documentation
cat claude_scratch/provenance_separation_guide.md
cat claude_scratch/copy_alloc_id_spec_findings.md
```

## Key Findings

1. **Provenance is separate from address** - Can extract and reason about each component independently
2. **Cannot construct in specs** - Can only construct pointers in C code with `__cerbvar_copy_alloc_id`
3. **Must reason via properties** - Specs assert properties (address, allocation ID) rather than constructing values
4. **MMIO needs trusted axioms** - Hardware addresses require trusted functions that axiomatically provide provenance
5. **cn_function doesn't help** - Cannot wrap `__cerbvar_copy_alloc_id` because it's not a pure logical function

## Future Work

To enable pointer construction in specs, CN would need:
- Expose `CopyAllocId` as built-in spec function (like `has_alloc_id`)
- Add `Pointer(alloc_id, addr)` constructor syntax
- Provide spec for `__cerbvar_copy_alloc_id` builtin

See `copy_alloc_id_spec_findings.md` for detailed analysis.
