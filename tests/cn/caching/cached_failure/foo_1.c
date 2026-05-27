int wrong_impl(int x)
/*@ requires x >= 0i32;
    ensures return == x + 1i32;
@*/
{
  // WRONG: returns x instead of x+1
  return x;
}
