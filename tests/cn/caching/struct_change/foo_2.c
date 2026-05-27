struct Point {
  int x;
  int y;
  int z;  // Changed: added field z
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
