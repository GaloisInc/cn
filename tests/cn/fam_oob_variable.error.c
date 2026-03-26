// Bug: doesn't check that i < len before access
#include <stdlib.h>
#include "fam_buffer.h"

int get_unchecked(struct buffer *buf, unsigned long i)
/*@
  requires
    take b = Buffer(buf);
  ensures
    take b2 = Buffer(buf);
@*/
{
    /*@ focus RW<int>, i; @*/
    return buf->data[i];
}
