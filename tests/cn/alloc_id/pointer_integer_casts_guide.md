# CN Pointer ↔ Integer Casts: Complete Guide

**Discovered: 2026-05-14**

Based on CN's VIP testsuite (`tests/cn_vip_testsuite/`) and implementation analysis.

## The Provenance Problem

CN (via Cerberus) tracks **provenance** (allocation IDs) separately from numeric addresses. A pointer in CN has two components:

1. **Address** - the numeric memory location (`uintptr_t`)
2. **Allocation ID** - which allocation this pointer belongs to (provenance)

### What Works

**Pointer → Integer: Always Safe**
```c
int *p = &x;
uintptr_t addr = (uintptr_t)p;  // ✅ Gets numeric address
/*@ assert(addr == (u64)p); @*/  // Can reason about address in specs
```

### What Breaks

**Integer → Pointer: Loses Provenance!**
```c
uintptr_t addr = (uintptr_t)p;
int *q = (int*)addr;            // ⚠️ q has address but NO allocation ID
*q = 42;                        // ❌ ERROR: "Missing resource for reading"
```

The cast from integer to pointer creates a pointer with:
- ✅ Correct numeric address
- ❌ **No allocation ID** - cannot be dereferenced!

From `lib/check.ml:1698-1712`:
```ocaml
| IntToPtr ->
  let sym, result = IT.fresh_named (BT.Loc ()) "intToPtr" loc in
  let cond = eq_ (arg, int_lit_ 0 (get_bt arg) here) here in
  let null_case = eq_ (result, null_ here) here in
  (* NOTE: the allocation ID is intentionally left unconstrained *)
  let alloc_case =
    and_
      [ hasAllocId_ result here;
        eq_ (cast_ Memory.uintptr_bt arg here, addr_ result here) here
      ]
      here
```

Key line: **"the allocation ID is intentionally left unconstrained"** - the resulting pointer may or may not have a valid allocation ID that CN can reason about.

## Solution: `__cerbvar_copy_alloc_id`

Use this Cerberus builtin to **copy** an allocation ID from a known-good pointer:

```c
void* __cerbvar_copy_alloc_id(uintptr_t address, void* provenance_source);
```

**Semantics:**
- Takes numeric `address` (from integer arithmetic)
- Copies allocation ID from `provenance_source` pointer
- Returns pointer at `address` with provenance from `provenance_source`

**Example: Roundtrip Cast**
```c
int *p = &x;
uintptr_t addr = (uintptr_t)p;

// Copy allocation ID from p to the address
int *q = __cerbvar_copy_alloc_id(addr, p);
*q = 42;  // ✅ Works! Has provenance from p
```

From `lib/check.ml:1769-1776`:
```ocaml
| Copy_alloc_id, [ pe1; pe2 ] ->
  check_pexpr pe1 (fun vt1 ->
    check_pexpr pe2 (fun vt2 ->
      let unspec = CF.Undefined.UB_unspec_copy_alloc_id in
      let@ () = check_has_alloc_id loc vt2 unspec in
      let ub = CF.Undefined.(UB_CERB004_unspecified unspec) in
      let result = copyAllocId_ ~addr:vt1 ~loc:vt2 loc in
      let@ () = check_live_alloc_bounds `Copy_alloc_id loc ub [ result ] in
      k result))
```

**Key constraint:** `check_live_alloc_bounds` - the resulting address must be within the bounds of the source allocation (or one-past-end).

## CN Spec Operations

### Address Operations

**`(u64)ptr`** - Get pointer's numeric address
```c
/*@ assert((u64)p == (u64)q); @*/  // Compare addresses
/*@ assert((u64)p == 0xE0000000u64); @*/  // Check specific address
```

**`ptr_eq(p, q)`** - Test pointer equality (address AND allocation ID)
```c
/*@ assert(ptr_eq(p, q)); @*/  // Same address and same allocation
```

**`has_alloc_id(p)`** - Check if pointer has valid allocation ID
```c
/*@ requires has_alloc_id(p); @*/  // Pointer must have provenance
```

### Allocation Metadata

**`Alloc(p)` predicate** - Access allocation metadata
```c
/*@ requires
      take A = Alloc(p);
      A.base <= (u64)p;                    // p is within allocation
      (u64)p + sizeof<int> <= A.base + A.size;  // Access is in-bounds
@*/
```

From `lib/alloc.ml:16`:
```ocaml
let value_bt = BaseTypes.Record [ (base_id, base_bt); (size_id, size_bt) ]
```

The `Alloc` predicate returns a record with:
- `base`: Base address of allocation (`uintptr_t`)
- `size`: Size of allocation in bytes (`uintptr_t`)

## Practical Patterns from VIP Tests

### Pattern 1: Roundtrip with Offset

From `tests/cn_vip_testsuite/provenance_roundtrip_via_intptr_t.pass.c`:

```c
int x = 1;
int *p = &x;
intptr_t i = (intptr_t)p;
int *q = (int *)i;
*q = 11;  // ✅ Works in VIP tests (assumes roundtrip preserves provenance)

// In CN, need explicit:
// int *q = __cerbvar_copy_alloc_id(i, &x);
```

### Pattern 2: Pointer Arithmetic via Integers

From `tests/cn_vip_testsuite/pointer_arith_algebraic_properties_2_global.annot.c`:

```c
int x[10], y[10];

// Cast to integer, do arithmetic, cast back
uintptr_t base = (uintptr_t)&x[0];
uintptr_t offset = ((uintptr_t)&y[1]) - ((uintptr_t)&y[0]);
uintptr_t result_addr = base + offset;

