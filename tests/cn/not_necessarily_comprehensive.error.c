// Comprehensive error test: cases where not_necessarily should fail
#include <stdint.h>

// ERROR 1: Constraint IS provable (necessarily true)
int test_provable_true(int x)
/*@ requires (i32)x >= 10i32;
             (i32)x <= 20i32;
    ensures (i32)return >= 10i32;
@*/
{
    // FAIL: x >= 10 IS provable from precondition
    /*@ assert(not_necessarily((i32)x >= 10i32)); @*/
    return x;
}

// ERROR 2: Constraint negation IS provable (necessarily false)
int test_provable_false(int x)
/*@ requires (i32)x >= 10i32;
             (i32)x <= 20i32;
    ensures (i32)return >= 10i32;
@*/
{
    // FAIL: x < 5 is necessarily false (¬(x < 5) is provable)
    /*@ assert(not_necessarily((i32)x < 5i32)); @*/
    return x;
}

// ERROR 3: Exact value is provable
int test_exact_value()
/*@ ensures (i32)return == 42i32;
@*/
{
    int x = 42;

    // FAIL: x == 42 IS provable
    /*@ assert(not_necessarily((i32)x == 42i32)); @*/

    return x;
}
