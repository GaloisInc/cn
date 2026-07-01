// Test that FAM access via struct value syntax is rejected

struct buffer {
    unsigned long len;
    int data[];
};

/*@
predicate (struct buffer) BadPredicate(pointer p) {
    take I = RW<struct buffer>(p);
    take Ifam = each(u64 j; j < (u64)I.len) {
      RW<int>(array_shift<int>(p->data, j))
    };
    return I;
}
@*/

void test(struct buffer *buf)
/*@
  requires take b = BadPredicate(buf);
  ensures take b2 = BadPredicate(buf);
@*/
{
}
