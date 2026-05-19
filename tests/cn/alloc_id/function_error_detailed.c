// Test case: Demonstrating where CN error messages could be improved
//
// When a logical function with multiple conjuncts fails, CN doesn't tell us
// which specific conjunct caused the failure.

#include <stdint.h>
#include <stddef.h>

// A logical function combining multiple properties
/*@ function (boolean) valid_range(u64 base, u64 size, u64 ptr) {
      base <= ptr &&                    // Property 1: ptr not below base
      ptr < base + size &&              // Property 2: ptr not above end
      size > 0u64 &&                    // Property 3: non-zero size
      size < 100000u64 &&               // Property 4: reasonable size
      base % 8u64 == 0u64               // Property 5: base is aligned
    }
@*/

// Function that requires the valid_range property
int* get_element(int *arr, uintptr_t base, size_t size, size_t index)
/*@ requires take A = each(u64 i; i < size) {
                 RW<int>(array_shift<int>(arr, i))
             };
             valid_range(base, size, (u64)arr + (index * 4u64));
    ensures  take A2 = each(u64 i; i < size) {
                 RW<int>(array_shift<int>(arr, i))
             };
             A2 == A;
             return == array_shift<int>(arr, index);
@*/
{
    return &arr[index];
}

int main()
/*@ trusted; @*/
{
    int arr[10];
    // This should fail because we don't know if the conjuncts hold
    // But the error won't tell us which one
    int *elem = get_element(arr, 0x1001, 10, 5);  // base not aligned!
    return 0;
}
