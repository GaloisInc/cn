// Test calling a function with not_necessarily in requires
#include <stdint.h>

// Callee has not_necessarily in requires
int callee(int x)
/*@ requires (i32)x >= 10i32;
             (i32)x <= 20i32;
             not_necessarily((i32)x == 15i32);  // x could be anything in [10,20]
    ensures (i32)return >= 10i32;
@*/
{
    return x;
}

// Caller 1: Should PASS - x is in range but specific value not known
int caller_pass(int x)
/*@ requires (i32)x >= 10i32;
             (i32)x <= 20i32;
    ensures (i32)return >= 10i32;
@*/
{
    // At call site, we need to prove not_necessarily(x == 15)
    // Since x is in [10,20] but not specifically 15, this should pass
    return callee(x);
}

// Caller 2: Should FAIL - x is exactly 15
int caller_fail(int x)
/*@ requires (i32)x == 15i32;
    ensures (i32)return >= 10i32;
@*/
{
    // At call site, we need to prove not_necessarily(x == 15)
    // But x == 15 IS provable from the precondition, so this should FAIL
    return callee(x);
}

// Caller 3: Should FAIL - x is necessarily NOT 15
int caller_fail_negation(int x)
/*@ requires (i32)x >= 10i32;
             (i32)x < 15i32;
    ensures (i32)return >= 10i32;
@*/
{
    // At call site, we need to prove not_necessarily(x == 15)
    // But ¬(x == 15) IS provable from x < 15, so this should also FAIL
    return callee(x);
}
