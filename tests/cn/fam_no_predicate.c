struct bar {
    unsigned int n;
    int x[];
};

void use_bar(struct bar *p)
/*@
  requires
    take I = RW(p);
    I.n >= 2u32;
  ensures
    take O = RW(p);
@*/
{
    unsigned int n = p->n;
    p->n = n;
}
