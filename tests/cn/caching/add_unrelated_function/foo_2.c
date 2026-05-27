// Added unrelated function at the top

int unrelated_function(int x)
/*@ requires -1000i32 <= x; x <= 1000i32;
    ensures return == x * 2i32;
@*/
{
  return x * 2;
}

int get_value(int n)
/*@ requires -1000i32 <= n; n <= 1000i32;
    ensures return == n + n;
@*/
{
  return n + n;
}
