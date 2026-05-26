// Simple test for database functionality

int add(int x, int y)
/*@ requires true;
    ensures return == x + y;
@*/
{
    return x + y;
}

int main() {
    return add(1, 2);
}
