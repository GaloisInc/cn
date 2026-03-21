// cn test --skip=test_qpred_iargs
/*@
predicate u32 CheckValue(pointer p, i32 idx) {
  take x = Owned<int>(p);
  assert (x == idx);
  return (u32)idx;
}
@*/

void test_qpred_iargs(int *arr)
/*@ requires take items = each(i32 i; 0i32 <= i && i < 3i32) { CheckValue(arr + i, i) };
    ensures take items2 = each(i32 i; 0i32 <= i && i < 3i32) { CheckValue(arr + i, i) };
@*/
{
  return;
}

void foo(void)
/*@ ensures true; @*/
{
  int arr[3] = {0, 1, 99};
  test_qpred_iargs(arr);
}
