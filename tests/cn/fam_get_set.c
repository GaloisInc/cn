// CN test: In-bounds FAM access with proper specs

#include <stdlib.h>
#include "fam_buffer.h"

int get(struct buffer *buf, unsigned long i)
/*@
  requires
    take b = BufferAndData(buf);
    i < b.len;
  ensures
    take b2 = BufferAndData(buf);
    b2.data == b.data;
    b2.len == b.len;
    return == b.data[i];
@*/
{
    /*@ focus RW<int>, i; @*/
    return buf->data[i];
}

void set(struct buffer *buf, unsigned long i, int value)
/*@
  requires
    take b = BufferAndData(buf);
    i < b.len;
  ensures
    take b2 = BufferAndData(buf);
    b2.data == b.data[i:value];
    b2.len == b.len;
@*/
{
    /*@ focus RW<int>, i; @*/
    buf->data[i] = value;
}

int get_set(struct buffer *buf, unsigned long i, int value)
/*@
  requires
    take b = BufferAndData(buf);
    i < b.len;
  ensures
    take b2 = BufferAndData(buf);
    b2.data == b.data[i:value];
    b2.len == b.len;
    return == value;
@*/
{
  set(buf, i, value);
  return get(buf, i);
}
