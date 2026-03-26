#include <stdlib.h>
#include <stddef.h>
#include "fam_buffer.h"

long offset_to_fam_element(struct buffer *buf, unsigned long i)
/*@
  requires take b = Buffer(buf);
           i < b.len;
           b.len >= 5u64;
  ensures take b2 = Buffer(buf);
          return == (i64)(sizeof<unsigned long> + i * sizeof<int>);
@*/
{
    /*@ focus RW<int>, i; @*/
    char *struct_start = (char *)buf;
    char *fam_element = (char *)&buf->data[i];
    return fam_element - struct_start;
}

_Bool fam_after_base(struct buffer *buf)
/*@
  requires take b = Buffer(buf);
           b.len >= 1u64;
  ensures take b2 = Buffer(buf);
          return == 1u8;
@*/
{
    /*@ focus RW<int>, 0u64; @*/
    // FAM element is always after the struct base
    return (char *)&buf->data[0] > (char *)buf;
}

long offset_len_to_fam(struct buffer *buf)
/*@
  requires take b = Buffer(buf);
           b.len >= 1u64;
  ensures take b2 = Buffer(buf);
          // data[] starts right after len field (no padding in this struct)
          return == (i64)sizeof<unsigned long>;
@*/
{
    /*@ focus RW<int>, 0u64; @*/
    char *len_ptr = (char *)&buf->len;
    char *fam_ptr = (char *)&buf->data[0];
    return fam_ptr - len_ptr;
}
