// Test: --check-consistency should respect --only flag

int foo()
/*@ ensures true; @*/
{
    return 0;
}

int bar()
/*@ ensures true; @*/
{
    return 0;
}

int main() {
    return 0;
}
