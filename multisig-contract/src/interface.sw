library;

use std::bytes::Bytes;
use ::types::*;
abi Multisig {
    #[storage(read, write)]
    fn constructor(threshold: u8, owners_list: Vec<Identity>);
    #[storage(read, write)]
    fn propose_tx(to:Identity, tx_parameters: TransactionParameters) -> TxId;
    #[storage(read, write)]
    fn approve_tx(tx_id: TxId);
    #[storage(read, write)]
    fn reject_tx(tx_id: TxId);
    #[storage(read, write)]
    fn execute_tx(tx_id: TxId);
    #[storage(read, write)]
    fn remove_tx(tx_id: TxId);
    #[storage(read, write)]
    fn add_owner(owner: Identity);
    #[storage(read, write)]
    fn remove_owner(owner: Identity);
    #[storage(read, write)]
    fn change_threshold(threshold: u8);
    #[storage(read)]
    fn get_owners() -> Vec<Identity>;
    #[storage(read)]
    fn is_owner(owner: Identity) -> bool;
    #[storage(read)]
    fn get_threshold() -> u8;
    #[storage(read)]
    fn get_next_tx_id() -> TxId;
    #[storage(read)]
    fn get_active_tx_ids() -> Vec<TxId>;
    #[storage(read)]
    fn get_tx(tx_id: TxId) -> Option<Transaction>;
    #[storage(read)]
    fn get_tx_calldata(tx_id: TxId) -> Option<Bytes>;
    #[storage(read)]
    fn get_tx_function_selector(tx_id: TxId) -> Option<Bytes>;
     #[storage(read)]
    fn get_tx_approval_by_owner(tx_id: TxId, owner: Identity) -> Option<bool>;
    #[storage(read)]
    fn get_tx_approval_count(tx_id: TxId) -> Option<Approvals>;
    #[storage(read)]
    fn get_tx_rejection_count(tx_id: TxId) -> Option<Rejections>;
}
