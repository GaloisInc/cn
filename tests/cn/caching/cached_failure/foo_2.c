int wrong_impl(int x)
/*@ requires x >= 0i32;
    ensures return == x + 1i32;
@*/
{
  // Still WRONG: same bug
  return x;
}
