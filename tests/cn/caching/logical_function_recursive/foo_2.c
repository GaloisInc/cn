/*@
function (i32) helper(i32 n) {
  n + 2i32
}

function (i32) uses_helper(i32 n) {
  helper(n) * 2i32
}
@*/

int compute(int n)
/*@ requires n >= 0i32; n < 100i32;
    ensures return == uses_helper(n); @*/
{
  return (n + 2) * 2;
}

int main()
{
  int result = compute(5);
  return 0;
}
