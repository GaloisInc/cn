int helper(int x)
/*@ requires x >= 0i32;
           x < 1000i32;
    ensures return == x + 1i32;
@*/
{
  int tmp = x + 1;
  return tmp;
}

int caller(int y)
/*@ requires y >= 0i32;
           y < 1000i32;
    ensures return == y + 1i32;
@*/
{
  return helper(y);
}
