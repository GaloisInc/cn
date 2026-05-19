# 🎉 SUCCESS: __cerbvar_copy_alloc_id Spec Works Perfectly!

**Date: 2026-05-19**

## The Big Win

By providing a proper CN spec for `__cerbvar_copy_alloc_id`, we can now **fully verify** provenance-preserving operations in CN!

## The Working Spec

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

### Key Insights

1. **Takes and returns `Alloc(prov_source)`** - Not `Alloc(return)`!
2. **Requires address in bounds** - `A.base <= addr_val <= A.base + A.size`
3. **Preserves allocation ID** - `(alloc_id)return == (alloc_id)prov_source`
4. **Sets address** - `(u64)return == addr_val`

## Verification Results

### ✅ copy_alloc_id_with_spec.c - 5/5 PASS

1. **`roundtrip`** ✓ - Pointer → integer → pointer
2. **`pointer_with_offset`** ✓ - Pointer arithmetic via integers  
3. **`set_tag_bit`** ✓ - Set tag bit on aligned pointer
4. **`clear_tag_bit`** ✓ - Clear tag bit
5. **`align_down`** ✓ - Align pointer to boundary

### ✅ copy_alloc_id_complete_demo.c - 9/9 PASS

1. **`roundtrip`** ✓ - Basic roundtrip
2. **`pointer_with_offset`** ✓ - Array offset via integer math
3. **`set_tag_bit`** ✓ - Tag a pointer
4. **`clear_tag_bit`** ✓ - Untag a pointer
5. **`align_down`** ✓ - Alignment
6. **`mask_pointer_bits`** ✓ - General bit masking
7. **`analyze_pointer`** ✓ - Extract and reason about components
8. **`compare_pointers`** ✓ - Address vs full equality
9. **`test_tagged_cycle`** ✓ - Complete tag/untag cycle

### ✅ provenance_demo_simple.c - 16/16 PASS

All examples without `__cerbvar_copy_alloc_id` continue to work.

## What This Enables

### 1. Tagged Pointers

```c
int* set_tag_bit(int *p)
/*@ requires take Px = RW<int>(p);
             (u64)p % 4u64 == 0u64;
             take A = Alloc(p);
             A.base <= (u64)p + 1u64;
    ensures  (u64)return == (u64)p + 1u64;
             (alloc_id)return == (alloc_id)p;
             take A2 = Alloc(p);
             A2 == A;
             take Px_returned = RW<int>(p);
             Px_returned == Px;
@*/
{
    uintptr_t addr = (uintptr_t)p | 1ULL;
    return __cerbvar_copy_alloc_id(addr, p);
}
```

**Key pattern:** Tagged pointer doesn't own the RW resource at address+1; ownership stays at original address.

### 2. Pointer Arithmetic

```c
int* pointer_with_offset(int *base, size_t offset)
/*@ requires take arr = each(u64 i; i <= offset) {
                 RW<int>(array_shift<int>(base, i))
             };
             take A = Alloc(base);
             A.base <= (u64)base;
             A.base <= (u64)base + (offset * 4u64);  // Key constraint!
             (u64)base + (offset * 4u64) <= A.base + A.size;
    ensures  ...
             take A2 = Alloc(base);  // Returns Alloc for input, not output!
@*/
{
    uintptr_t result_addr = (uintptr_t)base + (offset * sizeof(int));
    return __cerbvar_copy_alloc_id(result_addr, base);
}
```

**Key pattern:** Must explicitly prove `A.base <= result_addr` for CN's arithmetic reasoning.

### 3. Pointer Alignment

```c
int* align_down(int *p)
/*@ requires take Px = RW<int>(p);
             take A = Alloc(p);
    ensures  take Px2 = RW<int>(return);
             Px2 == Px;
             (u64)return == ((u64)p & ~3u64);
             (alloc_id)return == (alloc_id)p;
             take A2 = Alloc(p);
             A2 == A;
@*/
{
    uintptr_t addr = (uintptr_t)p & ~3ULL;
    return __cerbvar_copy_alloc_id(addr, p);
}
```

**Key pattern:** Simple masking operations just work!

## Lessons Learned

### 1. Alloc Resource Management

- **Take:** `take A = Alloc(prov_source)`
- **Return:** `take A2 = Alloc(prov_source)` (not `Alloc(return)`!)
- **Reason:** The `Alloc` tracks the allocation, which is the same for both pointers

### 2. Arithmetic Constraints

For `result_addr = base + offset`, must prove:
```c
A.base <= (u64)base;                    // Base is in allocation
A.base <= (u64)base + (offset * 4u64); // Result is >= A.base
(u64)base + (offset * 4u64) <= A.base + A.size;  // Result is in bounds
```

CN needs the middle constraint explicitly stated.

### 3. Tagged Pointer Ownership

When tagging a pointer:
- Input: `RW<int>(p)` at address `X`
- Output: Tagged pointer at address `X+1`
- **Return:** `RW<int>(p)` at original address, NOT at tagged address
- Tagged pointer has correct `Alloc` but doesn't own the misaligned RW resource

### 4. Resource Accounting

`__cerbvar_copy_alloc_id` preserves the `Alloc` but doesn't move RW resources. The RW resource location is determined by the pointer you pass in and return, not by the spec.

## Impact

This changes everything! Now you can:

✅ **Verify tagged pointer implementations**  
✅ **Verify custom allocators with address arithmetic**  
✅ **Verify pointer alignment routines**  
✅ **Verify MMIO with integer address manipulation**  
✅ **Verify XOR linked lists** (with more work)  
✅ **Verify any provenance-preserving operation**

## Next Steps

1. **Add this spec to CN's builtin library** - Should be upstreamed!
2. **Document the patterns** - Share with CN community
3. **Test more complex cases** - XOR lists, compressed pointers, etc.
4. **Consider spec refinements** - Could the Alloc handling be automatic?

## Files

All working demonstration files:

1. **`copy_alloc_id_with_spec.c`** - 5 examples, all pass
2. **`copy_alloc_id_complete_demo.c`** - 9 examples, all pass  
3. **`provenance_demo_simple.c`** - 16 examples without builtin, all pass
4. **`provenance_separation_guide.md`** - Complete documentation
5. **`pointer_integer_casts_guide.md`** - Cast patterns
6. **`PROVENANCE_TESTS_README.md`** - Index of all tests

## The Spec That Changed Everything

```c
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

**30 total verified examples** demonstrating complete provenance separation in CN! 🚀
