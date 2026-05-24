// Demonstrates that not_necessarily in postcondition "poisons" caller context
#include <stdint.h>

int identity(int x)
/*@ requires (i32)x >= 0i32;
             (i32)x < 100i32;
    ensures (i32)return == (i32)x;  // Returns exactly x
            not_necessarily((i32)return == 50i32);  // But claims 50 not provable
@*/
{
    return x;
}

// This FAILS even though it should be provable
int test_poisoned_context()
/*@ ensures (i32)return == 50i32;
@*/
{
    int y = identity(50);  // Call with literal 50

    // We know:
    // 1. y == x (from postcondition)
    // 2. x == 50 (from call site)
    // Therefore y == 50
    //
    // But the not_necessarily postcondition blocks this proof!
    /*@ assert((i32)y == 50i32); @*/  // FAILS

    return y;
}
