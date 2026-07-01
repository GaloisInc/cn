#include <stdint.h>
typedef struct {
    uint16_t l;
    int rs[];
} s;
/*@
type_synonym SRegion =
  { u16 l
  , map<u64, i32> rs_data
  }
predicate SRegion Region(pointer p, u32 c) {
  take I = RW<s>(p);
  take B = each(u64 j; j < (u64)c) {
    RW(array_shift(member_shift<s>(p, rs), j))
  };
  return {l: I.l, rs_data: B};
}
@*/

void foo(s *p)
/*@
  requires take I = Region(p, 2u32);
  ensures take O = Region(p, 2u32);
@*/
{
  //if (p->n > 0) {
    /*@ focus RW<uint16_t>, p->l; @*/
  //}
}

#if 0
void bar(void)
/*@
  requires true;
@*/
{
    s s;
    s.n = 0;
    foo(&s);


}
#endif
