/*@
datatype IntOption {
  Some { i32 value },
  None {}
}

predicate (datatype IntOption) OptValue(pointer p) {
  take V = RW<int>(p);
  return Some { value: V };
}

lemma option_lemma(pointer p, datatype IntOption opt)
  requires take x = OptValue(p); x == opt;
  ensures take y = OptValue(p); y == opt;
@*/

int check_value(int *p)
/*@ requires take opt = OptValue(p);
    ensures take opt2 = OptValue(p); @*/
{
  /*@ apply option_lemma(p, opt); @*/
  return *p;
}

int main()
{
  int x = 5;
  int result = check_value(&x);
  return 0;
}
