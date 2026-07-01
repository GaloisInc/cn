/* Demonstrate issues with default<> in transitivity proofs */

#include <stdint.h>

/* Simple non-transitive relation: "exactly one more" */
/*@ function (boolean) OnePlus(u32 x, u32 y) {
      y == x + 1u32
    }
@*/

/* Test 1: The way we THOUGHT we were testing transitivity with default<>
 * This PASSES but shouldn't prove transitivity!
 */
void test_false_transitivity_with_default(uint32_t a)
/*@ requires
      a == 10u32;
      let b = default<u32>;
      let c = default<u32>;
      OnePlus(a, b) == true;
      OnePlus(b, c) == true;
    ensures
      // Can we prove a -> c?
      // OnePlus(a, c) would be a=c+1, but we have a=b+1 and b=c+1, so a=c+2
      let c_out = default<u32>;
      OnePlus(a, c_out) == true;  // Just checks "can a be onePlus something?"
@*/
{
}

/* Test 2: What happens if we try to use THE SAME default variable? */
void test_transitivity_same_variable(uint32_t a)
/*@ requires
      a == 10u32;
      let b = default<u32>;
      let c = default<u32>;
      OnePlus(a, b) == true;
      OnePlus(b, c) == true;
    ensures
      // Try to reference the SAME c from requires
      OnePlus(a, c) == true;  // Should fail - c is from requires scope
@*/
{
}

/* Test 3: With parameters (proper universal quantification) */
void test_transitivity_with_params(uint32_t a, uint32_t b, uint32_t c)
/*@ requires
      OnePlus(a, b) == true;
      OnePlus(b, c) == true;
    ensures
      true;
@*/
{
    /* This should FAIL - OnePlus is not transitive */
    /*@ assert(OnePlus(a, c) == true); @*/
}
