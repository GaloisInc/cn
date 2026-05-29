int get_value(int x)
/*@ requires x > 0i32; x < 100i32;  // Added upper bound constraint
    ensures return == x; @*/
{
  return x;
}
