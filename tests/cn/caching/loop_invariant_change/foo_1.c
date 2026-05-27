int sum(int n)
/*@ requires (i32) n >= 0i32;
    ensures return == ((i32)n * ((i32)n + 1i32)) / 2i32;
@*/
{
  int i = 0;
  int s = 0;
  while (i < n)
  /*@ inv (i32)i >= 0i32; (i32)i <= (i32)n; (i32)s == ((i32)i * ((i32)i + 1i32)) / 2i32; @*/
  {
    i++;
    s += i;
  }
  return s;
}
