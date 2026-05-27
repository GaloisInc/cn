/*@
datatype IntOption {
  None {},
  Some { i32 value }
}

function (i32) get_value(datatype IntOption opt) {
  match opt {
    None {} => { 0i32 }
    Some {value: v} => { v }
  }
}
@*/

int use_option(int x)
/*@ requires x >= 0i32;
    ensures return == get_value(Some {value: x});
@*/
{
  return x;
}
