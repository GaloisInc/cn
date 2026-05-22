// Test that --check-consistency reports all inconsistent functions, not just the first

// First inconsistent function: requires false
int f1(int x)
/*@ requires false;
    ensures return == x + 1i32; @*/
{
  return x + 1;
}

// Second inconsistent function: requires false
int f2(int y)
/*@ requires false;
    ensures return == y * 2i32; @*/
{
  return y * 2;
}

// Third inconsistent function: contradictory requires (in one clause)
int f3(int z)
/*@ requires z > 10i32 && z < 5i32;
    ensures return == z; @*/
{
  return z;
}
