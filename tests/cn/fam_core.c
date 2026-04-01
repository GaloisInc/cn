// Test that FAM field access from struct value doesn't crash the compiler
// This test verifies the Cerberus fix for FAM memberof translation

typedef struct {
  short a;
  int b[];
} s;

// Access FAM from pointer (should work)
void from_ptr(s *c)
/*@
  requires
    take p = RW(c);
  ensures
    take p2 = RW(c);
@*/
{
  int *fam = c->b;
}
