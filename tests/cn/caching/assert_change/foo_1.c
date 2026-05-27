int increment(int x)
/*@ requires x >= 0i32 && x < 100i32;
    ensures return == x + 1i32;
@*/
{
  /*@ assert(x < 50i32 || x >= 50i32); @*/
  return x + 1;
}
