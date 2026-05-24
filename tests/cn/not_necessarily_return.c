// Test: What happens when we use the result of a function
// with not_necessarily in its postcondition?
#include <stdint.h>

// Function that returns a value in [0, 100) but doesn't commit to specifics
int get_value(int x)
/*@ requires (i32)x >= 0i32;
             (i32)x < 100i32;
    ensures (i32)return >= 0i32;
            (i32)return < 100i32;
            not_necessarily((i32)return == 50i32);  // Don't assume any specific value
@*/
{
    return x;
}

// Test 1: Use the return value - what constraints do we have?
int use_return_value(int x)
/*@ requires (i32)x >= 0i32;
             (i32)x < 100i32;
    ensures (i32)return >= 0i32;
            (i32)return < 100i32;
@*/
{
    int y = get_value(x);

    // What can we prove about y?
    /*@ assert((i32)y >= 0i32); @*/          // Should pass - from ensures
    /*@ assert((i32)y < 100i32); @*/         // Should pass - from ensures
    /*@ assert(not_necessarily((i32)y == 50i32)); @*/  // What about this?

    return y;
}

// Test 2: Can we prove specific values about the return?
int test_specific_value(int x)
/*@ requires (i32)x >= 0i32;
             (i32)x < 100i32;
    ensures (i32)return >= 0i32;
@*/
{
    int y = get_value(x);

    // If not_necessarily "poisons" the context, we might not be able to prove y == 50
    // even when x == 50
    if (y == 50) {
        /*@ assert((i32)y == 50i32); @*/  // Can we prove this in the then-branch?
        return y;
    }
    return 0;
}

// Test 3: Does the not_necessarily constraint persist?
int test_constraint_persistence(int x)
/*@ requires (i32)x == 50i32;
    ensures (i32)return == 50i32;
@*/
{
    int y = get_value(x);

    // We know x == 50, and get_value returns x
    // So y == 50 should be provable despite the not_necessarily postcondition
    /*@ assert((i32)y == 50i32); @*/  // Can we prove this?

    return y;
}
