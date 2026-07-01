// Test: Are casts in spec vs code treated as the same value?

#include <stdint.h>

// Test: If we explicitly say they're equal, does it work?
void test_explicit_equality(uintptr_t addr)
/*@ requires take P = RW<int>((pointer)addr);
    ensures  take Q = RW<int>((pointer)addr);
@*/
{
    int *p = (int *)addr;

    // Try to constrain them to be equal
    /*@ assert((u64)p == addr); @*/  // Addresses are equal
    /*@ assert((u64)p == (u64)((pointer)addr)); @*/  // Both have addr as address

    // But are the pointers themselves equal?
    /*@ assert(ptr_eq(p, (pointer)addr)); @*/

    *p = 42;
}

// Test: What if we explicitly bind the spec cast to a name?
void test_named_spec_cast(uintptr_t addr)
/*@ requires take P = RW<int>((pointer)addr);
             let spec_ptr = (pointer)addr;
    ensures  take Q = RW<int>((pointer)addr);
@*/
{
    int *p = (int *)addr;

    /*@ assert(ptr_eq(p, spec_ptr)); @*/

    *p = 42;
}

// Test: Can we prove anything about their relationship?
void test_relationship(uintptr_t addr)
/*@ requires take P = RW<int>((pointer)addr); @*/
{
    int *p = (int *)addr;

    // These should all hold:
    /*@ assert((u64)p == addr); @*/
    /*@ assert((u64)((pointer)addr) == addr); @*/

    // But this fails:
    /*@ assert(ptr_eq(p, (pointer)addr)); @*/
}
