// Demonstrating error messages for logical function failures
//
// When a logical function with && fails, the error doesn't tell us
// which conjunct is the problem.

#include <stdint.h>

// Logical function with multiple conjuncts
/*@ function (boolean) all_properties(u64 x, u64 y, u64 z) {
      x > 10u64 &&      // Property A
      y < 100u64 &&     // Property B
      z == x + y &&     // Property C
      x % 2u64 == 0u64  // Property D
    }
@*/

// Function requiring the logical function
void requires_properties(int *p, uintptr_t x, uintptr_t y, uintptr_t z)
/*@ requires take P = RW<int>(p);
             all_properties(x, y, z);
    ensures  take P2 = RW<int>(p);
@*/
{
    // Empty body
}

// Caller that provides values that DON'T satisfy all properties
void caller(int *p)
/*@ requires take P = RW<int>(p);
    ensures  take P2 = RW<int>(p);
             P2 == P;
@*/
{
    // Call with x=5 (fails x > 10), y=50, z=55
    // The error will just say "Unprovable constraint"
    // without telling us that x > 10 is the failing conjunct
    requires_properties(p, 5, 50, 55);
}

int main()
/*@ trusted; @*/
{
    int x = 0;
    caller(&x);
    return 0;
}
