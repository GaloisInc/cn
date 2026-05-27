/*@
predicate (i32) PointX(pointer p) {
  take Px = RW<struct Point>(p);
  return Px.x;
}
@*/

struct Point {
  int x;
  int y;
};

int get_x(struct Point *p)
/*@ requires take x = PointX(p);
    ensures take x2 = PointX(p); return == x; @*/
{
  return p->x;
}

int main()
{
  struct Point pt = {5, 10};
  int result = get_x(&pt);
  return 0;
}
