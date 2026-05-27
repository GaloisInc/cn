struct Point {
  int x;
  int y;
};

int get_x(struct Point *p)
/*@ requires take P = RW<struct Point>(p);
    ensures take Q = RW<struct Point>(p);
            Q == P;
            return == P.x;
@*/
{
  return p->x;
}
