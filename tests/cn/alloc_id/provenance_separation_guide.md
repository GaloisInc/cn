# CN Provenance Separation: Splitting Address and Allocation ID

**Created: 2026-05-19**

## Overview

CN (via Cerberus) represents pointers as a pair of:
1. **Address** (`uintptr_t`) - the numeric memory location
2. **Allocation ID** (`alloc_id`) - provenance tracking which allocation this pointer belongs to

This document covers how to work with these components separately in CN's spec language, which is critical for reasoning about hardware addresses (MMIO), tagged pointers, and pointer/integer round-trips.

## Pointer Representation in CN

### Internal Structure

From `lib/terms.ml:8-11`:
```ocaml
| Pointer of
    { alloc_id : Z.t;
      addr : Z.t
    }
```

Pointers are internally a product type `(alloc_id, address)`.

### SMT Encoding

From `lib/solver.ml:248-300`:
```ocaml
let alloc_id_addr_name = "AiA"

(SMT.declare_datatype
   "CN_Pointer"
   []
   [ (null_name, []);
     ( alloc_id_addr_name,
       [ (alloc_id_name, CN_AllocId.t ()); 
         (addr_name, SMT.t_bits width) ] )
   ])
```

In SMT, pointers are represented as a datatype with two constructors:
- `NULL` - null pointer
- `AiA(alloc_id, addr)` - non-null pointer with provenance and address

## Spec Language Operations

### 1. Extract Address: `(u64)ptr`

**Syntax:** Cast pointer to `uintptr_t` (or any unsigned integer type)

**Example:**
```c
int *p = &x;
/*@ assert((u64)p == 0xE0000000u64); @*/  // Check specific address
/*@ assert((u64)p == (u64)q); @*/         // Compare addresses only
```

**Implementation:** `lib/indexTerms.ml:692-694`
```ocaml
let addr_ it loc =
  assert (BT.equal (get_bt it) (Loc ()));
  cast_ Memory.uintptr_bt it loc
```

**SMT Translation:** `lib/solver.ml:990-997`
```ocaml
| Loc (), Bits _ ->
  maybe_cast (CN_Pointer.addr_of ~ptr:smt_term)
```

Uses the SMT function `addr_of` which pattern-matches the pointer:
```smt2
(define-fun addr_of ((p CN_Pointer)) (_ BitVec 64)
  (match p
    (case NULL (_ bv0 64))
    (case (AiA alloc_id addr) addr)))
```

### 2. Extract Allocation ID: `(alloc_id)ptr`

**Syntax:** Cast pointer to `alloc_id` type

**Example:**
```c
int *p = &x;
int *q = &y;

/*@ 
  let p_aid = (alloc_id)p;
  let q_aid = (alloc_id)q;
  assert(p_aid != q_aid);  // Different allocations
@*/
```

**Implementation:** `lib/indexTerms.ml:707`
```ocaml
let allocId_ it loc = cast_ Alloc_id it loc
```

**SMT Translation:** `lib/solver.ml:998-999`
```ocaml
| Loc (), Alloc_id ->
  CN_Pointer.alloc_id_of ~ptr:smt_term ~null_case:(default Alloc_id)
```

Uses the SMT function `alloc_id_of`:
```smt2
(define-fun alloc_id_of ((p CN_Pointer) (null_case CN_AllocId)) CN_AllocId
  (match p
    (case NULL null_case)
    (case (AiA alloc_id addr) alloc_id)))
```

### 3. Check Provenance: `has_alloc_id(ptr)`

**Syntax:** Predicate that checks if pointer has valid allocation ID

**Example:**
```c
/*@ requires has_alloc_id(p); @*/
void foo(int *p) {
  *p = 42;  // Safe: p has provenance
}
```

**Implementation:** `lib/indexTerms.ml:721-729`
```ocaml
let hasAllocId_ ptr loc =
  (* Handles member shifts and array shifts specially *)
  let rec futz = function
    | IT ((MemberShift (base, _, _) | ArrayShift { base; _ }), _, _) -> futz base
    | it -> it
  in
  IT (HasAllocId (futz ptr), BT.Bool, loc)
```

**Note:** The "futzing" is necessary because `&p[x]` and `&p->x` should inherit provenance from `p`, but the SMT solver doesn't automatically prove this implication.

**SMT Translation:** `lib/solver.ml:902`
```ocaml
| HasAllocId loc -> 
  SMT.is_con CN_Pointer.alloc_id_addr_name (translate_term s loc)
```

