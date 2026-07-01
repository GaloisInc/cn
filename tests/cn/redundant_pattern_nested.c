/*@
datatype OpType {
    OpRst {},
    OpMdic {}
}

datatype TxRing {
    NoTxRing {},
    SomeTxRing { u32 dummy }
}

function (boolean) check_async(datatype OpType op, datatype TxRing tx) {
    match op {
        OpRst{} => {
            match tx {
                NoTxRing{} => { true }
                SomeTxRing{dummy: _} => { false }
            }
        }
        OpMdic{} => {
            match tx {
                NoTxRing{} => { false }
                SomeTxRing{dummy: _} => { true }
            }
        }
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
