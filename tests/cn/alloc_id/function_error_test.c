// Test case: Demonstrating poor error messages for logical function failures
//
// This file creates a function with multiple conjuncts and shows that
// when it fails, CN doesn't tell us which conjunct failed.

#include <stdint.h>
#include <stddef.h>

// A logical function with multiple properties
/*@ function (boolean) valid_bounds(u64 base, u64 ptr, u64 size) {
      base <= ptr &&           // Property 1
      ptr < base + size &&     // Property 2
      size > 0u64 &&           // Property 3
      size < 1000u64           // Property 4
    }
@*/

// Test function that will fail
void test_function(char *p, uintptr_t base, size_t size)
/*@ requires take P = RW<char>(p);
             valid_bounds(base, (u64)p, size);
    ensures  take P2 = RW<char>(p);
@*/
{
    // Do nothing so the issue is just with the precondition
}

int main()
/*@ trusted; @*/
{
    char x = 0;
    // This call will fail because base > (u64)&x
    // But the error won't tell us which conjunct of valid_bounds failed
    test_function(&x, 0x1000000, 10);
    return 0;
}