This checks if the pointer is the `AiA` constructor (not `NULL`).

### 4. Combine Address and Provenance: `copy_alloc_id(addr, ptr)`

**C Builtin:** `__cerbvar_copy_alloc_id(uintptr_t addr, void *ptr)`

**Semantics:** 
- Takes numeric address `addr`
- Copies allocation ID from `ptr`
- Returns new pointer with `addr` and provenance from `ptr`
- **Constraint:** `addr` must be within bounds of `ptr`'s allocation (or one-past-end)

**Example:**
```c
int *p = &x;
uintptr_t addr = (uintptr_t)p;

// Do arithmetic on address
addr = addr + 4;

// Restore pointer with original provenance
int *q = __cerbvar_copy_alloc_id(addr, p);
*q = 42;  // ✅ Safe: has provenance from p
```

**Implementation:** `lib/check.ml:1769-1786`
```ocaml
| Copy_alloc_id, [ pe1; pe2 ] ->
  check_pexpr pe1 (fun vt1 ->
    check_pexpr pe2 (fun vt2 ->
      let unspec = CF.Undefined.UB_unspec_copy_alloc_id in
      let@ () = check_has_alloc_id loc vt2 unspec in  (* vt2 must have alloc_id *)
      let ub = CF.Undefined.(UB_CERB004_unspecified unspec) in
      let result = copyAllocId_ ~addr:vt1 ~loc:vt2 loc in
      let@ () = check_live_alloc_bounds `Copy_alloc_id loc ub [ result ] in  (* Must be in-bounds *)
      k result))
```

**Key checks:**
1. `check_has_alloc_id loc vt2` - Source pointer must have valid provenance
2. `check_live_alloc_bounds` - Resulting pointer must be within bounds of source allocation

**SMT Translation:** Uses `copy_alloc_id` SMT function (lib/solver.ml:315-323):
```smt2
(define-fun copy_alloc_id ((p CN_Pointer) (new_addr (_ BitVec 64)) (null_case CN_Pointer)) CN_Pointer
  (match p
    (case NULL null_case)
    (case (AiA alloc_id addr) (AiA alloc_id new_addr))))
```

### 5. Pointer Equality: `ptr_eq(p, q)`

Checks BOTH address AND allocation ID match.

**Contrast with:**
- `(u64)p == (u64)q` - Only checks addresses match (ignores provenance)
- `ptr_eq(p, q)` - Checks both address and provenance match

**Example:**
```c
int x[10];
int *p = &x[0];
uintptr_t addr = (uintptr_t)p;
int *q = (int*)addr;  // Loses provenance!

/*@ 
  assert((u64)p == (u64)q);  // ✅ Same address
  assert(ptr_eq(p, q));       // ❌ May fail: q might not have provenance
@*/
```

## Use Cases for Provenance Separation

### 1. MMIO (Memory-Mapped I/O) at Fixed Hardware Addresses

**Problem:** Hardware registers exist at fixed addresses like `0xE0000000`, but CN requires provenance to dereference pointers.

**Solution:** Use `trusted` functions to axiomatically assert provenance exists:

```c
uint32_t* mmio_init();
/*@ spec mmio_init();
    trusted;
    ensures
        (u64)return == 0xE0000000u64;           // At hardware address
        take A = Alloc(return);                 // Has allocation metadata
        A.base == 0xE0000000u64;               // Allocation base matches
        A.size >= 0x1000u64;                   // 4KB region
        take regs = each(u64 i; 0u64 <= i && i < 256u64) {
            RW<unsigned int>(array_shift<unsigned int>(return, i))
        };
@*/

void driver_write(uint32_t val) {
    uint32_t *mmio = mmio_init();
    mmio[0x10] = val;  // ✅ Safe: has provenance from trusted init
}
```

**Key idea:** Separate "address is at 0xE0000000" (provable) from "provenance exists for this address" (axiom).

### 2. Tagged Pointers (Using Low Bits)

**Pattern:** Use low bits of aligned pointers for tags

```c
struct Node {
    int data;
    struct Node *next;  // Low bit used as "visited" flag
};

/*@ 
predicate TaggedNode(pointer p, u64 tag) {
    take base_addr = (u64)p & ~1u64;           // Mask out tag bit
    take tagged_aid = (alloc_id)p;             // Get original provenance
    take base = Pointer(tagged_aid, base_addr); // Reconstruct untagged pointer
    take N = Owned<struct Node>(base);
    tag == ((u64)p & 1u64);                    // Extract tag
    return { base: base, node: N };
}
@*/

