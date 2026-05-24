// Test not_necessarily in requires and ensures clauses
#include <stdint.h>

// Test in postcondition - should PASS
int test_ensures(int x)
/*@ requires (i32)x >= 10i32;
             (i32)x <= 20i32;
    ensures (i32)return >= 10i32;
            (i32)return <= 20i32;
            not_necessarily((i32)return == 15i32);
@*/
{
    return x;
}

// Test in precondition - should PASS
int test_requires(int x)
/*@ requires (i32)x >= 10i32;
             (i32)x <= 20i32;
             not_necessarily((i32)x == 15i32);
    ensures (i32)return >= 10i32;
@*/
{
    return x;
}

// Test range in ensures without specific value - should PASS
int test_range_ensures(int x)
/*@ requires (i32)x >= 0i32;
             (i32)x < 10i32;
    ensures (i32)return >= 0i32;
            (i32)return < 10i32;
            not_necessarily((i32)return == 5i32);
@*/
{
    // Return value is in range but specific value (5) is not provable
    return x;
}
