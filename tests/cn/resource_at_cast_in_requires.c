// Test: Does RW<int>((pointer)addr) in requires actually work?

#include <stdint.h>

// Test 1: Simplest case - resource directly at cast pointer
void test1_direct_cast_resource(uintptr_t addr)
/*@ requires take P = RW<int>((pointer)addr);
    ensures  take Q = RW<int>((pointer)addr);
@*/
{
    int *p = (int *)addr;
    *p = 42;  // Can we use the resource?
}

// Test 2: Read and write through cast
void test2_read_write_cast(uintptr_t addr)
/*@ requires take P = RW<int>((pointer)addr);
    ensures  take Q = RW<int>((pointer)addr);
             P == Q;
@*/
{
    int *p = (int *)addr;
    int x = *p;
    *p = x + 1;
}

// Test 3: Multiple accesses
void test3_multiple_accesses(uintptr_t addr)
/*@ requires take P = RW<int>((pointer)addr);
    ensures  take Q = RW<int>((pointer)addr);
@*/
{
    int *p = (int *)addr;
    *p = 1;
    *p = 2;
    *p = 3;
}

// Test 4: Access via different local variables
void test4_different_locals(uintptr_t addr)
/*@ requires take P = RW<int>((pointer)addr);
    ensures  take Q = RW<int>((pointer)addr);
@*/
{
    int *p = (int *)addr;
    int *q = (int *)addr;  // Another cast from same addr

    *p = 42;
    *q = 43;  // Can both use the same resource?
}

// Test 5: What about has_alloc_id?
void test5_alloc_id_check(uintptr_t addr)
/*@ requires take P = RW<int>((pointer)addr);
    ensures  take Q = RW<int>((pointer)addr);
@*/
{
    /*@ assert(has_alloc_id((pointer)addr)); @*/

    int *p = (int *)addr;

    /*@ assert(has_alloc_id(p)); @*/
}

// Test 6: alloc_id equality between cast in spec vs cast in code
void test6_alloc_id_equality(uintptr_t addr)
/*@ requires take P = RW<int>((pointer)addr);
    ensures  take Q = RW<int>((pointer)addr);
@*/
{
    int *p = (int *)addr;

    /*@ assert((alloc_id)p == (alloc_id)((pointer)addr)); @*/
}

// Test 7: ptr_eq between spec cast and code cast
void test7_ptr_eq(uintptr_t addr)
/*@ requires take P = RW<int>((pointer)addr);
    ensures  take Q = RW<int>((pointer)addr);
@*/
{
    int *p = (int *)addr;

    /*@ assert(ptr_eq(p, (pointer)addr)); @*/
}

// Test 8: Can we pass it to another function?
void helper(int *p)
/*@ requires take H = RW<int>(p);
    ensures  take H2 = RW<int>(p);
@*/
{
    *p = 99;
}

void test8_call_helper(uintptr_t addr)
/*@ requires take P = RW<int>((pointer)addr);
    ensures  take Q = RW<int>((pointer)addr);
@*/
{
    int *p = (int *)addr;
    helper(p);  // Can we pass the resource along?
}

// Test 9: What if we cast to different type?
void test9_cast_to_char(uintptr_t addr)
/*@ requires take P = RW<int>((pointer)addr);
    ensures  take Q = RW<int>((pointer)addr);
@*/
{
    char *p = (char *)addr;
    *p = 'x';  // This needs RW<char>, not RW<int>
}
