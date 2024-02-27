mod utils;

use fuels::types::Identity;
use fuels::{prelude::*, types::ContractId};

use crate::utils::setup::{
    base_asset_contract_id, call_parameters, deploy_counter, deploy_multisig, get_wallets,
    transfer_parameters, wallets_to_identities, DEFAULT_TRANSFER_AMOUNT,
};

// Load abi from json
abigen!(Contract(
    name = "Multisig",
    abi = "./multisig-contract/out/debug/fuel-multisig-abi.json"
));

async fn get_contract_instance() -> (Multisig<WalletUnlocked>, ContractId) {
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
        "./multisig-contract/out/debug/fuel-multisig.bin",
        LoadConfiguration::default(),
    )
    .unwrap()
    .deploy(&wallet, TxPolicies::default())
    .await
    .unwrap();

    let instance = Multisig::new(id.clone(), wallet);

    (instance, id.into())
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

#[tokio::test]
async fn propose_call_tx() {
    let mut wallets = get_wallets(3).await;
    let owners_list = wallets_to_identities(wallets[0..2].to_vec());
    let mut wallets: &mut [WalletUnlocked] = wallets.as_mut_slice();
    let threshold = 1;

    // Deploy the counter contract
    let (counter_contract_id, counter_deployer) = deploy_counter(&wallets[0]).await.unwrap();

    // Deploy the multisig contract
    let (contract_id, deployer) = deploy_multisig(&wallets[0]).await.unwrap();

    // Call the multisig constructor
    let constructor_result = deployer
        .contract
        .methods()
        .constructor(threshold, owners_list.clone())
        .call()
        .await
        .unwrap();

    // Transfer some funds to the contract
    deployer
        .wallet
        .force_transfer_to_contract(
            deployer.contract.contract_id(),
            DEFAULT_TRANSFER_AMOUNT,
            BASE_ASSET_ID,
            TxPolicies::default(),
        )
        .await
        .unwrap();

    // Check counter pre-call
    let initial_counter_value = counter_deployer
        .contract
        .methods()
        .get_counter()
        .call()
        .await
        .unwrap()
        .value;
    println!("Initial counter value: {:?}", initial_counter_value);

    // Get call parameters
    let transaction_parameters = call_parameters();

    // Propose a call tx
    let response = deployer
        .contract
        .methods()
        .propose_tx(
            Identity::ContractId(counter_contract_id.clone().into()),
            transaction_parameters.clone(),
        )
        .call()
        .await
        .unwrap();

    // let proposed_tx_log = response.decode_logs();
    // println!("Proposed tx log: {:?}", proposed_tx_log);
    println!("Proposed tx_id: {:?}", response.value);

    /*
    let active_tx_list = deployer
        .contract
        .methods()
        .get_active_tx_ids()
        .call()
        .await
        .unwrap()
        .value;
    println!("Active tx list: {:?}", active_tx_list);

    let tx = deployer
        .contract
        .methods()
        .get_tx(response.value)
        .call()
        .await
        .unwrap()
        .value
        .unwrap();
    println!("Proposed tx: {:?}", tx);

    let tx_calldata = deployer
        .contract
        .methods()
        .get_tx_calldata(response.value)
        .call()
        .await
        .unwrap()
        .value;

    println!("Proposed tx calldata: {:?}", tx_calldata);

    let tx_function_selector = deployer
        .contract
        .methods()
        .get_tx_function_selector(response.value)
        .call()
        .await
        .unwrap()
        .value;
    println!("Proposed tx function selector: {:?}", tx_function_selector);
    */

    // Execute the call tx because the threshold is 1
    let response = deployer
        .contract
        .methods()
        .execute_tx(response.value)
        .append_contract(counter_contract_id.into())
        .call()
        .await;

    match response {
        Ok(response) => {
            // let execute_tx_log = response.decode_logs();
            // println!("Execute tx log: {:?}", execute_tx_log);
            println!("Call tx executed successfully");
        }
        Err(e) => {
            println!("Error executing transfer tx: {:?}", e);
        }
    }
    // Check counter post-call
    let final_counter_value = counter_deployer
        .contract
        .methods()
        .get_counter()
        .call()
        .await
        .unwrap()
        .value;
    println!("Final counter value: {:?}", final_counter_value);

    assert_eq!(initial_counter_value, 0);
    assert_eq!(final_counter_value, initial_counter_value + 5);
}

