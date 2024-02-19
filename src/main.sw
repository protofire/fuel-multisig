contract;

mod types;
mod interface;
mod errors;

use types::*;
use interface::Multisig;
use errors::Error;
use std::storage::storage_vec::*;
use std::hash::Hash;
use std::call_frames::contract_id;

const MAX_OWNERS: u64 = 10; // TODO: Set a reasonable limit
const MAX_TXS: u64 = 10; // TODO: Set a reasonable limit
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
    approvals: StorageMap<TxId, StorageMap<Identity, bool>> = StorageMap::<TxId, StorageMap<Identity, bool>> {},
    /// Mapping of approvals count to check how many approvals a transaction has
    approvals_count: StorageMap<TxId, u8> = StorageMap {},
    /// Mapping of rejections count to check how many rejections a transaction has
    rejections_count: StorageMap<TxId, u8> = StorageMap {},
}

impl Multisig for Contract {
    #[storage(read, write)]
    fn constructor(threshold: u8, owners_list: Vec<Identity>) {
        // Check that the threshold is not 0, otherwise revert
        require(threshold != 0, Error::ThresholdCannotBeZero);

        let owners_count = owners_list.len();
    
        // Check that the owners list is not empty, otherwise revert
        require(owners_count > 0, Error::OwnersCannotBeEmpty);

        // Check that the threshold is not greater than the owners count, otherwise revert
        require(owners_count >= threshold.as_u64(), Error::ThresholdCannotBeGreaterThanOwners);

        // Check owners limit and revert if it has been reached
        require(owners_count <= MAX_OWNERS, Error::MaxOwnersReached);

        // Add the owners
        let mut i = 0;
        while i < owners_count {
            //TODO: Make this more efficient. Try insert is not working. https://github.com/FuelLabs/sway/blob/491a07fa5d298c78cf28a9a89db327cdf6fd5e69/sway-lib-std/src/storage/storage_map.sw#L180
            //let res = storage.owners.try_insert(owners_list.get(i).unwrap(), ());
            // If the owner is already in the list, revert
            // if res.is_err() {
            //     revert(0); //TODO: add custom error
            // }
            let owner = storage.owners.get(owners_list.get(i).unwrap()).try_read();
            require(owner.is_none(), Error::DuplicatedOwner);
            
            storage.owners.insert(owners_list.get(i).unwrap(), ());

            i += 1;
        }
        storage.owners_list.store_vec(owners_list);

        // Set the threshold
        storage.threshold.write(threshold);
    }

    #[storage(read, write)]
    fn propose_tx(tx: Transaction) {
        // Get the caller if it is an owner. If not, revert.
        let caller = get_caller_if_owner();

        // Get the next transaction id and increment the nonce
        let tx_id = storage.next_tx_id.read();
        storage.next_tx_id.write(tx_id + 1);

        //TODO: Check that the tx is valid

        // Store the transaction
        storage.tx_ids_list.push(tx_id);
        storage.txs.insert(tx_id, tx);

        // Initialize the approvals and rejections count
        storage.approvals_count.insert(tx_id, 1);
        storage.rejections_count.insert(tx_id, 0);
        storage.approvals.get(tx_id).insert(caller, true);

        //TODO: emit event
    }

    #[storage(read, write)]
    fn approve_tx(tx_id: TxId) {
        // Check that the tx_id is valid, otherwise revert
        check_tx_id_validity(tx_id);

        // Get the caller if it is an owner. If not, revert.
        let caller = get_caller_if_owner();

        // Check if the owner has already voted, otherwise revert
        check_if_already_voted(tx_id, caller);

        let approvals_count = storage.approvals_count.get(tx_id).read();
        storage.approvals_count.insert(tx_id, approvals_count + 1);

        storage.approvals.get(tx_id).insert(caller, true);

        //TODO: emit event
    }

    #[storage(read, write)]
    fn reject_tx(tx_id: TxId) {
        // Check that the tx_id is valid, otherwise revert
        check_tx_id_validity(tx_id);

        // Get the caller if it is an owner. If not, revert.
        let caller = get_caller_if_owner();

        // Check if the owner has already voted, otherwise revert
        check_if_already_voted(tx_id, caller);

        let rejections_count = storage.rejections_count.get(tx_id).read();
        storage.rejections_count.insert(tx_id, rejections_count + 1);

        storage.approvals.get(tx_id).insert(caller, false);

        //TODO: emit event
    }

    #[storage(read, write)]
    fn execute_tx(tx_id: TxId) {
        // Check that the tx_id is valid, otherwise revert
        check_tx_id_validity(tx_id);

        // Get current threshold
        let threshold = storage.threshold.read();

        // Get the tx approvals count
        let approvals_count = storage.approvals_count.get(tx_id).read();

        // If the tx has been approved by the required number of owners, execute it, otherwise revert
        require(approvals_count >= threshold, Error::ThresholdNotReached);
       
        // Remove the transaction from active transactions
        _remove_tx(tx_id);

        // TODO: execute the transaction

        // TODO: emit event
    }

