// Minimal 3-case switch to debug call pattern
int debug_switch(int x) {
  int result = 0;
  switch (x) {
    case 0: result = 0; break;
    case 1: result = 1; break;
    case 2: result = 2; break;
  }
  return result;
}
