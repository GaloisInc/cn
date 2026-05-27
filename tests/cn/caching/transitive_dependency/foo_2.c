/*@
function (i32) base(i32 x) {
  x + 2i32  // Changed: was x + 1i32
}

function (i32) middle(i32 x) {
  base(x) + 1i32
}
@*/

int use_middle(int a)
/*@ requires a >= 0i32;
    ensures return == middle(a);
@*/
{
  return a + 2;
}
