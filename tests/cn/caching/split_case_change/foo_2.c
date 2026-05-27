int max(int x, int y)
/*@ requires true;
    ensures return >= x; return >= y; (return == x) || (return == y);
@*/
{
  /*@ split_case(x > y); @*/  // Changed: >= to >
  if (x >= y) {
    return x;
  } else {
    return y;
  }
}
