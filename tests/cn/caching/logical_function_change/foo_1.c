/*@
function (i32) double(i32 x) {
  x + x
}
@*/

int use_func(int a)
/*@ requires a >= 0i32;
    ensures return == double(a);
@*/
{
  return a + a;
}
