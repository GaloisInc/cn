int add(int a, int b)  // Changed: x→a, y→b
/*@ requires a >= 0i32;
             b >= 0i32;
    ensures return == a;
@*/
{
  return a;
}
