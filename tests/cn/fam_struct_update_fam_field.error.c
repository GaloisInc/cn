// Test: Updating FAM field in struct update should be disallowed
// FAM fields in CN struct values represent C pointers to the FAM array.
// While struct update syntax works for regular fields (e.g., {a: 1i32, ..I}),
// updating the FAM pointer itself should not be allowed as it would break
// the connection to the original C struct's layout.
typedef struct {
  int a;
  int b[];
} s;

void test(s *p, int *newptr)
/*@
  requires
    take I = RW(p);
    let I2 = {b: newptr, ..I};  // ERROR: Cannot update FAM field
  ensures
    take O = RW(p);
@*/
{
}
