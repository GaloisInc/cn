int identity(int x)
/*@ requires x >= 0i32;
    ensures return == x;
@*/
{
  return x;
}
