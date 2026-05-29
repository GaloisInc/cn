// Test: Match with wildcard pattern after concrete constructor patterns
// This triggers a bug in cn test where valid wildcard patterns are
// incorrectly flagged as "redundant"
//
// The match expression is valid and non-redundant:

/*@
datatype D {
    A {},
    B {},
    C {}
}

function (i32) check_reg(datatype D r) {
    match r {
        A{} => { 1i32 }
        _ => { 0i32 }
    }
}
@*/

int test_wildcard()
/*@ ensures check_reg(A{}) == 1i32 &&
            check_reg(B{}) == 0i32 &&
            check_reg(C{}) == 0i32;
@*/
{
    return 0;
}
