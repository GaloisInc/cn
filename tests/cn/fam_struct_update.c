typedef struct {
  int a;
  int b[];
} c;
void d(c *e)
/*@
  requires
    take I = RW(e);
    let I_ = {a:1i32, ..I};
@*/
{
}
