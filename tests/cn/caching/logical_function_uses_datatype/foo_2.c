/*@
datatype IntOption {
  Some { i32 value },
  None {},
  Unknown {}
}

function (i32) get_or_default(datatype IntOption opt, i32 default_val) {
  match opt {
    Some {value: v} => { v }
    None {} => { default_val }
    Unknown {} => { default_val }
  }
}
@*/

int use_option(int x)
/*@ requires x >= 0i32;
    ensures return == get_or_default(Some { value: x }, 0i32); @*/
{
  return x;
}

int main()
{
  int result = use_option(42);
  return 0;
}
