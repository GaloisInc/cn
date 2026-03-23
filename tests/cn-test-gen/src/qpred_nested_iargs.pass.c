// cn test --skip=test_qpred_iargs
/*@
predicate u32 CheckValue(pointer p, i32 idx, pointer q) {
  take x = each(u32 j; 0u32 <= j && j < 2u32 && (u32)idx < 1u32 ? false : false) { RW<int>(array_shift<int>(q,j)) };
  assert (x[0u32] == idx);
  return (u32)idx;
}
@*/

void test_qpred_iargs(int **arr)
/*@
  requires
    take Iptrs = each(i32 i; 0i32 <= i && i < 3i32) { RW<int*>(arr+i) };
    take Iints = each(i32 i; 0i32 <= i && i < 3i32) { CheckValue(arr+i, i, Iptrs[i]) };
  ensures
    take Optrs = each(i32 i; 0i32 <= i && i < 3i32) { RW<int*>(arr+i) };
    take Oints = each(i32 i; 0i32 <= i && i < 3i32) { CheckValue(arr+i, i, Optrs[i]) };
@*/
{
  return;
}

void foo(void)
/*@ ensures true; @*/
{
  int arr1[2] = {0, 1};
  int arr2[2] = {1, 2};
  int arr3[2] = {2, 3};
  int *arr[3] = {arr1, arr2, arr3};
  test_qpred_iargs(arr);
}