#ifdef ANNOT
int *p = copy_alloc_id(result_addr, x);  // copy_alloc_id from refinedc.h
#else
int *p = (int*)result_addr;  // Loses provenance
#endif

*p = 42;  // Only works with copy_alloc_id
```

Note: `copy_alloc_id` in VIP tests is a macro:
```c
// From tests/cn_vip_testsuite/refinedc.h:
#if defined(__cerb__) && defined(VIP)
#define copy_alloc_id(to, from) __cerbvar_copy_alloc_id(to, from)
#else
#define copy_alloc_id(to, from) ((uintptr_t)(from), (void*)(to))
#endif
```

### Pattern 3: Bit Masking / Tag Bits

From `tests/cn_vip_testsuite/provenance_tag_bits_via_uintptr_t_1.annot.c`:

```c
int x = 1;
int *p = &x;

// Check low bits are unused (alignment)
uintptr_t i = (uintptr_t)p;
assert(_Alignof(int) >= 4);
assert((i & 3u) == 0u);

// Set low bit as tag
i = i | 1u;

// Cast back with provenance
#ifdef ANNOT
int *q = copy_alloc_id(i, p);  // Tagged pointer
#else
int *q = (int*)i;  // Loses provenance
#endif

// Mask out tag and restore
uintptr_t j = ((uintptr_t)q) & ~((uintptr_t)3u);

#ifdef ANNOT
int *r = copy_alloc_id(j, p);  // Untagged pointer
#else
int *r = (int*)j;
#endif

*r = 11;  // ✅ Works with copy_alloc_id
```

### Pattern 4: Pointer Comparison via Integers

From `tests/cn_vip_testsuite/pointer_from_int_disambiguation_2.pass.c`:

```c
int x = 1, y = 2;
int *p = &x + 1;
int *q = &y;

uintptr_t i = (uintptr_t)p;
uintptr_t j = (uintptr_t)q;

// Compare as bytes (requires to_bytes/from_bytes)
/*@ to_bytes RW<int*>(&p); @*/
/*@ to_bytes RW<int*>(&q); @*/
int result = _memcmp((byte*)&p, (byte*)&q, sizeof(p));
/*@ from_bytes RW<int*>(&p); @*/
/*@ from_bytes RW<int*>(&q); @*/

if (result == 0) {
    // Addresses match, restore provenance
    int *r = __cerbvar_copy_alloc_id(i, &x);
    r = r - 1;  // Adjust back
    *r = 11;    // ✅ Safe with provenance
}
```

## Key Constraints and Limitations

### 1. Provenance Source Must Be Valid

```c
int *p = &x;
uintptr_t addr = 0xDEADBEEF;

// ❌ WRONG: p doesn't point to 0xDEADBEEF
int *q = __cerbvar_copy_alloc_id(addr, p);  // OUT OF BOUNDS ERROR
```

The address must be **within the bounds** (or one-past-end) of the provenance source's allocation.

### 2. Can't Manufacture Provenance from Nothing

```c
uintptr_t addr = 0xE0000000ULL;  // Hardware MMIO address
int *p = (int*)addr;             // Has NO provenance
*p = 42;                         // ❌ ERROR: Missing resource

// Need trusted function to axiomatically assert provenance exists
// (See mmio_clean_pattern.c)
```

### 3. Roundtrip Not Automatic

Unlike some C implementations, CN doesn't automatically preserve provenance through roundtrips:

```c
int *p = &x;
int *q = (int*)(uintptr_t)p;  // ❌ q may not have provenance

// Must use:
int *q = __cerbvar_copy_alloc_id((uintptr_t)p, p);  // ✅ Explicit
```

## Integration with MMIO

For MMIO at fixed addresses, combine with trusted functions:

```c
// Trusted: axiomatically assert MMIO exists at address
uint32_t* mmio_init();
/*@ spec mmio_init();
    trusted;
    ensures
        (u64)return == 0xE0000000u64;
        take A = Alloc(return);
        A.base == 0xE0000000u64;
        A.size >= 0x1000u64;
        take regs = each(u64 i; 0u64 <= i && i < 256u64) {
            RW<unsigned int>(array_shift<unsigned int>(return, i))
        };
@*/
```

See `mmio_clean_pattern.c` for complete example.

## Summary

**Safe pattern for pointer/integer round-trips:**
```c
// 1. Pointer to integer - always safe
uintptr_t addr = (uintptr_t)ptr;

// 2. Integer arithmetic
addr = addr + offset;
addr = addr & ~3ULL;  // Clear tag bits, etc.

// 3. Integer to pointer - MUST copy provenance
new_ptr = __cerbvar_copy_alloc_id(addr, ptr);

// 4. Dereference - now safe
*new_ptr = value;
```

**Constraints:**
- ✅ `addr` must be within `ptr`'s allocation bounds
- ✅ `ptr` must have valid provenance (`has_alloc_id(ptr)`)
- ✅ Resulting pointer inherits all bounds checking from source allocation
- ❌ Cannot manufacture provenance for arbitrary addresses (use `trusted` functions)

## References

- CN VIP Testsuite: `tests/cn_vip_testsuite/*.c`
- Implementation: `lib/check.ml` (lines 1690-1776)
- Alloc predicate: `lib/alloc.ml`
- Index terms: `lib/indexTerms.ml` (`addr_`, `allocId_`, `copyAllocId_`)
