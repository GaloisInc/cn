struct foo {
    int x[2];
};

void use_foo(struct foo *p)
/*@
  requires
    take I = RW(p);
  ensures
    take O = RW(p);
@*/
{
    /*@ focus RW<int>, 1u64; @*/
    int x = p->x[1];

}

struct bar {
    unsigned long n;
    int x[];
};

/*@ predicate struct bar Bar(pointer p) {
    take A = Alloc(p);
    take I = RW<struct bar>(p);
    take Ifam = each(u64 j; j < (u64)I.n) {
      RW<int>(array_shift<int>(member_shift<struct bar>(p, x), j))
    };
    assert(A.base <= (u64) p);
    assert((u64) member_shift<struct bar>(p, x) + sizeof<int>*(u64)I.n <= A.base + A.size);
    return I;
}
@*/

void use_bar(struct bar *p)
/*@
  requires take b = Bar(p);
           b.n >= 2u64;
  ensures take b2 = Bar(p);
@*/
{
    /*@ focus RW<int>, 1u64; @*/
    int x = p->x[1];

}
