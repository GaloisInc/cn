#include <stdlib.h>
#include "fam_buffer.h"

long direct_access(struct buffer *buf, unsigned long i, unsigned long j)
/*@
  requires take b = Buffer(buf);
           i < b.len;
           j < b.len;
           //b.len >= 10u64;
  ensures take b2 = Buffer(buf);
@*/
{
    /*@ focus RW<int>, i; @*/
    int *pi = &buf->data[i];
    /*@ split_case i != j; @*/
    /*@ focus RW<int>, j; @*/
    int *pj = &buf->data[j];
    long diff = pj - pi;
    /*@ assert((i64)pj - (i64)pi == ((i64)j - (i64)i) * (i64)sizeof<int>); @*/
    /*@ assert(diff == (i64)j - (i64)i); @*/
    return diff;
}

long indirect_access(struct buffer *buf, unsigned long i, unsigned long j)
/*@
  requires take b = Buffer(buf);
           i < b.len;
           j < b.len;
           //b.len >= 10u64;
  ensures take b2 = Buffer(buf);
@*/
{
    /*@ focus RW<int>, i; @*/
    /*@ split_case i != j; @*/
    /*@ focus RW<int>, j; @*/

    int *data_ptr = buf->data;
    int *pi = &data_ptr[i];
    int *pj = &data_ptr[j];
    long diff = pj - pi;
    /*@ assert((i64)pj - (i64)pi == ((i64)j - (i64)i) * (i64)sizeof<int>); @*/
    /*@ assert(diff == (i64)j - (i64)i); @*/
    return diff;
}
