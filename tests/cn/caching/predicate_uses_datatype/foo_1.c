/*@
datatype IntOption {
  Some { i32 value },
  None {}
}

predicate (datatype IntOption) MaybeValue(pointer p) {
  take V = RW<int>(p);
  return Some { value: V };
}
@*/

int check_value(int *p)
/*@ requires take opt = MaybeValue(p);
    ensures take opt2 = MaybeValue(p); @*/
{
  return *p;
}

int main()
{
  int x = 5;
  int result = check_value(&x);
  return 0;
}
