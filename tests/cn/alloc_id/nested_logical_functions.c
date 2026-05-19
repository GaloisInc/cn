// Testing nested logical functions - what happens when a failing conjunct
// is itself another logical function?

#include <stdint.h>

// Simple property: value must be positive
/*@ function (boolean) positive(u64 x) {
      x > 0u64
    }
@*/

// Composite property: both values must be positive
/*@ function (boolean) both_positive(u64 x, u64 y) {
      positive(x) && positive(y)
    }
@*/

// Three-level nesting
/*@ function (boolean) all_positive(u64 x, u64 y, u64 z) {
      both_positive(x, y) && positive(z)
    }
@*/

void requires_both_positive(int *p, uintptr_t x, uintptr_t y)
/*@ requires take P = RW<int>(p);
             both_positive(x, y);
    ensures  take P2 = RW<int>(p);
@*/
{
    // Empty
}

void requires_all_positive(int *p, uintptr_t x, uintptr_t y, uintptr_t z)
/*@ requires take P = RW<int>(p);
             all_positive(x, y, z);
    ensures  take P2 = RW<int>(p);
@*/
{
    // Empty
}

// Test 1: Call with one negative value (two-level nesting)
void test_nested_two_levels(int *p)
/*@ requires take P = RW<int>(p);
    ensures  take P2 = RW<int>(p);
             P2 == P;
@*/
{
    requires_both_positive(p, 0, 5);  // x=0 fails positive(x)
}

// Test 2: Call with multiple failures (three-level nesting)
void test_nested_three_levels(int *p)
/*@ requires take P = RW<int>(p);
    ensures  take P2 = RW<int>(p);
             P2 == P;
@*/
{
    requires_all_positive(p, 0, 5, 0);  // x=0 and z=0 both fail
}

int main()
/*@ trusted; @*/
{
    int x = 0;
    test_nested_two_levels(&x);
    test_nested_three_levels(&x);
    return 0;
}
