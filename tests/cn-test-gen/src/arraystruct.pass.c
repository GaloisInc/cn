typedef struct a {
    unsigned long long size;
} b;
struct c {
    b d[4];
};
/*@
predicate struct c C(pointer p) {
  take O = RW<struct c>(p);
  return O;
}
@*/
void foo(void)
/*@ requires true; @*/
{}
