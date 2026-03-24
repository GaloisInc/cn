typedef struct {
  void *p;
  unsigned long long size;
} A;
/*@
  predicate A B(pointer p, A v) {
  take a = each(u64 j; j < v.size) { RW<char>(array_shift<char>(v.p, j))};
  return v;
  }
@*/
typedef struct {
    A a;
} As;

As bar;
void foo()
/*@
  requires
    take s = RW<As>(&bar);
    take as = B(member_shift<As>(&bar, a), s.a);
@*/
{}
