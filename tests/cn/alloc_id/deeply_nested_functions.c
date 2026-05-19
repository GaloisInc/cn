// Testing deeply nested logical functions
// Shows that recursive expansion fully expands nested function calls

#include <stdint.h>

// Level 1: Basic properties
/*@ function (boolean) in_range(u64 x, u64 min, u64 max) {
      x >= min && x <= max
    }
@*/

/*@ function (boolean) is_even(u64 x) {
      x % 2u64 == 0u64
    }
@*/

// Level 2: Composite properties
/*@ function (boolean) valid_byte(u64 x) {
      in_range(x, 0u64, 255u64)
    }
@*/

/*@ function (boolean) even_byte(u64 x) {
      valid_byte(x) && is_even(x)
    }
@*/

// Level 3: Complex property combining multiple levels
/*@ function (boolean) two_even_bytes(u64 a, u64 b) {
      even_byte(a) && even_byte(b)
    }
@*/

void requires_two_even_bytes(int *p, uintptr_t a, uintptr_t b)
/*@ requires take P = RW<int>(p);
             two_even_bytes(a, b);
    ensures  take P2 = RW<int>(p);
@*/
{
    // Empty
}

// Test with values that fail at different nesting levels
void test_deep_nesting(int *p)
/*@ requires take P = RW<int>(p);
    ensures  take P2 = RW<int>(p);
             P2 == P;
@*/
{
    // a=300 fails in_range (too large for byte)
    // b=7 fails is_even (odd number)
    requires_two_even_bytes(p, 300, 7);
}

int main()
/*@ trusted; @*/
{
    int x = 0;
    test_deep_nesting(&x);
    return 0;
}
