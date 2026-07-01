// Testing: Specifying provenance via has_alloc_id and addr_eq

#include <stdint.h>

// Test 1: Specify that a pointer exists at an address
void use_pointer_at_address(uintptr_t addr, int *witness)
/*@ requires take P = RW<int>(witness);
             (u64)witness == addr;
             has_alloc_id(witness);
    ensures  take P2 = RW<int>(witness);
@*/
{
    // Cast the address to a pointer
    int *p = (int *)addr;

    // Even though p came from a cast, we can use it because:
    // - We specified a witness pointer exists at this address
    // - The witness has provenance
    // - CN can use the witness's provenance

    *p = 42;
}

// Test 2: Using addr_eq with two pointers
void use_pointer_with_addr_eq(int *p, int *q)
/*@ requires take P = RW<int>(p);
             addr_eq(p, q);
             has_alloc_id(q);
    ensures  take P2 = RW<int>(p);
@*/
{
    // p and q have the same address
    // Both have provenance
    *q = 42;
}

// Test 3: Multiple pointers at same address
void two_pointers_same_address(int *p, int *q)
/*@ requires take P = RW<int>(p);
             addr_eq(p, q);
             has_alloc_id(q);
    ensures  take P2 = RW<int>(p);
@*/
{
    // p and q point to the same address
    // Both have provenance

    uintptr_t addr = (uintptr_t)p;
    int *r = (int *)addr;

    // Can we use r? We have witnesses at that address
    *r = 42;
}

// Test 4: Specify provenance for array element
void use_array_element_by_address(int arr[10], uintptr_t elem_addr)
/*@ requires take A = each(u64 i; i < 10u64) {
                 RW<int>(array_shift<int>(arr, i))
             };
             // Specify that elem_addr is the address of arr[5]
             elem_addr == (u64)array_shift<int>(arr, 5u64);
    ensures  take A2 = each(u64 i; i < 10u64) {
                 RW<int>(array_shift<int>(arr, i))
             };
@*/
{
    int *p = (int *)elem_addr;

    // We specified that elem_addr is arr[5]'s address
    // So p should be usable
    *p = 42;
}

// Test 5: Existential - there exists some pointer at this address
void use_pointer_existential(uintptr_t addr)
/*@ requires take P = RW<int>((pointer)addr);
    ensures  take P2 = RW<int>((pointer)addr);
@*/
{
    int *p = (int *)addr;
    *p = 42;
}

// Test 6: Reconstruct from parts
void reconstruct_pointer(uintptr_t addr, int *prov_source)
/*@ requires (u64)prov_source == addr;
             has_alloc_id(prov_source);
             take P = RW<int>(prov_source);
    ensures  take P2 = RW<int>(prov_source);
@*/
{
    int *p = (int *)addr;

    // We know:
    // - prov_source is at address addr
    // - prov_source has provenance
    // - We have RW at prov_source
    // Can we write through p?

    *p = 42;
}

int main()
/*@ trusted; @*/
{
    int x = 0;
    uintptr_t addr_x = (uintptr_t)&x;

    use_pointer_at_address(addr_x, &x);
    use_pointer_with_addr_eq(&x, &x);
    two_pointers_same_address(&x, &x);

    int arr[10] = {0};
    uintptr_t elem5_addr = (uintptr_t)&arr[5];
    use_array_element_by_address(arr, elem5_addr);

    use_pointer_existential(addr_x);
    reconstruct_pointer(addr_x, &x);

    return 0;
}
