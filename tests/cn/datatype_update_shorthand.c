// Test: Can we match against a datatype constructor and bind the entire record?
#include <stdint.h>

/*@
datatype Tree {
  Leaf {},
  Node {i32 value, datatype Tree left, datatype Tree right}
}
@*/

/*@
function (datatype Tree) update_value_shorthand(datatype Tree t, i32 new_val) {
    match t {
        Leaf {} => { Leaf {} }
        Node r => { Node {value: new_val, ..r} }
    }
}
@*/

int test() { return 0; }
