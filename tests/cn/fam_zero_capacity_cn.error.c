// Bug: tries to access data[0] when len is 0 (no elements allocated)

#include <stdlib.h>
#include "fam_buffer.h"

int get_from_empty(struct buffer *buf)
/*@
  requires take b = Buffer(buf);
           b.len == 0u64;
  ensures take b2 = Buffer(buf);
@*/
{
    /*@ focus RW<int>, 0u64; @*/
    return buf->data[0];
}
