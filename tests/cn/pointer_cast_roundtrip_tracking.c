// Test: Does CN track provenance through pointer->int->pointer round trips?
//
// Question: If addr = (uintptr_t)p, does CN know (pointer)addr has p's alloc_id?

#include <stdint.h>

// Test 1: Can CN prove alloc_id equality after round trip?
void test1_alloc_id_equality(int *p)
/*@ requires take P = RW<int>(p);
    ensures  take Q = RW<int>(p);
@*/
{
    uintptr_t addr = (uintptr_t)p;

    // Can CN prove these have same alloc_id?
    /*@ assert((alloc_id)p == (alloc_id)((pointer)addr)); @*/
}

// Test 2: Can we use the resource through the round-tripped pointer?
void test2_use_resource_after_roundtrip(int *p)
/*@ requires take P = RW<int>(p);
    ensures  take Q = RW<int>(p);
@*/
{
    uintptr_t addr = (uintptr_t)p;
    int *q = (int *)addr;

    // Does CN know q can use p's resource?
    *q = 42;
}

// Test 3: What if we explicitly state addr came from p?
void test3_explicit_cast_relationship(int *p)
/*@ requires take P = RW<int>(p);
    ensures  take Q = RW<int>(p);
@*/
{
    uintptr_t addr = (uintptr_t)p;

    /*@ assert((u64)p == addr); @*/  // Address equality should hold

    int *q = (int *)addr;

    // Now can we use it?
    *q = 42;
}

// Test 4: Can we assert properties that would make it work?
void test4_assert_provenance_preserved(int *p)
/*@ requires take P = RW<int>(p);
    ensures  take Q = RW<int>(p);
@*/
{
    uintptr_t addr = (uintptr_t)p;

    /*@ assert((u64)p == addr); @*/
    /*@ assert((alloc_id)((pointer)addr) == (alloc_id)p); @*/

    int *q = (int *)addr;
    *q = 42;
}

// Test 5: What if we use ptr_eq?
void test5_ptr_eq_after_roundtrip(int *p)
/*@ requires take P = RW<int>(p);
    ensures  take Q = RW<int>(p);
@*/
{
    uintptr_t addr = (uintptr_t)p;
    int *q = (int *)addr;

    /*@ assert(ptr_eq(p, q)); @*/  // Full pointer equality?
}

// Test 6: Does the cast lose information?
void test6_inspect_cast_result(int *p)
/*@ requires take P = RW<int>(p); @*/
{
    /*@ assert(has_alloc_id(p)); @*/

    uintptr_t addr = (uintptr_t)p;
    int *q = (int *)addr;

    /*@ assert(has_alloc_id(q)); @*/  // Does q have any alloc_id?
}

// Test 7: What if we constrain the cast result's alloc_id?
void test7_constrain_cast_alloc_id(int *p)
/*@ requires take P = RW<int>(p);
    ensures  take Q = RW<int>(p);
@*/
{
    uintptr_t addr = (uintptr_t)p;

    // Manually constrain the cast to have p's alloc_id
    /*@ assert((u64)((pointer)addr) == addr); @*/
    /*@ assert(has_alloc_id((pointer)addr) == has_alloc_id(p)); @*/
    /*@ assert((alloc_id)((pointer)addr) == (alloc_id)p); @*/

    int *q = (int *)addr;
    *q = 42;
}