struct Node* mark_visited(struct Node *p) 
/*@ requires take TN = TaggedNode(p, 0u64);
    ensures  take TN2 = TaggedNode(return, 1u64);
             TN2.base == TN.base;
             TN2.node == TN.node;
@*/
{
    uintptr_t addr = (uintptr_t)p;
    addr = addr | 1;  // Set visited bit
    return __cerbvar_copy_alloc_id(addr, p);  // Preserve provenance
}

struct Node* get_next(struct Node *p) 
/*@ requires take TN = TaggedNode(p, _);
             take next_ptr = TN.node.next;
             has_alloc_id(next_ptr);
    ensures  ptr_eq(return, next_ptr);
@*/
{
    uintptr_t addr = (uintptr_t)p;
    addr = addr & ~1ULL;  // Clear tag
    struct Node *untagged = __cerbvar_copy_alloc_id(addr, p);
    return untagged->next;
}
```

**Key operations:**
- `(u64)p & ~1u64` - Extract address without tag
- `(alloc_id)p` - Preserve original allocation ID through tagging
- `copy_alloc_id` - Reconstruct pointer with new address but original provenance

### 3. Pointer Arithmetic via Integer Operations

**Use case:** Operations not directly expressible as pointer arithmetic

```c
int arr[100];

// Find middle element using integer division
int* find_middle(int *start, int *end)
/*@ requires take start_val = (u64)start;
             take end_val = (u64)end;
             start_val <= end_val;
             take start_aid = (alloc_id)start;
             take end_aid = (alloc_id)end;
             start_aid == end_aid;  // Same allocation
    ensures  take result_val = (u64)return;
             result_val == start_val + ((end_val - start_val) / 2u64);
@*/
{
    uintptr_t start_addr = (uintptr_t)start;
    uintptr_t end_addr = (uintptr_t)end;
    uintptr_t mid_addr = start_addr + ((end_addr - start_addr) / 2);
    return __cerbvar_copy_alloc_id(mid_addr, start);
}
```

**Why this pattern:**
- Integer operations (division, bitwise AND/OR) not valid on pointer types
- Must convert to integers, operate, then restore provenance

### 4. Pointer Comparison for Serialization

**Use case:** Compare pointer representations as bytes (e.g., for hash tables, serialization)

```c
bool ptr_bytes_equal(void *p, void *q) 
/*@ requires true;
    ensures  return == (((u64)p == (u64)q) ? 1u8 : 0u8);
@*/
{
    uintptr_t p_addr = (uintptr_t)p;
    uintptr_t q_addr = (uintptr_t)q;
    return p_addr == q_addr;
}
```

**Note:** This only compares addresses, not allocation IDs. For full pointer equality, use `ptr_eq(p, q)`.

### 5. Computing with Stored Addresses (uintptr_t fields)

**Use case:** Pointer stored as `uintptr_t` in hardware descriptor, need to reconstruct with provenance

```c
struct DMA_Descriptor {
    uint64_t buffer_addr;  // Physical address as integer
    uint32_t size;
};

/*@ 
predicate DMA_Ready(pointer desc, pointer buf, u64 size) {
    take D = Owned<struct DMA_Descriptor>(desc);
    D.buffer_addr == (u64)buf;           // Address stored matches
    D.size == size;
    has_alloc_id(buf);                   // buf must have provenance
    take B = each(u64 i; i < size) {
        Block<char>(array_shift<char>(buf, i))
    };
    return { desc_data: D, buffer: B };
}
@*/

