// Absolute minimal switch to isolate the issue

int switch_2(int x) {
  int result = 0;
  switch (x) {
    case 0: result = 0; break;
    case 1: result = 1; break;
  }
  return result;
}

int switch_3(int x) {
  int result = 0;
  switch (x) {
    case 0: result = 0; break;
    case 1: result = 1; break;
    case 2: result = 2; break;
  }
  return result;
}

int switch_5(int x) {
  int result = 0;
  switch (x) {
    case 0: result = 0; break;
    case 1: result = 1; break;
    case 2: result = 2; break;
    case 3: result = 3; break;
    case 4: result = 4; break;
  }
  return result;
}
