/*@
predicate u32 Foo(pointer p, boolean b) {
  take s = RW<int*>(p);
  take o = each(u64 j; j < 3u64 && (b ? j < 2u64 : true)) {RW<int>(s+j)};
  return 0u32;
}
@*/

// only here so test will actually run
void foo(void) /*@ requires true; @*/ {}
