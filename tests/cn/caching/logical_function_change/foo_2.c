/*@
function (i32) double(i32 x) {
  x * 2i32  // Changed: x + x → x * 2
}
@*/

int use_func(int a)
/*@ requires a >= 0i32;
    ensures return == double(a);
@*/
{
  return a + a;
}
