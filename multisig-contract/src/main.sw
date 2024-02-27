contract;

mod events;
mod types;
mod interface;
mod errors;

use types::*;
use interface::Multisig;
use errors::MultisigError;
use events::*;
use std::{
    asset::transfer,
    call_frames::contract_id,
    context::this_balance,
    hash::Hash,
    low_level_call::{
        call_with_function_selector,
        CallParams,
    },
    storage::storage_vec::*,
    storage::storage_bytes::*
};
use std::bytes::Bytes;

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
    // TODO: This is a workaround. We should use the calldata and function_selector from ContractCallParams directly instead of storing them in a separate storage key
    /// The calldata of the transactions that are currently active.(Optional)
    txs_calldata: StorageMap<TxId, StorageBytes> = StorageMap {},
    /// The function selector of the transactions that are currently active.(Optional)
    txs_function_selector: StorageMap<TxId, StorageBytes> = StorageMap {},
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
        // Check that the multisig wallet has not been initialized yet, otherwise revert
        require(storage.threshold.read() == 0, MultisigError::AlreadyInitialized);

        // Check that the threshold is not 0, otherwise revert
        require(threshold != 0, MultisigError::ThresholdCannotBeZero);

        let owners_count = owners_list.len();

        // Check that the owners list is not empty, otherwise revert
        require(owners_count > 0, MultisigError::OwnersCannotBeEmpty);

        // Check that the threshold is not greater than the owners count, otherwise revert
        require(
            owners_count >= threshold
                .as_u64(),
            MultisigError::ThresholdCannotBeGreaterThanOwners,
        );

        // Check owners limit and revert if it has been reached
        require(owners_count <= MAX_OWNERS, MultisigError::MaxOwnersReached);

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
            require(owner.is_none(), MultisigError::DuplicatedOwner);

            storage.owners.insert(owners_list.get(i).unwrap(), ());

            i += 1;
        }
        storage.owners_list.store_vec(owners_list);

        // Set the threshold
        storage.threshold.write(threshold);

        // Emit event
        log(MultisigInitialized {
            contract_id: contract_id(),
            threshold: threshold,
            owners: owners_list,
        });
    }

    #[storage(read, write)]
    fn propose_tx(to: Identity, tx_parameters: TransactionParameters) -> TxId{
        //TODO: Check if StorageBytes in tx_parameters can be sent, or if we need to change the type to Bytes and then convert it to StorageBytes in here
        // Check that the multisig wallet has been initialized, otherwise revert
        require(storage.threshold.read() != 0, MultisigError::NotInitialized);

        // Get the caller if it is an owner. If not, revert.
        let caller = get_caller_if_owner();

        // Get the next transaction id and increment the nonce
        let tx_id = storage.next_tx_id.read();
        storage.next_tx_id.write(tx_id + 1);

        //TODO: Check that the tx is valid

        // Store the transaction
        storage.tx_ids_list.push(tx_id);

        // TODO: This is a workaround. We should use the calldata and function_selector from ContractCallParams directly instead of storing them in a separate storage key
        let internal_tx_parameters = match tx_parameters {
            TransactionParameters::Call(contract_call_params) => {
               
                let calldata = storage.txs_calldata.get(tx_id);
                calldata.write_slice(contract_call_params.calldata);

                let function_selector = storage.txs_function_selector.get(tx_id);
                function_selector.write_slice(contract_call_params.function_selector);

                InternalTransactionParameters::Call(InternalContractCallParams {
                    forwarded_gas: contract_call_params.forwarded_gas,
                    single_value_type_arg: contract_call_params.single_value_type_arg,
                    transfer_params: contract_call_params.transfer_params,
                })
            },
            TransactionParameters::Transfer(transfer_params) => {
                InternalTransactionParameters::Transfer(transfer_params)
            },
        };

        storage
            .txs
            .insert(
                tx_id,
                Transaction {
                    tx_id,
                    to,
                    tx_parameters: internal_tx_parameters,
                },
            );

        // Initialize the approvals and rejections count
        storage.approvals_count.insert(tx_id, 1);
        storage.rejections_count.insert(tx_id, 0);
        storage.approvals.get(tx_id).insert(caller, true);

        // Emit event
        log(TransactionProposed { tx_id: tx_id, to: to, transaction_parameters: tx_parameters});
        tx_id
    }

    #[storage(read, write)]
    fn approve_tx(tx_id: TxId) {
        // Check that the multisig wallet has been initialized, otherwise revert
        require(storage.threshold.read() != 0, MultisigError::NotInitialized);

        // Check that the tx_id is valid, otherwise revert
        check_tx_id_validity(tx_id);

        // Get the caller if it is an owner. If not, revert.
        let caller = get_caller_if_owner();

        // Check if the owner has already voted, otherwise revert
        check_if_already_voted(tx_id, caller);

        let approvals_count = storage.approvals_count.get(tx_id).read();
        storage.approvals_count.insert(tx_id, approvals_count + 1);

        storage.approvals.get(tx_id).insert(caller, true);

        // Emit event
        log(TransactionApproved { tx_id: tx_id, owner: caller });
    }

    #[storage(read, write)]
    fn reject_tx(tx_id: TxId) {
        // Check that the multisig wallet has been initialized, otherwise revert
        require(storage.threshold.read() != 0, MultisigError::NotInitialized);

        // Check that the tx_id is valid, otherwise revert
        check_tx_id_validity(tx_id);

        // Get the caller if it is an owner. If not, revert.
        let caller = get_caller_if_owner();

        // Check if the owner has already voted, otherwise revert
        check_if_already_voted(tx_id, caller);

        let rejections_count = storage.rejections_count.get(tx_id).read();
        storage.rejections_count.insert(tx_id, rejections_count + 1);

        storage.approvals.get(tx_id).insert(caller, false);

        // Emit event
        log(TransactionRejected { tx_id: tx_id, owner: caller });
    }

    #[storage(read, write)]
    fn execute_tx(tx_id: TxId) {
        // Check that the multisig wallet has been initialized, otherwise revert
        require(storage.threshold.read() != 0, MultisigError::NotInitialized);

        // Check that the tx_id is valid, otherwise revert
        check_tx_id_validity(tx_id);

        // Get current threshold
        let threshold = storage.threshold.read();

        // Get the tx approvals count
        let approvals_count = storage.approvals_count.get(tx_id).read();

        // If the tx has been approved by the required number of owners, execute it, otherwise revert
        require(approvals_count >= threshold, MultisigError::ThresholdNotReached);

        // Get the transaction from the storage.
        let transaction = storage.txs.get(tx_id).try_read().unwrap();

        // Remove the transaction from active transactions
        _remove_tx(tx_id);

        // Execute the transaction
        _execute_tx(transaction);

        //TODO: Check if we can analyze the result of the execution and log this in the event
        // Emit event
        log(TransactionExecuted { tx_id: tx_id });
    }

    #[storage(read, write)]
    fn remove_tx(tx_id: TxId) {
        // Check that the multisig wallet has been initialized, otherwise revert
        require(storage.threshold.read() != 0, MultisigError::NotInitialized);

        // Check that the tx_id is valid, otherwise revert
        check_tx_id_validity(tx_id);

        // Get current threshold
        let threshold = storage.threshold.read();

        // Get the tx rejections count
        let rejections_count = storage.rejections_count.get(tx_id).read();

        // Get owners count
        let owners_count = storage.owners_list.len();

        // If the rejections are greater than the owners - threshold, the threshold can't be reached, so remove the transaction. Otherwise, revert
        require(
            rejections_count
                .as_u64() >= (owners_count - threshold
                    .as_u64()),
            MultisigError::ThresholdStillReachable,
        );

        // Remove the transaction from active transactions
        _remove_tx(tx_id);

        // Emit event
        log(TransactionCancelled { tx_id: tx_id });
    }

    #[storage(read, write)]
    fn add_owner(owner: Identity) {
        // Check that the multisig wallet has been initialized, otherwise revert
        require(storage.threshold.read() != 0, MultisigError::NotInitialized);

        check_self_call();

        // Check owners limit and revert if it has been reached
        require(
            storage
                .owners_list
                .len() < MAX_OWNERS,
            MultisigError::MaxOwnersReached,
        );

        // Check that the owner is not already in the list, otherwise revert
        let owner_exists = storage.owners.get(owner).try_read();
        require(owner_exists.is_none(), MultisigError::AlreadyOwner);

        // Add the owner
        storage.owners.insert(owner, ());
        storage.owners_list.push(owner);

        // Emit event
        log(OwnerAdded { owner: owner });
    }

    #[storage(read, write)]
    fn remove_owner(owner: Identity) {
        // Check that the multisig wallet has been initialized, otherwise revert
        require(storage.threshold.read() != 0, MultisigError::NotInitialized);

        check_self_call();

        // Check that the owner is already in the list, otherwise revert
        let owner_exists = storage.owners.get(owner).try_read();
        require(owner_exists.is_some(), MultisigError::NotOwner);

        // Remove the owner
        _remove_owner(owner);

        // Emit event
        log(OwnerRemoved { owner: owner });
    }

    #[storage(read, write)]
    fn change_threshold(threshold: u8) {
        // Check that the multisig wallet has been initialized, otherwise revert
        require(storage.threshold.read() != 0, MultisigError::NotInitialized);

        check_self_call();

        // Check that the threshold is not greater than the owners count, otherwise revert
        require(
            threshold
                .as_u64() <= storage
                .owners_list
                .len(),
            MultisigError::ThresholdCannotBeGreaterThanOwners,
        );

        // Check that the threshold is not 0, otherwise revert
        require(threshold != 0, MultisigError::ThresholdCannotBeZero);

        // Change the threshold
        storage.threshold.write(threshold);

        // Emit event
        log(ThresholdChanged { new_threshold: threshold });
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
    fn get_tx_calldata(tx_id: TxId) -> Option<Bytes> {
        storage.txs_calldata.get(tx_id).read_slice()
    }

    #[storage(read)]
    fn get_tx_function_selector(tx_id: TxId) -> Option<Bytes> {
        storage.txs_function_selector.get(tx_id).read_slice()
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
    storage.txs_calldata.remove(tx_id);
    storage.txs_function_selector.remove(tx_id);
    storage.approvals.remove(tx_id);
    storage.approvals_count.remove(tx_id);
    storage.rejections_count.remove(tx_id);

    // Emit event
    log(TransactionRemoved { tx_id: tx_id });
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

#[storage(read, write)]
fn _execute_tx(transaction: Transaction) { 
    // Check if it is a call or a transfer and execute it.
    match transaction.tx_parameters {
        InternalTransactionParameters::Call(contract_call_params) => {
            let target_contract_id = match transaction.to {
                Identity::ContractId(contract_identifier) => contract_identifier,
                _ => {
                    // TODO: Add custom error
                    revert(0);
                },
            };

            if contract_call_params.transfer_params.value.is_some() {
                require(
                    contract_call_params
                        .transfer_params
                        .value
                        .unwrap() <= this_balance(contract_call_params.transfer_params.asset_id),
                    MultisigError::InsufficientAssetAmount,
                );
            }

            let call_params = CallParams {
                coins: contract_call_params.transfer_params.value.unwrap_or(0),
                asset_id: contract_call_params.transfer_params.asset_id,
                gas: contract_call_params.forwarded_gas,
            };

            // TODO: This is a workaround. We should use the calldata and function_selector from ContractCallParams directly instead of storing them in a separate storage key
            let function_selector = storage.txs_function_selector.get(transaction.tx_id).read_slice().unwrap();
            let calldata = storage.txs_calldata.get(transaction.tx_id).read_slice().unwrap();
          
            // TODO: Check if we can analyze the result of the execution
            call_with_function_selector(
                target_contract_id,
                function_selector,
                calldata,
                contract_call_params
                    .single_value_type_arg,
                call_params,
            );
        },
        InternalTransactionParameters::Transfer(transfer_params) => {
            require(
                transfer_params
                    .value
                    .is_some(),
                MultisigError::TransferRequiresAValue,
            );
            let value = transfer_params.value.unwrap();
            require(
                value <= this_balance(transfer_params.asset_id),
                MultisigError::InsufficientAssetAmount,
            );

            transfer(transaction.to, transfer_params.asset_id, value);
            //TODO: emit event
        },
    }
}

#[storage(read)]
fn get_caller_if_owner() -> Identity {
    let caller = match msg_sender() {
        Ok(caller) => caller,
        Err(_) => revert(0),
    };

    // Check if the caller is an owner, otherwise revert
    require(
        storage
            .owners
            .get(caller)
            .try_read()
            .is_some(),
        MultisigError::NotOwner,
    );

    caller
}

#[storage(read)]
fn check_tx_id_validity(tx_id: TxId) {
    require(
        storage
            .txs
            .get(tx_id)
            .try_read()
            .is_some(),
        MultisigError::InvalidTxId,
    );
}

#[storage(read)]
fn check_if_already_voted(tx_id: TxId, owner: Identity) {
    // TxId is not checked here because it is already checked in the approve_tx and reject_tx functions
    require(
        storage
            .approvals
            .get(tx_id)
            .get(owner)
            .try_read()
            .is_none(),
        MultisigError::AlreadyVoted,
    );
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
    require(is_self_call, MultisigError::Unauthorized);
}

#[test]
fn test_success() {
    let caller = abi(Multisig, CONTRACT_ID);
    let result = caller.change_threshold {    }(2);
}
