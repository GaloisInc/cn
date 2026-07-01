typedef int tx_desc;
typedef int rx_desc;
/*@ datatype TxDescMaps {
}
 datatype OptionTxRing {
}
 datatype RxDescMaps {
}
 datatype OptionRxRing {
}
 function (boolean) ring_index_between_inclusive(u64 index, u32 start, u32 end,
u64 num_desc) {
 ((index - (u64)start) & (num_desc - 1u64)) <= (((u64)end - (u64)start) &
(num_desc - 1u64)) } predicate (tx_desc) TxDesc(pointer p, boolean dd_expected)
predicate (rx_desc) RxDescInFlight(pointer p, u32 buffer_size) predicate
(rx_desc) RxDescAvailable(pointer p, u32 buffer_size)          predicate
(map<u64, u8>) TxBuffer(pointer desc_ptr, tx_desc desc)          predicate
(datatype TxDescMaps) TxDescriptorRing(pointer base, u64 len, u32 head, u32
tail, u32 tx_done)          predicate (datatype OptionTxRing)
MaybeTxRing(pointer base_ptr, u64 len, u32 head, u32 tail, u32 tx_done, boolean
enabled)          predicate (datatype RxDescMaps) RxDescriptorRing(pointer base,
u64 len, u32 head, u32 tail, u32 rx_done, u32 buffer_size)          predicate
(datatype OptionRxRing) MaybeRxRing(pointer base_ptr, u64 len, u32 head, u32
tail, u32 rx_done, boolean enabled, u32 buffer_size)          @*/
struct i210_reg_state {
  unsigned int rdlen;
  unsigned int rdh;
  unsigned int rdt;
  unsigned int rxdctl;
  void *rx_base_addr;
};
/*@ datatype RegisterOffset {
   CTRL {
}
,     STATUS {
}
,     CTRL_EXT {
}
,     MDIC {
}
,     FCAL {
}
,     FCAH {
}
,     FCT {
}
,     RCTL {
}
,     ICR {
}
,     IMS {
}
,     IMC {
}
,     EIMS {
}
,     EITR0 {
}
,     EITR1 {
}
,     MDICNFG {
}
,     MTA {
u64 index}
,     TCTL {
}
,     TCTL_EXT {
}
,     TDBAL {
}
,     TDBAH {
}
,     TDLEN {
}
,     TDH {
}
,     TDT {
}
,     TXDCTL {
}
,     RDBAL {
}
,     RDBAH {
}
,     RDLEN {
}
,     SRRCTL {
}
,     RDH {
}
,     RDT {
}
,     RXDCTL {
}
}
datatype MaybeRegister {
   JustReg {
datatype RegisterOffset reg}
,     NothingReg {
}
}
type_synonym I210State = {
   struct i210_reg_state regs,     datatype OptionRxRing rx_ring_data }
function (datatype MaybeRegister) offset_to_register(u32 offset) {
   if (offset == 0x0000u32 || offset == 0x0004u32) {
      JustReg{
reg: CTRL{
}
}
  }
else {
if (offset == 0x0008u32) {
     JustReg{
reg: STATUS{
}
}
 }
else {
if (offset == 0x0018u32) {
   JustReg{
reg: CTRL_EXT{
}
}
}
else {
if (offset == 0x0020u32) {
 JustReg{
reg: MDIC{
}
}
}
else {
if (offset == 0x0028u32) {
 JustReg{
reg: FCAL{
}
}
}
else {
if (offset == 0x002Cu32) {
JustReg{
reg: FCAH{
}
}
}
else {
if (offset == 0x0030u32) {
JustReg{
reg: FCT{
}
}
}
else {
if (offset == 0x0100u32) {
JustReg{
reg: RCTL{}
}
}
else {
if (offset == 0x1500u32 || offset == 0x00C0u32) {
JustReg{reg: ICR{}}
}
else {
if (offset == 0x1508u32 || offset == 0x00D0u32) {         JustReg{reg: IMS{}} }
else { if (offset == 0x150Cu32 || offset == 0x00DBu32) {         JustReg{reg:
IMC{}}     } else { if (offset == 0x1524u32) {         JustReg{reg: EIMS{}} }
else { if (offset == 0x1680u32) {         JustReg{reg: EITR0{}}     } else { if
(offset == 0x1684u32) {         JustReg{reg: EITR1{}}     } else { if (offset ==
0x0E04u32) {         JustReg{reg: MDICNFG{}}     } else { if (offset >=
0x5200u32 && offset <= 0x53FCu32 && (offset & 0x3u32) == 0u32) {         let
mta_index = (u64)((offset - 0x5200u32) / 4u32);         JustReg{reg: MTA{index:
mta_index}}     } else { if (offset == 0x0400u32) {         JustReg{reg: TCTL{}}
} else { if (offset == 0x0404u32) {         JustReg{reg: TCTL_EXT{}}     } else
{ if (offset == 0x6000u32 || offset == 0x0420u32 || offset == 0x3800u32) {
JustReg{reg: TDBAL{}}     } else { if (offset == 0x6004u32 || offset ==
0x0424u32 || offset == 0x3804u32) {         JustReg{reg: TDBAH{}}     } else {
if (offset == 0x6008u32 || offset == 0x0428u32 || offset == 0x3808u32) {
JustReg{reg: TDLEN{}}     } else { if (offset == 0x6010u32 || offset ==
0x0430u32 || offset == 0x3810u32) {         JustReg{reg: TDH{}}     } else { if
(offset == 0x6018u32 || offset == 0x0438u32 || offset == 0x3818u32) {
JustReg{reg: TDT{}}     } else { if (offset == 0x6028u32 || offset == 0x3828u32)
{         JustReg{reg: TXDCTL{}}     } else { if (offset == 0xC000u32 || offset
== 0x0110u32 || offset == 0x2800u32) {         JustReg{reg: RDBAL{}}     } else
{ if (offset == 0xC004u32 || offset == 0x0114u32 || offset == 0x2804u32) {
JustReg{reg: RDBAH{}}     } else { if (offset == 0xC008u32 || offset ==
0x0118u32 || offset == 0x2808u32) {         JustReg{reg: RDLEN{}}     } else {
if (offset == 0xC00Cu32 || offset == 0x280Cu32) {         JustReg{reg: SRRCTL{}}
} else { if (offset == 0xC010u32 || offset == 0x0120u32 || offset == 0x2810u32)
{         JustReg{reg: RDH{}}     } else { if (offset == 0xC018u32 || offset ==
0x0128u32 || offset == 0x2818u32) {         JustReg{reg: RDT{}}     } else { if
(offset == 0xC028u32 || offset == 0x2828u32) {         JustReg{reg: RXDCTL{}} }
else {         NothingReg{}     }}}}}}}}}}}}}}}}}}}}}}
}
}
}
}
}
}
}
}
}
}
function (boolean) rx_sw_regs_preserved(struct i210_reg_state in_regs, struct
i210_reg_state out_regs) { ptr_eq(out_regs.rx_base_addr, in_regs.rx_base_addr) }
@*/
/*@ function (boolean) rdh_advancement(struct i210_reg_state in_regs, struct
   i210_reg_state out_regs) { (if ((in_regs.rxdctl & 0x02000000u32) == 0u32) {
                   out_regs.rdh == in_regs.rdh     }
            else {
                   if (in_regs.rdlen > 0u32) {
                      let num_desc = (u64)in_regs.rdlen / 16u64;
                      ring_index_between_inclusive((u64)out_regs.rdh,
   in_regs.rdh, in_regs.rdt, num_desc)         } else { out_regs.rdh ==
   in_regs.rdh         }
               }
           ) }
             @*/
/*@ function (boolean) rx_queue_step(struct i210_reg_state in_regs, struct
   i210_reg_state out_regs) { rx_sw_regs_preserved(in_regs, out_regs) &&
   rdh_advancement(in_regs, out_regs) }
             @*/
/*@ function (boolean) I210StepRead(I210State in_state, I210State out_state, u32
  offset) { let in_regs = in_state.regs; let out_regs = out_state.regs; let
  maybe_reg = offset_to_register(offset); (match maybe_reg { NothingReg{
    }
           => {
          false }
                     JustReg{
         reg: r}
           => {
                      match r {
                        RDH{
  }
        => {
                          rx_queue_step(in_regs, out_regs)                 }
                        _ => {
                          rx_queue_step(in_regs, out_regs)                 }
                    }
                  }
               }
           ) }
              @*/
void test_not_inflight_implies_dd_set() /*@ requires       true;
             @*/
{}
