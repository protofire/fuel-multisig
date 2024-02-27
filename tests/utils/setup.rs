use fuels::{
    accounts::wallet::WalletUnlocked,
    core::codec::{calldata, fn_selector},
    prelude::{
        abigen, Address, AssetId, Contract, Error, LoadConfiguration, TxPolicies, BASE_ASSET_ID,
    },
    test_helpers::{launch_custom_provider_and_get_wallets, WalletsConfig},
    types::{bech32::Bech32ContractId, Bytes, Identity},
};

// Load abi from json
abigen!(
    Contract(
        name = "Multisig",
        abi = "./multisig-contract/out/debug/fuel-multisig-abi.json"
    ),
    Contract(
        name = "Counter",
        abi = "tests/utils/test-contracts/counter/out/debug/counter-abi.json"
    )
);

pub const DEFAULT_TRANSFER_AMOUNT: u64 = 200;
pub(crate) const DEFAULT_FORWARDED_GAS: u64 = 10_000_000;

pub struct MultisigCaller {
    pub contract: Multisig<WalletUnlocked>,
    pub wallet: WalletUnlocked,
}

pub struct CounterCaller {
    pub contract: Counter<WalletUnlocked>,
    pub wallet: WalletUnlocked,
}

pub fn base_asset_contract_id() -> AssetId {
    AssetId::new(BASE_ASSET_ID.into())
}

pub fn transfer_parameters() -> (WalletUnlocked, Identity, TransactionParameters) {
    let receiver_wallet = WalletUnlocked::new_random(None);
    let receiver = Identity::Address(receiver_wallet.address().into());

    let transaction_parameters = TransactionParameters::Transfer(TransferParams {
        asset_id: base_asset_contract_id(),
        value: Some(DEFAULT_TRANSFER_AMOUNT),
    });

    (receiver_wallet, receiver, transaction_parameters)
}

pub fn call_parameters() -> TransactionParameters {
    TransactionParameters::Call(ContractCallParams {
        calldata: Bytes(calldata!(5u64).unwrap()),
        forwarded_gas: DEFAULT_FORWARDED_GAS,
        function_selector: Bytes(fn_selector!(increment_counter(u64))),
        single_value_type_arg: true,
        transfer_params: TransferParams {
            asset_id: base_asset_contract_id(),
            value: None,
        },
    })
}

pub async fn get_wallets(num_wallets: u64) -> Vec<WalletUnlocked> {
    launch_custom_provider_and_get_wallets(
        WalletsConfig::new(
            Some(num_wallets),   /* "num_wallets" wallets */
            Some(1),             /* Single coin (UTXO) */
            Some(1_000_000_000), /* Amount per coin */
        ),
        None,
        None,
    )
    .await
    .unwrap()
}

pub fn wallets_to_identities(wallets: Vec<WalletUnlocked>) -> Vec<Identity> {
    wallets
        .iter()
        .map(|wallet| Identity::Address(Address::from(wallet.address())))
        .collect()
}

pub async fn deploy_multisig(
    deployer: &WalletUnlocked,
) -> Result<(Bech32ContractId, MultisigCaller), Error> {
    // Deploy the contract
    let multisig_contract_id = Contract::load_from(
        "./multisig-contract/out/debug/fuel-multisig.bin",
        LoadConfiguration::default(),
    )
    .unwrap()
    .deploy(deployer, TxPolicies::default())
    .await
    .unwrap();

    // Create a caller instance
    let deployer = MultisigCaller {
        contract: Multisig::new(multisig_contract_id.clone(), deployer.clone()),
        wallet: deployer.clone(),
    };

    Ok((multisig_contract_id, deployer))
}

pub async fn deploy_counter(
    deployer: &WalletUnlocked,
) -> Result<(Bech32ContractId, CounterCaller), Error> {
    // Deploy the contract
    let counter_contract_id = Contract::load_from(
        "tests/utils/test-contracts/counter/out/debug/counter.bin",
        LoadConfiguration::default(),
    )
    .unwrap()
    .deploy(deployer, TxPolicies::default())
    .await
    .unwrap();

    // Create a caller instance
    let deployer = CounterCaller {
        contract: Counter::new(counter_contract_id.clone(), deployer.clone()),
        wallet: deployer.clone(),
    };

    Ok((counter_contract_id, deployer))
}
