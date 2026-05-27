struct Point {
  int x;
  int y;
  int z;
};

/*@
function (i32) point_sum(struct Point pt) {
  pt.x + pt.y
}
@*/

int compute_sum(struct Point *pt)
/*@ requires take P = RW<struct Point>(pt);
             P.x >= 0i32; P.x < 100i32;
             P.y >= 0i32; P.y < 100i32;
    ensures take P2 = RW<struct Point>(pt); return == point_sum(P); @*/
{
  return pt->x + pt->y;
}

int main()
{
  struct Point p = {3, 7, 0};
  int result = compute_sum(&p);
  return 0;
}
