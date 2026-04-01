// this file should pass now. the FAM in the produced struct (I) only depends on p
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
    O.x == I.x;
@*/
{
}

void test2(struct bar *p)
/*@
  requires
    take I = RW(p);
  ensures
    take O = RW(p);
    ptr_eq(O.x, I.x);
@*/
{
}
void test3(struct bar *p)
/*@
  requires
    take I = RW(p);
  ensures
    take O = RW(p);
    ptr_eq(O.x, array_shift<char>(p, 4u64));
@*/
{
}
void test4(struct bar *p, struct bar *q)
/*@
  requires
    take I = RW(p);
    take J = RW(q);
  ensures
    take O = RW(p);
    take P = RW(q);
    ptr_eq(O.x, array_shift<char>(p, 4u64));
    ptr_eq(P.x, array_shift<char>(q, 4u64));
    !ptr_eq(p, q);
    !ptr_eq(p->x, q->x);
@*/
{
}
