#include <stdlib.h>
#include "fam_buffer.h"

int test_alias_write_read(struct buffer *buf, unsigned long i, int value)
/*@
  requires take b = Buffer(buf);
           i < b.len;
  ensures take o = Buffer(buf);
          return == value;
@*/
{
    /*@ focus RW<int>, i; @*/
    int *p1 = buf->data + i;
    int *p2 = buf->data + i;
    *p1 = value;
    return *p2;
}

int test_direct_vs_pointer(struct buffer *buf, unsigned long i, int value)
/*@
  requires
    take b = Buffer(buf);
    i < b.len;
  ensures
    take o = Buffer(buf);
    return == value;
@*/
{
    /*@ focus RW<int>, i; @*/
    int *ptr = buf->data + i;
    *ptr = value;
    int x = buf->data[i];
    return x;
}
