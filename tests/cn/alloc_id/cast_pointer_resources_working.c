// Working examples: Using cast pointers with resources

#include <stdint.h>

// Pattern 1: Take resource at (pointer)addr with witness
void pattern1_with_witness(int *witness, uintptr_t addr)
/*@ requires (u64)witness == addr;
             take P = RW<int>((pointer)addr);
    ensures  take P2 = RW<int>((pointer)addr);
@*/
{
    int *p = (int *)addr;
    *p = 42;  // Works!
}

// Pattern 2: Do we need the witness to have a resource too?
void pattern2_witness_without_resource(int *witness, uintptr_t addr)
/*@ requires (u64)witness == addr;
             has_alloc_id(witness);
             take P = RW<int>((pointer)addr);
    ensures  take P2 = RW<int>((pointer)addr);
@*/
{
    int *p = (int *)addr;
    *p = 42;
}

// Pattern 3: What if witness and cast pointer both have resources?
void pattern3_dual_resources(int *witness, uintptr_t addr)
/*@ requires (u64)witness == addr;
             take P1 = RW<int>(witness);
             take P2 = RW<int>((pointer)addr);
    ensures  take Q1 = RW<int>(witness);
             take Q2 = RW<int>((pointer)addr);
@*/
{
    int *p = (int *)addr;
    int *q = witness;

    // Can we write through both?
    *p = 42;
    *q = 43;
}

// Pattern 4: Array element via address
void pattern4_array_element(int arr[10], uintptr_t elem5_addr)
/*@ requires (u64)array_shift<int>(arr, 5u64) == elem5_addr;
             take A = each(u64 i; i < 10u64) {
                 RW<int>(array_shift<int>(arr, i))
             };
             take P = RW<int>((pointer)elem5_addr);
    ensures  take A2 = each(u64 i; i < 10u64) {
                 RW<int>(array_shift<int>(arr, i))
             };
             take P2 = RW<int>((pointer)elem5_addr);
@*/
{
    int *p = (int *)elem5_addr;
    *p = 42;
}

// Pattern 5: Just the resource at cast pointer, no witness
void pattern5_just_cast_resource(uintptr_t addr)
/*@ requires take P = RW<int>((pointer)addr);
    ensures  take P2 = RW<int>((pointer)addr);
@*/
{
    int *p = (int *)addr;
    *p = 42;
}

// Pattern 6: Alloc resource with cast pointer
void pattern6_with_alloc(uintptr_t addr)
/*@ requires take P = RW<int>((pointer)addr);
             take A = Alloc((pointer)addr);
    ensures  take P2 = RW<int>((pointer)addr);
             take A2 = Alloc((pointer)addr);
             A2 == A;
@*/
{
    int *p = (int *)addr;

    // Check provenance properties
    /*@ assert(has_alloc_id(p)); @*/

    *p = 42;
}

int main()
/*@ trusted; @*/
{
    int x = 0;
    uintptr_t addr_x = (uintptr_t)&x;

    pattern1_with_witness(&x, addr_x);
    pattern2_witness_without_resource(&x, addr_x);
    pattern3_dual_resources(&x, addr_x);

    int arr[10] = {0};
    uintptr_t elem5 = (uintptr_t)&arr[5];
    pattern4_array_element(arr, elem5);

    pattern5_just_cast_resource(addr_x);
    pattern6_with_alloc(addr_x);

    return 0;
}
