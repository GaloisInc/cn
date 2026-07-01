// Test struct/record/datatype update syntax
#include <stdint.h>

struct Point {
    int x;
    int y;
};

/*@
datatype Tree {
  Leaf {},
  Node {i32 value, datatype Tree left, datatype Tree right}
}
@*/

// Test 1: Struct update (should work)
/*@
function (struct Point) update_struct_x(struct Point p, i32 new_x) {
    {x: new_x, ..p}
}
@*/

// Test 2: Record update (should work now!)
/*@
function ({i32 a, i32 b}) update_record_a({i32 a, i32 b} r, i32 new_a) {
    {a: new_a, ..r}
}
@*/

// Test 3: Multiple field updates
/*@
function (struct Point) update_both(struct Point p, i32 nx, i32 ny) {
    {x: nx, y: ny, ..p}
}
@*/

// Test 4: Datatype update (Constructor - doesn't work, must use manual reconstruction)
/*@
function (datatype Tree) update_tree_value(datatype Tree t, i32 new_val) {
    match t {
        Leaf {} => {
            Leaf {}
        }
        Node {value: _, left: l, right: r} => {
            Node {value: new_val, left: l, right: r}
        }
    }
}
@*/

int test() { return 0; }
