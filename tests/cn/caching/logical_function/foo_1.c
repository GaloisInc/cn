/*@
function (i32) times_two(i32 x) {
  x + x
}
@*/

int compute(int x)
/*@ requires x >= 0i32; x < 1000i32;
    ensures return == times_two(x) + 1i32; @*/
{
  return 2 * x + 1;
}

int main()
{
  int result = compute(5);
  return 0;
}
