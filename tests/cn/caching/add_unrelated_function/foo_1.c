// Original file with just target function

int get_value(int n)
/*@ requires -1000i32 <= n; n <= 1000i32;
    ensures return == n + n;
@*/
{
  return n + n;
}
