/*@
function (i32) times_two(i32 x) {
  x + x
}

predicate (i32) DoubleValue(pointer p) {
  take V = RW<int>(p);
  assert(V == times_two(V / 2i32));
  return V;
}
@*/

int get_value(int *p)
/*@ requires take v = DoubleValue(p);
    ensures take v2 = DoubleValue(p); return == v; @*/
{
  return *p;
}

int main()
{
  int x = 10;
  int result = get_value(&x);
  return 0;
}
