// Test that not_necessarily correctly FAILS when constraint is provable
#include <stdint.h>

int test_provable_constraint(int x)
/*@ requires (i32)x >= 10i32;
             (i32)x <= 20i32;
    ensures (i32)return >= 10i32;
@*/
{
    // x >= 10 IS provable from precondition: this should FAIL
    /*@ assert(not_necessarily((i32)x >= 10i32)); @*/

    return x;
}
