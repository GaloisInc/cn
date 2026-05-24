// Simple test of not_necessarily in assertions only
#include <stdint.h>

int test_assertion_basic(int x)
/*@ requires (i32)x >= 0i32;
             (i32)x < 100i32;
    ensures (i32)return >= 0i32;
@*/
{
    // x==5 is satisfiable but not entailed: should PASS
    /*@ assert(not_necessarily((i32)x == 5i32)); @*/

    return x;
}

int test_assertion_range(int x)
/*@ requires (i32)x >= 10i32;
             (i32)x <= 20i32;
    ensures (i32)return >= 10i32;
@*/
{
    // x==15 is satisfiable but not entailed: should PASS
    /*@ assert(not_necessarily((i32)x == 15i32)); @*/

    // x >= 10 IS entailed: should FAIL
    // /*@ assert(not_necessarily((i32)x >= 10i32)); @*/

    return x;
}
