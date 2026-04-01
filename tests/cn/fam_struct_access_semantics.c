struct bar {
    unsigned int n;
    int x[];
};

void test(struct bar *p)
/*@
  requires
    take I = RW(p);
  ensures
    take O = RW(p);
    ptr_eq(member_shift<struct bar>(p, x), p->x);
@*/
{
}
