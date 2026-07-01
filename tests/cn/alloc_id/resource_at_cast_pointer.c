// Testing: Specifying resources directly for cast pointers

#include <stdint.h>

// Test 1: Take resource at the cast pointer directly
void use_cast_pointer_with_resource(uintptr_t addr)
/*@ requires take P = RW<int>((pointer)addr);
    ensures  take P2 = RW<int>((pointer)addr);
@*/
{
    int *p = (int *)addr;
    *p = 42;
}

// Test 2: Specify both address and resource
void use_with_address_constraint(int *witness, uintptr_t addr)
/*@ requires (u64)witness == addr;
             take P = RW<int>(witness);
    ensures  take P2 = RW<int>(witness);
@*/
{
    int *p = (int *)addr;
    *p = 42;
}

// Test 3: Resource at cast pointer with witness
void use_with_witness_and_cast_resource(int *witness, uintptr_t addr)
/*@ requires (u64)witness == addr;
             take P1 = RW<int>(witness);
             take P2 = RW<int>((pointer)addr);
    ensures  take Q1 = RW<int>(witness);
             take Q2 = RW<int>((pointer)addr);
@*/
{
    int *p = (int *)addr;
    *p = 42;
}

int main()
/*@ trusted; @*/
{
    int x = 0;
    uintptr_t addr = (uintptr_t)&x;

    use_cast_pointer_with_resource(addr);
    use_with_address_constraint(&x, addr);
    use_with_witness_and_cast_resource(&x, addr);

    return 0;
}
