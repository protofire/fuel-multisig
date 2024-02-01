library;

pub type TxId = u64; //TODO: change this to u256. Using u256 raises the error "The trait `Hash` is not implemented for `u256`"
pub type Approvals = u8;
pub type Rejections = u8;

const MAX_OWNERS: u8 = 10;
const MAX_TRANSACTIONS: u8 = 10;

pub struct Transaction {
    data: u64,// TODO: this is just for testing. Change this to the actual data type
}
