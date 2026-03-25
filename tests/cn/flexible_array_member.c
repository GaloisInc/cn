// Test flexible array member (FAM) support
#include <stdlib.h>

struct buffer {
    unsigned long len;
    char data[];  // FAM - flexible array member
};

// Test 1: Access fixed member of struct with FAM
// This tests that normal struct member access works even when the struct has a FAM
void test_fixed_member(struct buffer *buf)
/*@
  requires take b = RW(buf);
  ensures take b2 = RW(buf); b2.len == b.len;
@*/
{
    unsigned long len = buf->len;
    buf->len = len;
}

// Test 2: Access FAM member itself
// Accessing FAM returns pointer to element type
void test_fam_member(struct buffer *buf)
/*@
  requires take b = RW(buf);
  ensures take b2 = RW(buf);
@*/
{
    char *data_ptr = buf->data;  // FAM access - gets pointer to first element
    (void)data_ptr;  // Use the variable to avoid warning
}
