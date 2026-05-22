// Test consistency checking with different kinds of inconsistencies

// Function 1: requires false
int f1(int x)
/*@ requires false;
    ensures return == x + 1i32; @*/
{
  return x + 1;
}

// Function 2: unsat ensures
int f2(int y)
/*@ ensures return > 0i32 && return < 0i32; @*/
{
  return y;
}

// Function 3: contradictory requires
int f3(int z)
/*@ requires z > 10i32 && z < 5i32;
    ensures return == z; @*/
{
  return z;
}
