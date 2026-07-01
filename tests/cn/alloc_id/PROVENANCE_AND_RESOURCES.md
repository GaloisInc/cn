# Provenance and Resources in CN

## The Question

What happens when you try to use `RW<int>((pointer)some_uintptr)` where `some_uintptr` is a `uintptr_t` value?

## The Answer

**It doesn't work** - you cannot use resources like `RW<int>(p)` with a pointer that has no provenance.

## Why: Pointer Casts Lose Provenance

When you cast between pointers and integers in C:

```c
int *p = ...;           // p has provenance (allocation ID)
uintptr_t addr = (uintptr_t)p;  // addr is just a number (no provenance)
int *q = (int *)addr;   // q has NO provenance
```

### What CN Sees

- `p` has an allocation ID: `has_alloc_id(p) == true`
- `addr` is just a 64-bit integer
- `q` is represented internally as `intToPtr` (integer-to-pointer)
- `q` has **no allocation ID**: `has_alloc_id(q) == false`

## Testing This

```c
void test_cast_loses_provenance(int *p)
/*@ requires take P = RW<int>(p);
    ensures  take P2 = RW<int>(p);
@*/
{
    uintptr_t addr = (uintptr_t)p;
    int *q = (int *)addr;

    // These assertions show the problem:
    /*@ assert(has_alloc_id(p)); @*/   // ✓ TRUE - p has provenance
    /*@ assert(has_alloc_id(q)); @*/   // ✗ FALSE - q has NO provenance

    // This fails - can't write through q:
    *q = 42;  // Error: Missing resource for writing
}
```

**Error message:**
```
error: Missing resource for writing
    *q = 42;
Resource needed: W<signed int>(intToPtr)
```

CN can't find a resource for `intToPtr` because it has no allocation ID.

## Why Resources Need Provenance

CN resources are always associated with a specific allocation:

```c
RW<int>(p)   // Requires: p points into some allocation
             // CN tracks: which allocation, what offset
```

If `p` has no provenance:
- CN doesn't know which allocation this belongs to
- Can't verify it's in bounds
- Can't track ownership
- **Resource cannot be used**

## How to Fix It: Use `__cerbvar_copy_alloc_id`

To use a pointer that went through `uintptr_t`, you must explicitly restore provenance:

```c
void* __cerbvar_copy_alloc_id(uintptr_t addr, void* ptr);

/*@ spec __cerbvar_copy_alloc_id(u64 addr_val, pointer prov_source);
    requires has_alloc_id(prov_source);
             take A = Alloc(prov_source);
             A.base <= addr_val;
             addr_val <= A.base + A.size;
    ensures  (u64)return == addr_val;
             (alloc_id)return == (alloc_id)prov_source;
             take A2 = Alloc(prov_source);
             A2 == A;
@*/
```

### Example

```c
void test_restore_provenance(int *p)
/*@ requires take P = RW<int>(p);
             take A = Alloc(p);
    ensures  take P2 = RW<int>(p);
             take A2 = Alloc(p);
             A2 == A;
@*/
{
    uintptr_t addr = (uintptr_t)p;

    // Restore provenance: give it the allocation ID from p
    int *q = __cerbvar_copy_alloc_id(addr, p);

    // Now q has provenance:
    /*@ assert(has_alloc_id(q)); @*/
    /*@ assert((alloc_id)q == (alloc_id)p); @*/
    /*@ assert((u64)q == (u64)p); @*/

    // This works now:
    *q = 42;
}
```

**Key points:**
1. You need the original pointer `p` to provide the allocation ID
2. You need the `Alloc(p)` resource (allocation metadata)
3. You must prove `addr` is in bounds of the allocation
4. The result has the same allocation ID as `p`

## Typical Use Cases

### 1. Hardware/MMIO Addresses

For hardware addresses, you can't use `__cerbvar_copy_alloc_id` because there's no original pointer. Instead, use trusted functions:

```c
// Trusted axiom that hardware addresses have provenance
int* get_mmio_register(uintptr_t addr)
/*@ trusted;
    ensures (u64)return == addr;
            has_alloc_id(return);
@*/
{
    return (int *)addr;
}
```

### 2. Tagged Pointers

When you store pointers with tag bits:

```c
void use_tagged_pointer(int *p)
/*@ requires take P = RW<int>(p);
             take A = Alloc(p);
    ensures  take P2 = RW<int>(p);
             take A2 = Alloc(p);
             A2 == A;
@*/
{
    // Set a tag bit
    uintptr_t tagged = (uintptr_t)p | 0x1;

    // Later, clear the tag and restore provenance
    uintptr_t untagged_addr = tagged & ~0x1;
    int *restored = __cerbvar_copy_alloc_id(untagged_addr, p);

    // Use restored pointer
    *restored = 42;
}
```

### 3. Pointer Arithmetic via Integers

When you need to do arithmetic that C pointer arithmetic doesn't support:

```c
void complex_offset(int *arr)
/*@ requires take A = Alloc(arr);
    ensures  take A2 = Alloc(arr);
             A2 == A;
@*/
{
    uintptr_t base = (uintptr_t)arr;
    uintptr_t offset = compute_complex_offset();
    uintptr_t target = base + offset;

    // Restore provenance
    int *p = __cerbvar_copy_alloc_id(target, arr);

    // Use p (assuming in bounds)
}
```

## Summary

| Operation | Has Provenance? | Can use with RW? | How to fix |
|-----------|----------------|------------------|------------|
| `int *p` (original) | ✓ Yes | ✓ Yes | N/A |
| `(uintptr_t)p` | ✗ No (it's an integer) | N/A | N/A |
| `(int *)(uintptr_t)p` | ✗ No | ✗ No | Use `__cerbvar_copy_alloc_id` |
| `__cerbvar_copy_alloc_id(addr, p)` | ✓ Yes | ✓ Yes | N/A |

**Key principle:** Provenance is **not preserved** through integer casts in CN. You must explicitly restore it with `__cerbvar_copy_alloc_id` if you need to use resources or perform memory operations.

## Why This Design?

This matches the PNVI-ae-udi provenance model in C:
- Pointer-to-integer casts "expose" the provenance
- Integer-to-pointer casts don't automatically restore it
- Provenance must be explicitly tracked
- This prevents forging arbitrary pointers
- Ensures memory safety

CN makes this explicit by:
1. Tracking `has_alloc_id` as a property
2. Requiring provenance for memory operations
3. Providing `__cerbvar_copy_alloc_id` for explicit restoration

---

**Related:** See `provenance_separation_guide.md` for more details on CN's provenance model.
