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
    /// The nonce of the multisig wallet.
    tx_id: TxId = 0,
    /// The number of approvals required in order to execute a transaction.
    threshold: u8 = 0,
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
    fn change_threshold(threshold: u8) {
    }

    #[storage(read)]
    fn get_threshold() -> u8 {
        storage.threshold.read()
    }

    #[storage(read)]
    fn get_next_tx_id() -> TxId {
        storage.tx_id.read()
    }

    #[storage(read)]
    fn get_owners() -> Vec<Identity> {
        let owners = storage.owners_list.load_vec();
        owners
    }

    #[storage(read)]
    fn is_owner(owner: Identity) -> bool {
        //storage.owners.contains_key(&owner)
        true
    }

    #[storage(read)]
    fn get_active_txid_list() -> Vec<TxId> {
        Vec::new()
    }

    #[storage(read)]
    fn get_tx(tx_id: TxId) -> Transaction {
        Transaction{
            tx_id
        }
    }

    #[storage(read)]
    fn get_tx_approvals(tx_id: TxId) -> Option<Approvals> {
        None
    }

    #[storage(read)]
    fn get_tx_rejections(tx_id: TxId) -> Option<Rejections> {
        None
    }
}

#[test]
fn test_success() {
    let caller = abi(Multisig, CONTRACT_ID);
    let result = caller.change_threshold {}(2);
}