void process_dma(struct DMA_Descriptor *desc, void *buf_with_provenance)
/*@ requires take DR = DMA_Ready(desc, buf_with_provenance, desc->size);
    ensures  take DR2 = DMA_Ready(desc, buf_with_provenance, desc->size);
             DR2.buffer == DR.buffer;  // Buffer data unchanged
@*/
{
    // Hardware wrote address as integer
    uint64_t stored_addr = desc->buffer_addr;
    
    // Verify it matches our buffer
    assert((uint64_t)buf_with_provenance == stored_addr);
    
    // Use buf_with_provenance (has provenance) not stored_addr (just integer)
    char *buf = (char*)buf_with_provenance;
    buf[0] = 0xFF;  // ✅ Safe: buf has provenance
    
    // ❌ WRONG: Can't use stored_addr directly
    // char *bad = (char*)stored_addr;  // No provenance!
    // bad[0] = 0xFF;  // ERROR: Missing resource
    
    // ✅ Alternative: Copy provenance explicitly
    char *restored = __cerbvar_copy_alloc_id(stored_addr, buf_with_provenance);
    restored[0] = 0xFF;  // Safe: has provenance from buf_with_provenance
}
```

**Key pattern:**
1. Store address as `uintptr_t` (loses provenance)
2. Keep separate pointer with provenance
3. Verify addresses match: `(u64)ptr == stored_addr`
4. Use pointer with provenance, not stored integer
5. If needed, use `copy_alloc_id(stored_addr, ptr_with_provenance)` to reconstruct

## Type System Summary

### Base Types

From `lib/baseTypes.ml:13`:
```ocaml
| Alloc_id   (* Allocation ID / provenance *)
| Loc ()      (* Pointer = (alloc_id, address) *)
| Bits (sign, width)  (* Integer types including uintptr_t *)
```

### Cast Operations

| From | To | Operation | SMT Function |
|------|-----|-----------|--------------|
| `Loc()` | `Bits(_, 64)` | Extract address | `addr_of` |
| `Loc()` | `Alloc_id` | Extract allocation ID | `alloc_id_of` |
| `Bits(_, 64)` | `Loc()` | Integer to pointer (⚠️ loses provenance) | `bits_to_ptr` with unconstrained alloc_id |

### Term Constructors

From `lib/terms.ml:103-107`:
```ocaml
| CopyAllocId of
    { addr : 'bt annot;      (* New address (uintptr_t) *)
      loc : 'bt annot        (* Source pointer (Loc) for provenance *)
    }
| HasAllocId of 'bt annot    (* Check pointer has valid provenance *)
```

## Constraints and Limitations

### 1. Cannot Manufacture Provenance from Nothing

```c
uintptr_t hardware_addr = 0xE0000000ULL;
int *p = (int*)hardware_addr;  // ❌ No provenance!
*p = 42;  // ERROR: Missing resource

// Must use trusted function or copy_alloc_id from known pointer
```

### 2. copy_alloc_id Requires In-Bounds Address

```c
int x;
int *p = &x;
uintptr_t far_addr = 0xDEADBEEF;

int *q = __cerbvar_copy_alloc_id(far_addr, p);  // ❌ ERROR: Out of bounds
// far_addr is not within allocation of x
```

From `lib/check.ml:1785`:
```ocaml
let@ () = check_live_alloc_bounds `Copy_alloc_id loc ub [ result ] in
```

The address must satisfy:
```
alloc.base <= addr <= alloc.base + alloc.size
```

### 3. Roundtrip Not Automatic

```c
int *p = &x;
int *q = (int*)(uintptr_t)p;  // ⚠️ May lose provenance

// Must explicitly preserve:
int *q = __cerbvar_copy_alloc_id((uintptr_t)p, p);  // ✅ Preserves provenance
```

### 4. Allocation ID is Opaque

