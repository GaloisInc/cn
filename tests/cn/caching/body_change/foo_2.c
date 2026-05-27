int identity(int x)
/*@ requires x >= 0i32;
    ensures return == x;
@*/
{
  // Changed: added local variable
  int tmp = x;
  return tmp;
}
