/*@
predicate (i32) Positive(pointer p) {
  take P = RW<int>(p);
  assert(P > 0i32);
  return P;
}

lemma my_lemma(pointer p)
  requires take x = Positive(p);
  ensures take y = Positive(p); y == x;
@*/

int check_value(int *p)
/*@ requires take x = Positive(p);
    ensures take y = Positive(p); @*/
{
  /*@ apply my_lemma(p); @*/
  return *p;
}

int main()
{
  int x = 42;
  int result = check_value(&x);
  return 0;
}
