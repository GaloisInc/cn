#ifndef FAM_BUFFER_H_
#define FAM_BUFFER_H_

struct buffer {
    unsigned long len;
    int data[];
};
/*@
predicate struct buffer Buffer(pointer p) {
    take A = Alloc(p);
    take I = RW<struct buffer>(p);
    take Ifam = each(u64 j; j < (u64)I.len) {
      //RW<int>(array_shift<int>(member_shift<struct buffer>(p, data), j))
      RW<int>(array_shift<int>(p->data, j))
    };
    assert(A.base <= (u64) p);
    assert((u64) member_shift<struct buffer>(p, data) + sizeof<int>*(u64)I.len <= A.base + A.size);
    return I;
}
@*/
/*@
type_synonym Buffer =
  { u64 len
  , map<u64, i32> data
  }
predicate Buffer BufferAndData(pointer p) {
    take A = Alloc(p);
    take I = RW<struct buffer>(p);
    take Ifam = each(u64 j; j < (u64)I.len) {
      RW<int>(array_shift<int>(member_shift<struct buffer>(p, data), j))
    };
    assert(A.base <= (u64) p);
    assert((u64) member_shift<struct buffer>(p, data) + sizeof<int>*(u64)I.len <= A.base + A.size);
    return {len : I.len, data: Ifam};
}
@*/
#endif // FAM_BUFFER_H_
