/*@
datatype AsyncOpType {
    OpRst {},
    OpDevRst {},
    OpMdic {},
    OpTxdctl { u32 tx_target },
    OpRxdctl { u32 rx_target }
}

function (datatype AsyncOpType) make_op(u32 x) {
    if (x == 0u32) {
        OpRst{}
    } else {
        if (x == 1u32) {
            OpDevRst{}
        } else {
            if (x == 2u32) {
                OpMdic{}
            } else {
                if (x == 3u32) {
                    OpTxdctl{tx_target: 0u32}
                } else {
                    OpRxdctl{rx_target: 0u32}
                }
            }
        }
    }
}

function (boolean) check_op(datatype AsyncOpType op, u32 val) {
    match op {
        OpRst{} => { val == 0u32 }
        OpDevRst{} => { val == 1u32 }
        OpMdic{} => { val == 2u32 }
        OpTxdctl{tx_target: t} => { val == 3u32 }
        OpRxdctl{rx_target: t} => { val == 4u32 }
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