    #[storage(read, write)]
    fn remove_tx(tx_id: TxId) {
        // Check that the tx_id is valid, otherwise revert
        check_tx_id_validity(tx_id);

        // Get current threshold
        let threshold = storage.threshold.read();

        // Get the tx rejections count
        let rejections_count = storage.rejections_count.get(tx_id).read();

        // Get owners count
        let owners_count = storage.owners_list.len();

        // If the rejections are greater than the owners - threshold, the threshold can't be reached, so remove the transaction. Otherwise, revert
        require(rejections_count.as_u64() >= (owners_count - threshold.as_u64()), Error::ThresholdStillReachable);
      
        // Remove the transaction from active transactions
        _remove_tx(tx_id);
    }

    #[storage(read, write)]
    fn add_owner(owner: Identity) {
        // This is disabled just for the sake of the demo
        // check_self_call();

        // Check owners limit and revert if it has been reached
        require(storage.owners_list.len() < MAX_OWNERS, Error::MaxOwnersReached);

        // Check that the owner is not already in the list, otherwise revert
        let owner_exists = storage.owners.get(owner).try_read();
        require(owner_exists.is_none(), Error::AlreadyOwner);
      
        // Add the owner
        storage.owners.insert(owner, ());
        storage.owners_list.push(owner);

        //TODO: emit event
    }

    #[storage(read, write)]
    fn remove_owner(owner: Identity) {
        // This is disabled just for the sake of the demo
        // check_self_call();

        // Check that the owner is already in the list, otherwise revert
        let owner_exists = storage.owners.get(owner).try_read();
        require(owner_exists.is_some(), Error::NotOwner);

        // Remove the owner
       _remove_owner(owner);
        
        //TODO: emit event

    }

    #[storage(read, write)]
    fn change_threshold(threshold: u8) {
        // This is disabled just for the sake of the demo
        // check_self_call();

        // Check that the threshold is not greater than the owners count, otherwise revert
        require(threshold.as_u64() <= storage.owners_list.len(), Error::ThresholdCannotBeGreaterThanOwners);

        // Check that the threshold is not 0, otherwise revert
        require(threshold != 0, Error::ThresholdCannotBeZero);

        // Change the threshold
        storage.threshold.write(threshold);

        //TODO: emit event
    }

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
    fn get_tx(tx_id: TxId) -> Option<Transaction> {
        storage.txs.get(tx_id).try_read()
    }

    #[storage(read)]
    fn get_tx_approval_by_owner(tx_id: TxId, owner: Identity) -> Option<bool> {
        //TODO: this might panic if the tx_id is not valid, so we should check it
        storage.approvals.get(tx_id).get(owner).try_read()
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

// Helper functions
#[storage(read, write)]
fn _remove_tx(tx_id: TxId) {
    // Remove the transaction from active transactions
    let tx_ids_list = storage.tx_ids_list.load_vec();
    //TODO: Find a better way to remove the tx_id from the tx_ids_list
    let mut i = 0;
    while i < tx_ids_list.len() {
        if tx_ids_list.get(i).unwrap() == tx_id {
            storage.tx_ids_list.remove(i);
            break;
        }
        i += 1;
    }

    storage.txs.remove(tx_id);
    storage.approvals.remove(tx_id);
    storage.approvals_count.remove(tx_id);
    storage.rejections_count.remove(tx_id);
}

#[storage(read, write)]
fn _remove_owner(owner: Identity) {
    // Remove the owner from the mapping
    storage.owners.remove(owner);

    // Remove the owner from the list
    let owners_list = storage.owners_list.load_vec();
    let mut i = 0;
    while i < owners_list.len() {
        if owners_list.get(i).unwrap() == owner {
            storage.owners_list.remove(i);
            break;
        }
        i += 1;
    }
}

#[storage(read)]
fn get_caller_if_owner() -> Identity {
    let caller = match msg_sender() {
        Ok(caller) => caller,
        Err(_) => revert(0),
    };

    // Check if the caller is an owner, otherwise revert
    require(storage.owners.get(caller).try_read().is_some(), Error::NotOwner);

    caller
}

#[storage(read)]
fn check_tx_id_validity(tx_id: TxId) {
    require(storage.txs.get(tx_id).try_read().is_some(), Error::InvalidTxId);
}

#[storage(read)]
fn check_if_already_voted(tx_id: TxId, owner: Identity) {
    // TxId is not checked here because it is already checked in the approve_tx and reject_tx functions
    require(storage.approvals.get(tx_id).get(owner).try_read().is_none(), Error::AlreadyVoted);
}

fn check_self_call() {
    let caller = match msg_sender() {
        Ok(caller) => caller,
        Err(_) => revert(0),
    };

    let is_self_call = match caller {
        Identity::ContractId(caller_contract_id) => caller_contract_id == contract_id(),
        _ => false,
    };
    require(is_self_call, Error::Unauthorized);
}

#[test]
fn test_success() {
    let caller = abi(Multisig, CONTRACT_ID);
    let result = caller.change_threshold {    }(2);
}
