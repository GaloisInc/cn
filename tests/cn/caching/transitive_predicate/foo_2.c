/*@ predicate (i32) BaseValue(pointer p) {
  take x = Owned<int>(p);
  return x + 1i32;  // CHANGED: Added +1 to the return value
} @*/

/*@ predicate (i32) DoubledValue(pointer p) {
  take base = BaseValue(p);
  return base * 2i32;
} @*/

int check_doubled(int *p)
/*@ requires take val = DoubledValue(p);
           val == 10i32;
    ensures take val2 = Owned<int>(p);
@*/
{
  return *p;
}
