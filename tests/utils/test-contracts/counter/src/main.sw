contract;
 
abi TestContract {
	#[storage(write)]
	fn initialize_counter(value: u64);
 
	#[storage(read, write)]
	fn increment_counter(amount: u64);

    #[storage(read)]
    fn get_counter() -> u64;
}
 
storage {
	counter: u64 = 0,
}
 
impl TestContract for Contract {
	#[storage(write)]
	fn initialize_counter(value: u64) {
		storage.counter.write(value);
	}
 
	#[storage(read, write)]
	fn increment_counter(amount: u64) {
		let incremented = storage.counter.read() + amount;
		storage.counter.write(incremented);
	}

    #[storage(read)]
    fn get_counter() -> u64 {
        storage.counter.read()
    }
}