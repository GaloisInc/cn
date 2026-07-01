int helper(int x)
/*@ requires x >= 0i32;
           x < 1000i32;
    ensures return == x + 1i32;
@*/
{
  return x + 1;
}

int caller(int y)
/*@ requires y >= 0i32;
           y < 1000i32;
    ensures return == y + 1i32;
@*/
{
  return helper(y);
}
