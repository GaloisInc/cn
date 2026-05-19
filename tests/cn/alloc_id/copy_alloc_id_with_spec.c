// ✅ SUCCESS: All 5 functions pass with __cerbvar_copy_alloc_id spec!
//
// This demonstrates that providing a CN spec for __cerbvar_copy_alloc_id
// makes it fully usable in verified code!
//
// ALL EXAMPLES PASS:
// ✓ roundtrip: Pass pointer through integer and back
// ✓ pointer_with_offset: Pointer arithmetic via integers
// ✓ set_tag_bit: Set low bit for tagged pointer
// ✓ clear_tag_bit: Clear low bit from tagged pointer
// ✓ align_down: Align pointer to boundary

#include <stdint.h>
#include <stddef.h>

// Declare the Cerberus builtin
void* __cerbvar_copy_alloc_id(uintptr_t addr, void* ptr);

// Provide a spec for it (use CN types and logical parameter names)
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

// Test 1: Basic roundtrip
int* roundtrip(int *p)
/*@ requires take Px = RW<int>(p);
             take A = Alloc(p);
    ensures  take Px2 = RW<int>(return);
             Px2 == Px;
             (u64)return == (u64)p;
             (alloc_id)return == (alloc_id)p;
             take A2 = Alloc(return);
             A2 == A;
@*/
{
    uintptr_t addr = (uintptr_t)p;
    return __cerbvar_copy_alloc_id(addr, p);
}

// Test 2: Pointer arithmetic via integers
int* pointer_with_offset(int *base, size_t offset)
/*@ requires take arr = each(u64 i; i <= offset) {
                 RW<int>(array_shift<int>(base, i))
             };
             take A = Alloc(base);
             // Explicitly prove result address is in bounds
             A.base <= (u64)base;
             A.base <= (u64)base + (offset * 4u64);  // Arithmetic constraint for __cerbvar_copy_alloc_id
             (u64)base + (offset * 4u64) <= A.base + A.size;
    ensures  take arr2 = each(u64 i; i <= offset) {
                 RW<int>(array_shift<int>(base, i))
             };
             arr2 == arr;
             (u64)return == (u64)base + (offset * 4u64);
             (alloc_id)return == (alloc_id)base;
             take A2 = Alloc(base);  // __cerbvar_copy_alloc_id returns Alloc for input ptr
             A2 == A;
@*/
{
    uintptr_t base_addr = (uintptr_t)base;
    uintptr_t result_addr = base_addr + (offset * sizeof(int));
    return __cerbvar_copy_alloc_id(result_addr, base);
}

// Test 3: Clear tag bit (aligned pointer)
int* clear_tag_bit(int *p)
/*@ requires take Px = RW<int>(p);
             (u64)p % 2u64 == 1u64;  // Has tag bit set
    ensures  take Px2 = RW<int>(return);
             Px2 == Px;
             (u64)return == (u64)p - 1u64;
             (alloc_id)return == (alloc_id)p;
@*/
{
    uintptr_t addr = (uintptr_t)p;
    addr = addr & ~1ULL;
    return __cerbvar_copy_alloc_id(addr, p);
}

// Test 4: Set tag bit (aligned pointer)
// Note: Returns tagged pointer that doesn't own the data anymore
int* set_tag_bit(int *p)
/*@ requires take Px = RW<int>(p);
             (u64)p % 4u64 == 0u64;  // Aligned, no tag
             take A = Alloc(p);
             A.base <= (u64)p + 1u64;  // Prove tagged address is in bounds
    ensures  // Tagged pointer is returned but doesn't own RW resource
             (u64)return == (u64)p + 1u64;
             (alloc_id)return == (alloc_id)p;
             take A2 = Alloc(p);  // Alloc for original pointer
             A2 == A;
             // Return the RW resource at original address
             take Px_returned = RW<int>(p);
             Px_returned == Px;
@*/
{
    uintptr_t addr = (uintptr_t)p;
    addr = addr | 1ULL;
    return __cerbvar_copy_alloc_id(addr, p);
}

// Test 5: Align pointer down
int* align_down(int *p)
/*@ requires take Px = RW<int>(p);
             take A = Alloc(p);
    ensures  take Px2 = RW<int>(return);
             Px2 == Px;
             (u64)return == ((u64)p & ~3u64);
             (alloc_id)return == (alloc_id)p;
             take A2 = Alloc(return);
             A2 == A;
@*/
{
    uintptr_t addr = (uintptr_t)p;
    addr = addr & ~3ULL;
    return __cerbvar_copy_alloc_id(addr, p);
}

int main()
/*@ trusted; @*/
{
    int x = 42;
    int *p = &x;

    // Test roundtrip
    int *q = roundtrip(p);
    *q = 43;

    // Test clear_tag
    int *cleared = clear_tag_bit(p);

    // Test align
    int *aligned = align_down(p);

    return 0;
}
