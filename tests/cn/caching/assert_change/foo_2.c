int increment(int x)
/*@ requires x >= 0i32 && x < 100i32;
    ensures return == x + 1i32;
@*/
{
  /*@ assert(x < 25i32 || x >= 25i32); @*/  // Changed: different tautology
  return x + 1;
}
