// Practical use case: not_necessarily documents that a function
// doesn't assume specific values, even though range is constrained
#include <stdint.h>

// A function that works for ANY value in the range,
// not just a specific one
int process_any_value(int x)
/*@ requires (i32)x >= 0i32;
             (i32)x < 100i32;
             not_necessarily((i32)x == 50i32);  // Don't assume x is any specific value
    ensures (i32)return >= 0i32;
            (i32)return < 100i32;
@*/
{
    // Implementation that handles any value in [0, 100)
    return x;
}

// Test 1: Valid call with unknown value in range
int test_valid_call(int x)
/*@ requires (i32)x >= 0i32;
             (i32)x < 100i32;
    ensures (i32)return >= 0i32;
@*/
{
    // This passes: x is in range but specific value unknown
    return process_any_value(x);
}

// Test 2: Invalid call where caller knows x is exactly 50
int test_invalid_call_exact()
/*@ ensures (i32)return >= 0i32;
@*/
{
    int x = 50;
    // This FAILS: x == 50 is provable, violates the not_necessarily precondition
    // The function documents it doesn't want specific values assumed
    return process_any_value(x);
}

// Test 3: Valid call with constrained range (value in range)
int test_valid_call_constrained(int x)
/*@ requires (i32)x >= 40i32;
             (i32)x < 60i32;
    ensures (i32)return >= 0i32;
@*/
{
    // This passes: x is in [40,60), which overlaps with [0,100)
    // The value 50 is within [40,60), so x==50 is possible but not provable
    return process_any_value(x);
}
