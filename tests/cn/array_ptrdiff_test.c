#include <stdlib.h>

long array_compute_diff(int *arr, unsigned long i, unsigned long j)
/*@
  requires take arr_elems = each(u64 k; k < 10u64) {
             RW<int>(array_shift<int>(arr, k))
           };
           i < 10u64;
           j < 10u64;
  ensures take arr_elems2 = each(u64 k; k < 10u64) {
            RW<int>(array_shift<int>(arr, k))
          };
          return == (i64)j - (i64)i;
@*/
{
    /*@ focus RW<int>, i; @*/
    int *pi = &arr[i];
    /*@ split_case i != j; @*/
    /*@ focus RW<int>, j; @*/
    int *pj = &arr[j];
    return pj - pi;
}
