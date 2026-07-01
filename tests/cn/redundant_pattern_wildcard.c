/*@
datatype Reg {
    RDH {},
    RDT {},
    CTRL {}
}

function (boolean) check_reg(datatype Reg r) {
    match r {
        RDH{} => { true }
        _ => { true }
    }
}
@*/

void test()
/*@ requires true;
    ensures true;
@*/
{
    return;
}
