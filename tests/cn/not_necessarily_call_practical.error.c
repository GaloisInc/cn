// Error case: calling with a specific known value
#include <stdint.h>

int process_any_value(int x)
/*@ requires (i32)x >= 0i32;
             (i32)x < 100i32;
             not_necessarily((i32)x == 50i32);
    ensures (i32)return >= 0i32;
@*/
{
    return x;
}

// This should FAIL: x is exactly 50
int test_invalid_call_exact()
/*@ ensures (i32)return >= 0i32;
@*/
{
    int x = 50;
    return process_any_value(x);  // FAIL: x == 50 is provable
}
