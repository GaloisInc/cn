int get_value(int x)
/*@ requires x >= 0i32;
    ensures return == x;
@*/
{
  // BROKEN: Returns 0 instead of x
  // Spec unchanged, so cache would say "skip"
  // But verification MUST run and MUST fail!
  return 0;
}
