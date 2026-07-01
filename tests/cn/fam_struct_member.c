typedef struct A {
  unsigned int b;
} A;

/*@
predicate i32 FOO(pointer p, u32 c) {
  take N = RW<A>(p);
  take D = each(u64 j; j < c) {
    RW(array_shift(N.bad, j))
  };
  return;
}
@*/
