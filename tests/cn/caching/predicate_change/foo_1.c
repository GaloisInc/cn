/*@
predicate (i32) MyPred(pointer p) {
  take X = RW<int>(p);
  return X;
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
