// Test the not_necessarily builtin predicate
#include <stdint.h>

int test_basic(int x)
/*@ requires (i32)x >= 0i32;
             (i32)x < 100i32;
    ensures (i32)return >= 0i32;
@*/
{
    // These should PASS: x==5 is possible but not entailed
    /*@ assert(not_necessarily((i32)x == 5i32)); @*/

    return x;
}

int test_postcondition(int x)
/*@ requires (i32)x >= 0i32;
             (i32)x < 100i32;
    ensures (i32)return >= 0i32;
            (i32)return < 100i32;
            not_necessarily((i32)return == 5i32);
@*/
{
    return x;
}

int test_order_dependency()
/*@ ensures (i32)return >= 0i32;
            (i32)return < 10i32;
            not_necessarily((i32)return == 5i32);
@*/
{
    return 5;
}
