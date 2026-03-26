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
