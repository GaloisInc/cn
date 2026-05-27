struct Point {
  int x;
  int y;
};

/*@
predicate (struct Point) PointValue(pointer p) {
  take Pt = RW<struct Point>(p);
  return Pt;
}

lemma point_lemma(pointer p, struct Point pt)
  requires take x = PointValue(p); x.x == pt.x; x.y == pt.y;
  ensures take y = PointValue(p); y.x == pt.x;
@*/

int get_x(struct Point *p)
/*@ requires take pt = PointValue(p);
    ensures take pt2 = PointValue(p); @*/
{
  /*@ apply point_lemma(p, pt); @*/
  return p->x;
}

int main()
{
  struct Point pt = {5, 10};
  int result = get_x(&pt);
  return 0;
}