#[tokio::test]
async fn propose_transfer_tx() {
    let mut wallets = get_wallets(3).await;
    let owners_list = wallets_to_identities(wallets[0..2].to_vec());
    let mut wallets: &mut [WalletUnlocked] = wallets.as_mut_slice();
    let threshold = 1;

    // Deploy the contract
    let (contract_id, deployer) = deploy_multisig(&wallets[0]).await.unwrap();

    // Call the constructor
    let constructor_result = deployer
        .contract
        .methods()
        .constructor(threshold, owners_list.clone())
        .call()
        .await
        .unwrap();

    // Transfer some funds to the contract
    deployer
        .wallet
        .force_transfer_to_contract(
            deployer.contract.contract_id(),
            DEFAULT_TRANSFER_AMOUNT,
            BASE_ASSET_ID,
            TxPolicies::default(),
        )
        .await
        .unwrap();

    // Check balances pre-transfer
    let initial_contract_balance = deployer
        .wallet
        .provider()
        .unwrap()
        .get_contract_asset_balance(&deployer.contract.contract_id(), base_asset_contract_id())
        .await
        .unwrap();

    println!("Initial contract balance: {:?}", initial_contract_balance);

    // Get transfer parameters
    let (receiver_wallet, receiver, transaction_parameters) = transfer_parameters();

    let initial_receiver_balance = deployer
        .wallet
        .provider()
        .unwrap()
        .get_asset_balance(receiver_wallet.address(), BASE_ASSET_ID)
        .await
        .unwrap();
    println!("Initial receiver balance: {:?}", initial_receiver_balance);

    // Propose a transfer tx
    let response = deployer
        .contract
        .methods()
        .propose_tx(receiver, transaction_parameters.clone())
        .call()
        .await
        .unwrap();

    let proposed_tx_log = response.decode_logs();
    println!("Proposed tx log: {:?}", proposed_tx_log);
    println!("Proposed tx_id: {:?}", response.value);

    let active_tx_list = deployer
        .contract
        .methods()
        .get_active_tx_ids()
        .call()
        .await
        .unwrap()
        .value;
    println!("Active tx list: {:?}", active_tx_list);

    let tx = deployer
        .contract
        .methods()
        .get_tx(response.value)
        .call()
        .await
        .unwrap()
        .value
        .unwrap();
    println!("Proposed tx: {:?}", tx);

    // Execute the transfer tx because the threshold is 1
    let response = deployer
        .contract
        .methods()
        .execute_tx(response.value)
        .append_variable_outputs(1)
        .call()
        .await;

    match response {
        Ok(_) => {
            println!("Transfer tx executed successfully");
        }
        Err(e) => {
            println!("Error executing transfer tx: {:?}", e);
        }
    }

    // check balances post-transfer
    let final_contract_balance = deployer
        .wallet
        .provider()
        .unwrap()
        .get_contract_asset_balance(&deployer.contract.contract_id(), base_asset_contract_id())
        .await
        .unwrap();
    let final_receiver_balance = deployer
        .wallet
        .provider()
        .unwrap()
        .get_asset_balance(receiver_wallet.address(), BASE_ASSET_ID)
        .await
        .unwrap();

    assert_eq!(initial_contract_balance, DEFAULT_TRANSFER_AMOUNT);
    assert_eq!(initial_receiver_balance, 0);

    assert_eq!(final_contract_balance, 0);
    assert_eq!(final_receiver_balance, DEFAULT_TRANSFER_AMOUNT);

    assert!(final_contract_balance < initial_contract_balance);
    assert!(final_receiver_balance > initial_receiver_balance);
}
