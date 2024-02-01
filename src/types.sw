library;

pub type TxId = u256;
pub type Approvals = u8;
pub type Rejections = u8;

const MAX_OWNERS: u8 = 10;
const MAX_TRANSACTIONS: u8 = 10;

pub struct Transaction {
    tx_id: TxId
}