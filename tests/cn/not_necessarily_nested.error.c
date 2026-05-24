// Test what happens when not_necessarily is used nested
#include <stdint.h>

int test_nested_in_implication(int x, int y)
/*@ requires (i32)x >= 0i32;
             (i32)x < 100i32;
    ensures (i32)return >= 0i32;
@*/
{
    // Try to use not_necessarily nested in an implication
    /*@ assert((i32)x > 50i32 implies not_necessarily((i32)y == 5i32)); @*/
    return x;
}

int test_nested_in_conjunction(int x, int y)
/*@ requires (i32)x >= 0i32;
             (i32)x < 100i32;
    ensures (i32)return >= 0i32;
@*/
{
    // Try to use not_necessarily in a conjunction
    /*@ assert((i32)x >= 0i32 && not_necessarily((i32)y == 5i32)); @*/
    return x;
}
