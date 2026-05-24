// Debug: What exactly is in the context after calling a function
// with not_necessarily in postcondition?
#include <stdint.h>

int get_value(int x)
/*@ requires (i32)x >= 0i32;
             (i32)x < 100i32;
    ensures (i32)return >= 0i32;
            (i32)return < 100i32;
            not_necessarily((i32)return == 50i32);
@*/
{
    return x;
}

// Simple test: can we prove anything about the return value?
int test_simple()
/*@ ensures (i32)return >= 0i32;
@*/
{
    int y = get_value(50);  // Call with literal 50

    // What can we prove about y?
    /*@ assert((i32)y >= 0i32); @*/     // Should work
    /*@ assert((i32)y < 100i32); @*/    // Should work
    /*@ assert((i32)y == 50i32); @*/   // Will this work?

    return y;
}
