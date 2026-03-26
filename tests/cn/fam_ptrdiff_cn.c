#include <stdlib.h>
#include <stddef.h>
#include "fam_buffer.h"

long compute_diff(struct buffer *buf, unsigned long i, unsigned long j)
/*@
  requires
    take b = Buffer(buf);
    i < b.len;
    j < b.len;
  ensures
    take b2 = Buffer(buf);
    return == (i64)j - (i64)i;
@*/
{
    /*@ split_case i != j; @*/
    /*@ focus RW<int>, i; @*/
    int *pi = &buf->data[i];
    /*@ focus RW<int>, j; @*/
    int *pj = &buf->data[j];
    return pj - pi;
}
