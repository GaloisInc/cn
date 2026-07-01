// Test: Understanding when RW<int>((pointer)uintptr) succeeds
//
// Question: Does CN match RW<int>(p) with RW<int>((pointer)addr)?
//
// Answer: NO - casting uintptr_t to pointer creates a pointer with a
// fresh/unknown allocation ID that doesn't match any existing allocations.
//
// In the SMT encoding:
//   (pointer)addr = bits_to_ptr(addr, default_alloc_id)
//
// Where default_alloc_id is a fresh unconstrained value that won't equal
// the alloc_id of any actual allocation.
//
// Resource matching requires:
//   addr(requested) == addr(available) AND
//   alloc_id(requested) == alloc_id(available)
//
// The alloc_id check fails for cast pointers.

#include <stdint.h>

// Test 1: Can we take a resource at (pointer)addr?
void test1_take_at_cast(uintptr_t addr)
/*@ requires take P = RW<int>((pointer)addr);
    ensures  take Q = RW<int>((pointer)addr);
@*/
{
    int *p = (int *)addr;
    *p = 42;
}

// Test 2: If we have RW<int>(witness), can we access via (int*)addr?
void test2_access_via_cast(int *witness, uintptr_t addr)
/*@ requires (u64)witness == addr;
             take P = RW<int>(witness);
    ensures  take Q = RW<int>(witness);
@*/
{
    int *p = (int *)addr;
    *p = 42;  // Does this consume RW<int>(witness)?
}

// Test 3: What if we explicitly say both are the same?
void test3_explicit_equivalence(int *witness, uintptr_t addr)
/*@ requires (u64)witness == addr;
             ptr_eq(witness, (pointer)addr);
             take P = RW<int>(witness);
    ensures  take Q = RW<int>(witness);
@*/
{
    int *p = (int *)addr;
    *p = 42;
}

// Test 4: What about alloc_id equality?
void test4_alloc_id_equality(int *witness, uintptr_t addr)
/*@ requires (u64)witness == addr;
             (alloc_id)witness == (alloc_id)((pointer)addr);
             take P = RW<int>(witness);
    ensures  take Q = RW<int>(witness);
@*/
{
    int *p = (int *)addr;
    *p = 42;
}

// Test 5: Let's check what (pointer)addr actually has
void test5_inspect_cast()
{
    uintptr_t addr = 0x1000;
    /*@ assert(!has_alloc_id((pointer)addr)); @*/
}

// Test 6: After casting from a real pointer
void test6_cast_round_trip(int *p)
/*@ requires take P = RW<int>(p);
    ensures  take Q = RW<int>(p);
@*/
{
    uintptr_t addr = (uintptr_t)p;
    int *q = (int *)addr;

    // Does q have alloc_id?
    /*@ assert(has_alloc_id(p)); @*/
    /*@ assert(has_alloc_id(q)); @*/  // Or not?
}
