// Demonstrates final not_necessarily semantics with interprocedural filtering
#include <stdint.h>

// ============================================================================
// 1. ASSERTIONS: not_necessarily is checked locally
// ============================================================================

int test_assertions(int x)
/*@ requires (i32)x >= 0i32;
             (i32)x < 100i32;
    ensures (i32)return >= 0i32;
@*/
{
    // PASS: x==50 is satisfiable but not entailed
    /*@ assert(not_necessarily((i32)x == 50i32)); @*/

    // Would FAIL if uncommented: x >= 0 IS provable
    // /*@ assert(not_necessarily((i32)x >= 0i32)); @*/

    return x;
}

// ============================================================================
// 2. POSTCONDITIONS: checked locally, filtered interprocedurally
// ============================================================================

int get_value(int x)
/*@ requires (i32)x >= 0i32;
             (i32)x < 100i32;
    ensures (i32)return >= 0i32;
            (i32)return < 100i32;
            not_necessarily((i32)return == 50i32);  // Checked when verifying body
@*/
{
    // PASSES: return==50 is not provable from the body (returns x, which varies)
    return x;
}

int caller(int x)
/*@ requires (i32)x == 50i32;
    ensures (i32)return >= 0i32;
@*/
{
    int y = get_value(x);

    // PASSES: not_necessarily in get_value's postcondition is filtered out
    // at call site, so it doesn't poison the caller's context.
    // We just get: y >= 0 && y < 100
    // We can't prove y == 50 here (postcondition doesn't say return == x)

    return y;
}

// ============================================================================
// 3. PRECONDITIONS: filtered completely (not checked at call site)
// ============================================================================

int process(int x)
/*@ requires (i32)x >= 10i32;
             (i32)x <= 20i32;
             not_necessarily((i32)x == 15i32);  // Filtered at call sites
    ensures (i32)return >= 10i32;
@*/
{
    return x;
}

int caller_specific()
/*@ ensures (i32)return >= 10i32;
@*/
{
    int x = 15;

    // PASSES: not_necessarily in precondition is filtered out at call site
    // Caller just needs to prove: x >= 10 && x <= 20
    return process(x);
}

// ============================================================================
// SUMMARY:
// - not_necessarily in assertions: checked locally ✓
// - not_necessarily in postconditions: checked in function body, filtered at call sites ✓
// - not_necessarily in preconditions: filtered at call sites ✓
//
// This enables:
// 1. Testing that properties are "possible but not necessary"
// 2. Documenting nondeterminism in specifications
// 3. Preventing "context poisoning" across function boundaries
// ============================================================================
