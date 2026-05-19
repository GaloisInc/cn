// Demonstrating improved error messages for multiple failing conjuncts
//
// This test shows that when a logical function with multiple && fails,
// CN now reports which specific conjuncts are false.

#include <stdint.h>

// Logical function with properties about a triangle
/*@ function (boolean) valid_triangle(u64 a, u64 b, u64 c) {
      a > 0u64 &&           // Side a must be positive
      b > 0u64 &&           // Side b must be positive
      c > 0u64 &&           // Side c must be positive
      a + b > c &&          // Triangle inequality 1
      a + c > b &&          // Triangle inequality 2
      b + c > a             // Triangle inequality 3
    }
@*/

void check_triangle(int *p, uintptr_t a, uintptr_t b, uintptr_t c)
/*@ requires take P = RW<int>(p);
             valid_triangle(a, b, c);
    ensures  take P2 = RW<int>(p);
@*/
{
    // Empty body
}

// Test case 1: Zero side length (fails first 3 conjuncts)
void test_zero_side(int *p)
/*@ requires take P = RW<int>(p);
    ensures  take P2 = RW<int>(p);
             P2 == P;
@*/
{
    check_triangle(p, 0, 0, 0);  // All sides zero
}

// Test case 2: Violates triangle inequality
void test_bad_triangle(int *p)
/*@ requires take P = RW<int>(p);
    ensures  take P2 = RW<int>(p);
             P2 == P;
@*/
{
    check_triangle(p, 1, 2, 10);  // 1 + 2 not > 10
}

int main()
/*@ trusted; @*/
{
    int x = 0;
    test_zero_side(&x);
    test_bad_triangle(&x);
    return 0;
}
