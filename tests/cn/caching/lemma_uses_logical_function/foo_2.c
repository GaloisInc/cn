/*@
function (i32) times_two(i32 x) {
  x * 2i32
}

predicate (i32) Value(pointer p) {
  take V = RW<int>(p);
  return V;
}

lemma double_lemma(pointer p, i32 v)
  requires take x = Value(p); x == v; v == times_two(v / 2i32);
  ensures take y = Value(p); y == v;
@*/

int get_value(int *p)
/*@ requires take v = Value(p); v == times_two(v / 2i32);
    ensures take v2 = Value(p); @*/
{
  /*@ apply double_lemma(p, v); @*/
  return *p;
}

int main()
{
  int x = 10;
  int result = get_value(&x);
  return 0;
}
