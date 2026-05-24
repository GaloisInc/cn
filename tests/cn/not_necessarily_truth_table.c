// Comprehensive test showing all four cases in the provability truth table
#include <stdint.h>

// Case 1: provable(X) = True, provable(¬X) = False
// X is necessarily true
int test_necessarily_true(int x)
/*@ requires (i32)x >= 10i32;
             (i32)x <= 20i32;
    ensures (i32)return >= 10i32;
@*/
{
    /*@ assert((i32)x >= 10i32); @*/  // Regular assert: PASSES
    return x;
}

// Case 2: provable(X) = False, provable(¬X) = True
// X is necessarily false
int test_necessarily_false(int x)
/*@ requires (i32)x >= 10i32;
             (i32)x <= 20i32;
    ensures (i32)return >= 10i32;
@*/
{
    /*@ assert(!((i32)x > 100i32)); @*/  // Assert negation: PASSES
    return x;
}

// Case 3: provable(X) = False, provable(¬X) = False
// X is possible but not necessary (satisfiable but not entailed)
int test_possible_not_necessary(int x)
/*@ requires (i32)x >= 10i32;
             (i32)x <= 20i32;
    ensures (i32)return >= 10i32;
@*/
{
    /*@ assert(not_necessarily((i32)x == 15i32)); @*/  // not_necessarily: PASSES
    /*@ assert(not_necessarily((i32)x == 10i32)); @*/  // Edge value: PASSES
    /*@ assert(not_necessarily((i32)x < 15i32)); @*/   // Range split: PASSES
    return x;
}
