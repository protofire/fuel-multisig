contract;

mod types;
mod interface;
mod errors;

use types::*;
use interface::Multisig;
use errors::Error;
use std::storage::storage_vec::*;
use std::hash::Hash;

storage {
    /// List of Owners of the multisig wallet.
    owners_list: StorageVec<Identity> = StorageVec {},
    /// Owners of the multisig wallet.
    owners: StorageMap<Identity, ()> = StorageMap {},
    /// The nonce of the multisig wallet for the next transaction.
    next_tx_id: TxId = 0,
    /// The number of approvals required in order to execute a transaction.
    threshold: u8 = 0,
    /// The list of transaction ids that are currently active.
    tx_ids_list: StorageVec<TxId> = StorageVec {},
    /// The transactions that are currently active.
    txs: StorageMap<TxId, Transaction> = StorageMap {},
    /// Mapping of approvals to check which owner has approved or rejected a transaction.
    approvals: StorageMap<(TxId, Identity), bool> = StorageMap {},
    /// Mapping of approvals count to check how many approvals a transaction has
    approvals_count: StorageMap<TxId, u8> = StorageMap {},
    /// Mapping of rejections count to check how many rejections a transaction has
    rejections_count: StorageMap<TxId, u8> = StorageMap {},
}

impl Multisig for Contract {
    #[storage(read, write)]
    fn constructor(threshold: u8, owners_list: Vec<Identity>) {
        // TODO: check that threshold is less or eq than owners_list.len() and that owners_list.len() is not 0
        // TODO: check that owners_list does not contain duplicates
        storage.threshold.write(threshold);

        let mut i = 0;
        while i < owners_list.len() {
            storage.owners_list.push(owners_list.get(i).unwrap());
            storage.owners.insert(owners_list.get(i).unwrap(), ());
            i += 1;
        }
    }

    #[storage(read, write)]
    fn propose_tx(to: Identity, tx: Transaction) {}

    #[storage(read, write)]
    fn approve_tx(tx_id: TxId) {}

    #[storage(read, write)]
    fn reject_tx(tx_id: TxId) {}

    #[storage(read, write)]
    fn execute_tx(tx_id: TxId) {}

    #[storage(read, write)]
    fn remove_tx(tx_id: TxId) {}

    #[storage(read, write)]
    fn add_owner(owner: Identity) {}

    #[storage(read, write)]
    fn remove_owner(owner: Identity) {}

    #[storage(read, write)]
    fn change_threshold(threshold: u8) {}

    #[storage(read)]
    fn get_threshold() -> u8 {
        storage.threshold.read()
    }

    #[storage(read)]
    fn get_next_tx_id() -> TxId {
        storage.next_tx_id.read()
    }

    #[storage(read)]
    fn get_owners() -> Vec<Identity> {
        storage.owners_list.load_vec()
    }

    #[storage(read)]
    fn is_owner(owner: Identity) -> bool {
        storage.owners.get(owner).try_read().is_some()
    }

    #[storage(read)]
    fn get_active_tx_ids() -> Vec<TxId> {
        storage.tx_ids_list.load_vec()
    }

    #[storage(read)]
    fn get_tx(tx_id: TxId) -> Transaction {
        Transaction { data: 5 }
    }

    #[storage(read)]
    fn get_tx_approval_by_owner(tx_id: TxId, owner: Identity) -> Option<bool> {
        storage.approvals.get((tx_id, owner)).try_read()
    }

    #[storage(read)]
    fn get_tx_approval_count(tx_id: TxId) -> Option<Approvals> {
        storage.approvals_count.get(tx_id).try_read()
    }

    #[storage(read)]
    fn get_tx_rejection_count(tx_id: TxId) -> Option<Rejections> {
        storage.rejections_count.get(tx_id).try_read()
    }
}

#[test]
fn test_success() {
    let caller = abi(Multisig, CONTRACT_ID);
    let result = caller.change_threshold {}(2);
}
