library;

use ::types::*;

/// Event emitted when the constructor is called
pub struct MultisigInitialized{
    contract_id: ContractId,
    threshold: u8,
    owners: Vec<Identity>
}

/// Event emitted when the threshold is changed
pub struct ThresholdChanged{
    new_threshold: u8
}

/// Event emitted when an owner is added
pub struct OwnerAdded{
    owner: Identity
}

/// Event emitted when an owner is removed
pub struct OwnerRemoved{
    owner: Identity
}

/// Event emitted when a transaction is proposed
pub struct TransactionProposed{
    tx_id: TxId,
    to: Identity,
    transaction_parameters: TransactionParameters,
}

/// Event emitted when a transaction is executed
pub struct TransactionExecuted{
    tx_id: TxId
}

/// Event emitted when a transaction is cancelled
pub struct TransactionCancelled{
    tx_id: TxId
}

/// Event emitted when a transaction is removed
pub struct TransactionRemoved{
    tx_id: TxId
}

/// Event emitted when a transaction is approved
pub struct TransactionApproved{
    tx_id: TxId,
    owner: Identity
}

/// Event emitted when a transaction is rejected
pub struct TransactionRejected{
    tx_id: TxId,
    owner: Identity
}