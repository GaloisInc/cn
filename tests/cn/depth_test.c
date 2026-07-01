// Minimal test to reproduce deep recursion in n_expr
// Start with a simple sequential chain

int depth_test_seq(int x) {
  int a = x;
  /*@ assert(a == x); @*/
  a = a + 1;
  /*@ assert(a == x + 1); @*/
  a = a + 2;
  /*@ assert(a == x + 3); @*/
  a = a + 3;
  /*@ assert(a == x + 6); @*/
  a = a + 4;
  /*@ assert(a == x + 10); @*/
  a = a + 5;
  /*@ assert(a == x + 15); @*/
  a = a + 6;
  /*@ assert(a == x + 21); @*/
  a = a + 7;
  /*@ assert(a == x + 28); @*/
  a = a + 8;
  /*@ assert(a == x + 36); @*/
  a = a + 9;
  /*@ assert(a == x + 45); @*/
  return a;
}

int depth_test_switch(int x) {
  int result = 0;
  switch (x) {
    case 0: result = 0; break;
    case 1: result = 1; break;
    case 2: result = 2; break;
    case 3: result = 3; break;
    case 4: result = 4; break;
    case 5: result = 5; break;
    case 6: result = 6; break;
    case 7: result = 7; break;
    case 8: result = 8; break;
    case 9: result = 9; break;
  }
  return result;
}
