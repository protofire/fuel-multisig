use fuels::types::Identity;
use fuels::{prelude::*, types::ContractId};

// Load abi from json
abigen!(Contract(
    name = "MyContract",
    abi = "out/debug/fuel-multisig-abi.json"
));

async fn get_contract_instance() -> (MyContract<WalletUnlocked>, ContractId) {
    // Launch a local network and deploy the contract
    let mut wallets = launch_custom_provider_and_get_wallets(
        WalletsConfig::new(
            Some(1),             /* Single wallet */
            Some(1),             /* Single coin (UTXO) */
            Some(1_000_000_000), /* Amount per coin */
        ),
        None,
        None,
    )
    .await
    .unwrap();
    let wallet = wallets.pop().unwrap();

    let id = Contract::load_from(
        "./out/debug/fuel-multisig.bin",
        LoadConfiguration::default(),
    )
    .unwrap()
    .deploy(&wallet, TxPolicies::default())
    .await
    .unwrap();

    let instance = MyContract::new(id.clone(), wallet);

    (instance, id.into())
}

async fn get_wallets(num_wallets: u64) -> Vec<WalletUnlocked> {
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

fn wallets_to_identities(wallets: Vec<WalletUnlocked>) -> Vec<Identity> {
    wallets
        .iter()
        .map(|wallet| Identity::Address(Address::from(wallet.address())))
        .collect()
}

#[tokio::test]
async fn deploy_contract() {
    let wallets = get_wallets(2).await;
    let owners_list = wallets_to_identities(wallets);
    let threshold = 2;

    let (contract_instance, _id) = get_contract_instance().await;
    let result = contract_instance
        .methods()
        .constructor(threshold, owners_list.clone())
        .call()
        .await
        .unwrap();
    let contract_owners = contract_instance
        .methods()
        .get_owners()
        .call()
        .await
        .unwrap()
        .value;

    assert_eq!(contract_owners.len() as u64, 2);
    assert_eq!(contract_owners, owners_list);
}
