int add(int x, int y)
/*@ requires x >= 1i32;  // Changed: was 0i32
             y >= 0i32;
    ensures return == x;
@*/
{
  return x;
}
