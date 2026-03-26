#include <stdlib.h>
#include "fam_buffer.h"

void test_fam_ptr_as_regular_ptr(struct buffer *buf, unsigned long i, unsigned long j)
/*@
  requires take b = Buffer(buf);
           i < b.len;
           j < b.len;
           b.len >= 10u64;
  ensures take b2 = Buffer(buf);
@*/
{
    /*@ focus RW<int>, i; @*/
    /*@ split_case i != j; @*/
    /*@ focus RW<int>, j; @*/

    int *fam_ptr = buf->data;

    int *pi = &fam_ptr[i];
    int *pj = &fam_ptr[j];

    /*@ assert((i64)pj - (i64)pi == ((i64)j - (i64)i) * (i64)sizeof<int>); @*/
}

void test_array_ptr(int *arr, unsigned long i, unsigned long j)
/*@
  requires take arr_elems = each(u64 k; k < 10u64) {
             RW<int>(array_shift<int>(arr, k))
           };
           i < 10u64;
           j < 10u64;
  ensures take arr_elems2 = each(u64 k; k < 10u64) {
            RW<int>(array_shift<int>(arr, k))
          };
@*/
{
    /*@ focus RW<int>, i; @*/
    /*@ split_case i != j; @*/
    /*@ focus RW<int>, j; @*/

    int *pi = &arr[i];
    int *pj = &arr[j];

    /*@ assert((i64)pj - (i64)pi == ((i64)j - (i64)i) * (i64)sizeof<int>); @*/
}
