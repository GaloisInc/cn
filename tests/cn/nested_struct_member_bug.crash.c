/* Test case for nested struct member access bug in simplification
 *
 * The bug: when a function returns a struct and we access nested fields through
 * let aliases, the optimization incorrectly extracts the intermediate struct
 * instead of the final field, causing a type mismatch.
 *
 * Expected error: type mismatch where u32 field is expected but struct is provided
 */

struct inner_struct {
    unsigned int field1;
    unsigned int field2;
};

struct outer_struct {
    struct inner_struct inner;
    unsigned int outer_field;
};

/*@
function (struct inner_struct) make_inner(u32 x, u32 y) {
    struct inner_struct {field1: x, field2: y}
}

function (struct outer_struct) make_outer(u32 x, u32 y) {
    struct outer_struct {inner: make_inner(x, y), outer_field: 10u32}
}
@*/

unsigned int test_nested_member_access(unsigned int x, unsigned int y)
/*@ requires
      true;
    ensures
      // Get outer struct from function
      let outer_s = make_outer(x, y);
      // Access inner through alias
      let inner_alias = outer_s.inner;
      // With the bug: inner_alias.field1 returns outer_s (wrong type), causing crash
      // Without the bug: inner_alias.field1 returns x (correct), and this comparison succeeds
      return == inner_alias.field1;
@*/
{
    return x;
}
