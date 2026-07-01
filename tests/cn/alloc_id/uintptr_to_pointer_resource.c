// Testing: What happens when you cast uintptr_t to pointer in resources?
//
// Key question: Does RW<int>((pointer)some_uintptr) work?
// Answer: It depends on whether the pointer has provenance!

#include <stdint.h>

// Declare the builtin first
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

// Test 1: Try to use a pointer cast from uintptr_t directly
void test_cast_no_provenance(int *p)
/*@ requires take P = RW<int>(p);
    ensures  take P2 = RW<int>(p);
@*/
{
    uintptr_t addr = (uintptr_t)p;

    // Try to access via the cast pointer
    // This should FAIL - (pointer)addr has no provenance
    int *q = (int *)addr;

    /*@ assert((u64)q == (u64)p); @*/  // Addresses are equal
    // But q has no allocation ID!

    *q = 42;  // Will this work?
}

// Test 2: Check if a casted pointer has_alloc_id
void test_has_alloc_id_after_cast(int *p)
/*@ requires take P = RW<int>(p);
    ensures  take P2 = RW<int>(p);
             P2 == P;
@*/
{
    uintptr_t addr = (uintptr_t)p;
    int *q = (int *)addr;

    /*@ assert(has_alloc_id(p)); @*/   // p has provenance
    /*@ assert(!has_alloc_id(q)); @*/  // q does NOT have provenance
}

// Test 3: Use copy_alloc_id to restore provenance
void test_copy_alloc_id_for_resource(int *p)
/*@ requires take P = RW<int>(p);
    ensures  take P2 = RW<int>(p);
@*/
{
    uintptr_t addr = (uintptr_t)p;

    // Restore provenance using __cerbvar_copy_alloc_id
    int *q = __cerbvar_copy_alloc_id(addr, p);

    /*@ assert(has_alloc_id(q)); @*/          // Now q has provenance
    /*@ assert((alloc_id)q == (alloc_id)p); @*/  // Same allocation ID
    /*@ assert((u64)q == (u64)p); @*/         // Same address

    // This should work - q has provenance
    *q = 42;
}

// Test 4: What about accessing via a casted address?
void test_access_cast_address(int *p)
/*@ requires take P = RW<int>(p);
    ensures  take P2 = RW<int>(p);
@*/
{
    uintptr_t addr = (uintptr_t)p;
    int *q = (int *)addr;

    // Try to access through q - does this work?
    // q has no provenance, so this should fail
    *q = 42;
}

// Test 5: With copy_alloc_id, can we access?
void test_access_with_provenance_restored(int *p)
/*@ requires take P = RW<int>(p);
    ensures  take P2 = RW<int>(p);
@*/
{
    uintptr_t addr = (uintptr_t)p;
    int *q = __cerbvar_copy_alloc_id(addr, p);

    // Now q has the same provenance as p
    // This should work!
    *q = 42;
}

int main()
/*@ trusted; @*/
{
    int x = 0;
    test_cast_no_provenance(&x);
    test_has_alloc_id_after_cast(&x);
    test_copy_alloc_id_for_resource(&x);
    test_access_cast_address(&x);
    test_access_with_provenance_restored(&x);
    return 0;
}
