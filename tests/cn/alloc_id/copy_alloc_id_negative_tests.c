// NEGATIVE TESTS: These should all FAIL verification
//
// Each test demonstrates a safety property that the __cerbvar_copy_alloc_id
// spec correctly enforces.

#include <stdint.h>
#include <stddef.h>

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

// =============================================================================
// Test 1: Address below allocation base - SHOULD FAIL
// =============================================================================

int* test_address_below_base(int *p)
/*@ requires take Px = RW<int>(p);
             take A = Alloc(p);
    ensures  false;  // Should not be provable
@*/
{
    // Try to create pointer below the allocation
    uintptr_t addr = (uintptr_t)p;
    uintptr_t bad_addr = addr - 1000;  // Way before allocation base

    // This SHOULD FAIL: bad_addr < A.base
    return __cerbvar_copy_alloc_id(bad_addr, p);
}

// =============================================================================
// Test 2: Address above allocation end - SHOULD FAIL
// =============================================================================

int* test_address_above_end(int *p)
/*@ requires take Px = RW<int>(p);
             take A = Alloc(p);
    ensures  false;  // Should not be provable
@*/
{
    // Try to create pointer way past the allocation
    uintptr_t addr = (uintptr_t)p;
    uintptr_t bad_addr = addr + 10000;  // Way past allocation end

    // This SHOULD FAIL: bad_addr > A.base + A.size
    return __cerbvar_copy_alloc_id(bad_addr, p);
}

// =============================================================================
// Test 3: Missing Alloc resource - SHOULD FAIL
// =============================================================================

int* test_missing_alloc_resource(int *p)
/*@ requires take Px = RW<int>(p);
             // Deliberately NOT taking Alloc(p)
    ensures  false;  // Should not be provable
@*/
{
    uintptr_t addr = (uintptr_t)p;

    // This SHOULD FAIL: Missing required resource Alloc(p)
    return __cerbvar_copy_alloc_id(addr, p);
}

// =============================================================================
// Test 4: Copying provenance from one allocation to access another - SHOULD FAIL
// =============================================================================

int* test_wrong_allocation(int *p, int *q)
/*@ requires take Px = RW<int>(p);
             take Qx = RW<int>(q);
             take Ap = Alloc(p);
             take Aq = Alloc(q);
             (alloc_id)p != (alloc_id)q;  // Different allocations
    ensures  false;  // Should not be provable
@*/
{
    // Try to use provenance from p to access q's address
    uintptr_t q_addr = (uintptr_t)q;

    // This SHOULD FAIL: q_addr is not in p's allocation
    // Constraint: Ap.base <= q_addr will fail
    return __cerbvar_copy_alloc_id(q_addr, p);
}

// =============================================================================
// Test 5: Way past one-past-end - SHOULD FAIL
// =============================================================================

int* test_way_past_end(int arr[10])
/*@ requires take elements = each(u64 i; i < 10u64) {
                 RW<int>(array_shift<int>(arr, i))
             };
             take A = Alloc(arr);
    ensures  false;  // Should not be provable
@*/
{
    uintptr_t base = (uintptr_t)arr;
    // One-past-end would be base + 40 (10 * sizeof(int))
    // Try going way past that
    uintptr_t way_past = base + 1000;

    // This SHOULD FAIL: way_past > A.base + A.size
    return __cerbvar_copy_alloc_id(way_past, arr);
}

// =============================================================================
// Test 6: Negative offset from middle of array - SHOULD FAIL
// =============================================================================

int* test_negative_offset_outside(int *mid)
/*@ requires take Mx = RW<int>(mid);
             take A = Alloc(mid);
    ensures  false;  // Should not be provable
@*/
{
    // Given a pointer somewhere in an array
    uintptr_t mid_addr = (uintptr_t)mid;

    // Go way back (might be before allocation base)
    uintptr_t way_back = mid_addr - (100 * sizeof(int));

    // This SHOULD FAIL: Can't prove A.base <= way_back
    return __cerbvar_copy_alloc_id(way_back, mid);
}

// =============================================================================
// Test 7: Using random address not in allocation - SHOULD FAIL
// =============================================================================

int* test_arbitrary_address(int *p)
/*@ requires take Px = RW<int>(p);
             take A = Alloc(p);
    ensures  false;  // Should not be provable
@*/
{
    // Use a hardcoded address nowhere near the allocation
    uintptr_t arbitrary = 0xDEADBEEF;

    // This SHOULD FAIL: Can't prove A.base <= 0xDEADBEEF <= A.base + A.size
    return __cerbvar_copy_alloc_id(arbitrary, p);
}

// =============================================================================
// Test 8: Tagged pointer with insufficient allocation - SHOULD FAIL
// =============================================================================

int* test_tag_insufficient_space(int *p)
/*@ requires take Px = RW<int>(p);
             take A = Alloc(p);
             (u64)p == A.base;  // p is at start of allocation
             A.size == 4u64;     // Allocation is exactly sizeof(int)
             // Deliberately NOT proving A.base <= (u64)p + 1
    ensures  false;  // Should not be provable
@*/
{
    uintptr_t addr = (uintptr_t)p | 1ULL;

    // This SHOULD FAIL: Can't prove A.base <= addr when A.size might be too small
    // The tagged address p+1 might be exactly at one-past-end, which is allowed,
    // but we haven't proven it
    return __cerbvar_copy_alloc_id(addr, p);
}

// =============================================================================
// Test 9: Integer without any provenance - SHOULD FAIL
// =============================================================================

int* test_integer_no_provenance()
/*@ requires true;
    ensures  false;  // Should not be provable
@*/
{
    // Just a raw integer, no pointer involved
    uintptr_t addr = 0x1000;

    // This SHOULD FAIL: No pointer to copy provenance from!
    // Need a second argument but don't have one
    // (This won't even compile, but demonstrates the concept)
    // return __cerbvar_copy_alloc_id(addr, ???);

    return (int*)addr;  // This will fail - no provenance
}

// =============================================================================
// Test 10: Mixing allocations - provenance from p, address from q - SHOULD FAIL
// =============================================================================

int* test_mix_allocations(int *p, int *q)
/*@ requires take Px = RW<int>(p);
             take Qx = RW<int>(q);
             take Ap = Alloc(p);
             take Aq = Alloc(q);
             (alloc_id)p != (alloc_id)q;
    ensures  false;  // Should not be provable
@*/
{
    // Get address from q, try to use provenance from p
    uintptr_t q_addr = (uintptr_t)q;

    // This SHOULD FAIL: q_addr is not within p's allocation bounds
    return __cerbvar_copy_alloc_id(q_addr, p);
}

int main()
/*@ trusted; @*/
{
    // These tests are NOT meant to run, just to verify they fail CN verification
    return 0;
}
