// Test: Updating regular fields in struct with FAM should work
// Struct update syntax is allowed for regular fields even when the struct
// contains a FAM field. The FAM pointer is preserved from the base struct.
typedef struct {
  int a;
  int b;
  int c[];
} s;

void test(s *p)
/*@
  requires
    take I = RW(p);
    let I2 = {a: 1i32, ..I};      // OK: Update regular field
    let I3 = {b: 2i32, ..I2};     // OK: Update another regular field
    let I4 = {a: 3i32, b: 4i32, ..I};  // OK: Update multiple regular fields
  ensures
    take O = RW(p);
@*/
{
}
