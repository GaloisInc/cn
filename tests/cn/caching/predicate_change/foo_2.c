/*@
predicate (i32) MyPred(pointer p) {
  take X = RW<int>(p);
  return X + 1i32;  // Changed: was X, now X + 1
}
@*/

int use_pred(int *p)
/*@ requires take X = MyPred(p);
    ensures take Y = MyPred(p);
            Y == X;
@*/
{
  return *p;
}
