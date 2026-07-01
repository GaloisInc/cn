int foo(int x)
/*@ requires x > 0;
    ensures return > x; @*/
{
  return x + 1;
}

int bar(int y)
/*@ requires take r = RequiresOf(foo, y);
            r;
    ensures return > y; @*/
{
  return foo(y);
}