Cannot construct specific allocation IDs or compare them directly in specs (they're abstract):

```c
// ❌ Can't write:
// alloc_id new_aid = 42;  // No way to construct
// assert((alloc_id)p == 42);  // No numeric value

// ✅ Can write:
assert((alloc_id)p == (alloc_id)q);  // Compare IDs
assert(has_alloc_id(p));  // Check exists
```

## Best Practices

### Pattern 1: Preserve Provenance Through Integer Operations

```c
// ✅ Good
uintptr_t addr = (uintptr_t)ptr;
addr = addr & ~3ULL;  // Arithmetic on address
ptr = __cerbvar_copy_alloc_id(addr, ptr);  // Restore provenance

// ❌ Bad
uintptr_t addr = (uintptr_t)ptr;
addr = addr & ~3ULL;
ptr = (void*)addr;  // Lost provenance!
```

### Pattern 2: Separate Address Reasoning from Provenance Reasoning

```c
/*@ 
requires 
    // Address constraints
    (u64)p >= 0x1000u64;
    (u64)p + size <= 0x2000u64;
    // Provenance constraints  
    has_alloc_id(p);
    take A = Alloc(p);
    A.base <= (u64)p;
    (u64)p + size <= A.base + A.size;
@*/
```

Keep address arithmetic and provenance validity as separate concerns.

### Pattern 3: Use Alloc Predicate for Bounds

```c
/*@ 
requires 
    take A = Alloc(p);
    // Now can reason about allocation bounds
    A.base <= (u64)p;
    (u64)p + sizeof<T> <= A.base + A.size;
@*/
```

The `Alloc` predicate gives you:
- `A.base : u64` - Base address of allocation
- `A.size : u64` - Size in bytes

### Pattern 4: Document Provenance Requirements

When writing specs that need provenance:

```c
int* get_buffer();
/*@ spec get_buffer();
    ensures 
        (u64)return == 0xE0000000u64;  // Address requirement
        has_alloc_id(return);           // Provenance requirement
        take A = Alloc(return);
        A.size >= 4096u64;              // Size requirement
@*/
```

Make it explicit:
1. What address you expect
2. That provenance must exist
3. What the allocation bounds are

## References

### Source Files
- `lib/terms.ml` - AST definitions for `CopyAllocId`, `HasAllocId`
- `lib/indexTerms.ml` - Constructor functions `addr_`, `allocId_`, `copyAllocId_`, `hasAllocId_`
- `lib/baseTypes.ml` - Base type `Alloc_id`
- `lib/solver.ml` - SMT encoding of pointer representation and operations
- `lib/check.ml` - Type checking and bounds checking for `copy_alloc_id`
- `lib/alloc.ml` - `Alloc` predicate definition

### Test Files
- `tests/cn_vip_testsuite/provenance_*.c` - Provenance tests from VIP suite
- `tests/cn_vip_testsuite/pointer_from_int_*.c` - Integer/pointer cast tests
- `tests/cn_vip_testsuite/refinedc.h` - `copy_alloc_id` macro definition

### Related Documentation
- `claude_scratch/pointer_integer_casts_guide.md` - Complete guide to pointer/integer casts
- `claude_scratch/mmio_clean_pattern.c` - Example MMIO pattern (if exists)

## Future Work: Explicit Provenance Parameters

**Current limitation:** Cannot write specs that take provenance as a separate parameter.

**Desired pattern:**
```c
// Hypothetical future syntax
uint32_t* reconstruct_ptr(uintptr_t addr, alloc_id prov)
/*@ spec reconstruct_ptr(addr, prov);
    requires has_alloc_id(Pointer(prov, addr));  // Address is valid for this provenance
    ensures  (u64)return == addr;
             (alloc_id)return == prov;
@*/
{
    // Would need language-level support
}
```

**Current workaround:** Must pass a pointer with the provenance you need, then use `copy_alloc_id`:

```c
uint32_t* reconstruct_ptr(uintptr_t addr, void *prov_source)
/*@ spec reconstruct_ptr(addr, prov_source);
    requires has_alloc_id(prov_source);
             take A = Alloc(prov_source);
             A.base <= addr;
             addr + 4u64 <= A.base + A.size;
    ensures  (u64)return == addr;
             (alloc_id)return == (alloc_id)prov_source;
@*/
{
    return __cerbvar_copy_alloc_id(addr, prov_source);
}
```

**Why this matters for MMIO:**

With MMIO, you often have:
- Hardware address `0xE0000000` stored as `uintptr_t` in device tree or hardware manual
- Need to assert that this specific address has provenance (via `trusted` axiom)
- But can't directly construct `Pointer(some_alloc_id, 0xE0000000)` in specs

Current approach requires:
1. Trusted function returns pointer (has both address and provenance)
2. Spec asserts address value matches expected: `(u64)return == 0xE0000000u64`
3. Spec asserts provenance exists: `has_alloc_id(return)`

See MMIO example in "Use Cases" section above.

## Conclusion

CN provides full support for reasoning about address and provenance separately:

**✅ Can do:**
- Extract address: `(u64)ptr`
- Extract allocation ID: `(alloc_id)ptr`
- Check provenance exists: `has_alloc_id(ptr)`
- Combine address + provenance: `copy_alloc_id(addr, ptr_with_prov)`
- Reason about allocation bounds: `Alloc(ptr)` predicate

**⚠️ Limitations:**
- Cannot construct arbitrary allocation IDs
- Cannot pass provenance as separate parameter (must pass pointer)
- Must use `trusted` functions to axiomatically assert provenance for hardware addresses

**Common patterns:**
1. **Tagged pointers**: Extract address, modify bits, restore with `copy_alloc_id`
2. **MMIO**: Use `trusted` function returning pointer at hardware address with provenance
3. **Integer arithmetic**: Convert to integer, compute, restore provenance
4. **Stored addresses**: Keep provenance-carrying pointer alongside `uintptr_t` value

The key insight is that **addresses are data you can compute with**, while **provenance is a capability you must preserve** through explicit operations like `copy_alloc_id`.
