// Test: consistency error to see which functions are checked

int foo()
/*@ requires true;
    ensures false;  // Inconsistent: requires true but ensures false
@*/
{
    return 0;
}

int bar()
/*@ requires true;
    ensures false;  // Inconsistent: requires true but ensures false
@*/
{
    return 0;
}
