// Investigation: Does (pointer) cast preserve provenance?

#include <stdint.h>

// Test 1: Check if (pointer) cast preserves provenance
void test_cast_preserves_provenance(int *p)
/*@ requires take P = RW<int>(p);
    ensures  take P2 = RW<int>(p);
             P2 == P;
@*/
{
    uintptr_t addr = (uintptr_t)p;
    int *q = (int *)addr;

    // Check provenance
    /*@ assert(has_alloc_id(p)); @*/
    /*@ assert(has_alloc_id(q)); @*/  // Does q have provenance?

    // Check if same allocation ID
    /*@ assert((alloc_id)p == (alloc_id)q); @*/  // Same allocation?

    // Check address
    /*@ assert((u64)p == (u64)q); @*/
}

// Test 2: Can we write through the cast pointer?
void test_write_through_cast(int *p)
/*@ requires take P = RW<int>(p);
    ensures  take P2 = RW<int>(p);
@*/
{
    uintptr_t addr = (uintptr_t)p;
    int *q = (int *)addr;

    // Try to write - does this work?
    *q = 42;
}

// Test 3: Multiple round-trips
void test_multiple_roundtrips(int *p)
/*@ requires take P = RW<int>(p);
    ensures  take P2 = RW<int>(p);
             P2 == P;
@*/
{
    // Round trip 1
    uintptr_t addr1 = (uintptr_t)p;
    int *q1 = (int *)addr1;

    // Round trip 2
    uintptr_t addr2 = (uintptr_t)q1;
    int *q2 = (int *)addr2;

    // Round trip 3
    uintptr_t addr3 = (uintptr_t)q2;
    int *q3 = (int *)addr3;

    // All should have same provenance
    /*@ assert((alloc_id)p == (alloc_id)q1); @*/
    /*@ assert((alloc_id)p == (alloc_id)q2); @*/
    /*@ assert((alloc_id)p == (alloc_id)q3); @*/

    /*@ assert((u64)p == (u64)q3); @*/
}

// Test 4: Arithmetic on uintptr_t
void test_arithmetic_on_uintptr(int arr[10])
/*@ requires take A = each(i64 i; 0i64 <= i && i < 10i64) {
                 RW<int>(array_shift<int>(arr, i))
             };
    ensures  take A2 = each(i64 i; 0i64 <= i && i < 10i64) {
                 RW<int>(array_shift<int>(arr, i))
             };
             A2 == A;
@*/
{
    // Convert to uintptr_t
    uintptr_t base = (uintptr_t)arr;

    // Add offset
    uintptr_t offset_addr = base + (5 * sizeof(int));

    // Cast back to pointer
    int *p = (int *)offset_addr;

    // Does p have provenance pointing to arr[5]?
    /*@ assert(has_alloc_id(p)); @*/
    /*@ assert((alloc_id)p == (alloc_id)arr); @*/  // Same allocation as arr?

    // What about the address?
    /*@ assert((u64)p == (u64)array_shift<int>(arr, 5i64)); @*/
}

int main()
/*@ trusted; @*/
{
    int x = 0;
    test_cast_preserves_provenance(&x);
    test_write_through_cast(&x);
    test_multiple_roundtrips(&x);

    int arr[10];
    test_arithmetic_on_uintptr(arr);

    return 0;
}
