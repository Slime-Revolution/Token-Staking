module slime::package_manager {
    use std::signer;
    use std::string;
    use std::string::String;
    use aptos_std::simple_map::SimpleMap;
    use aptos_std::smart_table;
    use aptos_std::smart_table::SmartTable;
    use aptos_std::string_utils;
    use aptos_std::type_info;
    use aptos_framework::account;
    use aptos_framework::fungible_asset::Metadata;
    use aptos_framework::object::{Self, ExtendRef, Object};

    const GLOBAL_STATE_NAME: vector<u8> = b"meso::global_state";
    /// Only Admin can call this function.
    const ADMIN: u64 = 1;
    /// Only Operator can call this function.
    const OPERATOR: u64 = 2;
    friend slime::nft;

    #[view]
    public fun treasury_addr(): address acquires GlobalState {
        borrow_global<GlobalState>(get_address()).treasury
    }


    #[view]
    public fun balances(): SimpleMap<String,u64> acquires GlobalState {
        let global_state = borrow_global<GlobalState>(get_address());
        smart_table::to_simple_map(&global_state.balances)
    }

    #[view]
    public fun get_address(): address {
        object::create_object_address(&@slime, GLOBAL_STATE_NAME)
    }

    #[view]
    public fun get_collection(): address acquires GlobalState {
        borrow_global<GlobalState>(get_address()).collection_addr
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct GlobalState has key {
        extend_ref: ExtendRef,
        admin: address,
        operator: address,
        new_admin: address,
        collection_addr: address,
        treasury: address,
        balances: SmartTable<String, u64>,
    }

    fun init_module(meso_signer: &signer) {
        let global_state = &object::create_named_object(meso_signer, GLOBAL_STATE_NAME);
        let global_state_signer = &object::generate_signer(global_state);
        account::create_account_if_does_not_exist(signer::address_of(global_state_signer));
        move_to(global_state_signer, GlobalState {
            extend_ref: object::generate_extend_ref(global_state),
            admin: @deployer,
            operator: @deployer,
            new_admin: @0x0,
            collection_addr: @0x0,
            treasury: @deployer,
            balances: smart_table::new(),
        });
    }

    public(friend) fun add_balances(name: String, amount: u64) acquires GlobalState {
        let global_state = borrow_global_mut<GlobalState>(get_address());
        let balance = smart_table::borrow_mut_with_default(&mut global_state.balances, name, 0);
        *balance = *balance + amount;
    }

    public(friend) fun sub_balances(name: String, amount: u64) acquires GlobalState {
        let global_state = borrow_global_mut<GlobalState>(get_address());
        let balance = smart_table::borrow_mut_with_default(&mut global_state.balances, name, 0);
        assert!(*balance >= amount, 1);
        *balance = *balance - amount;
    }

    public entry fun set_treasury(src: &signer, treasury: address) acquires GlobalState {
        only_admin(src);
        let permission_config = borrow_global_mut<GlobalState>(get_address());
        permission_config.treasury = treasury;
    }

    public(friend) fun set_collection(collection_addr: address) acquires GlobalState {
        let permission_config = borrow_global_mut<GlobalState>(get_address());
        permission_config.collection_addr = collection_addr;
    }

    public(friend) fun only_admin(src: &signer) acquires GlobalState {
        let permission_config = borrow_global<GlobalState>(get_address());
        assert!(signer::address_of(src) == permission_config.admin, ADMIN);
    }

    public(friend) fun only_operator(src: &signer) acquires GlobalState {
        let permission_config = borrow_global<GlobalState>(get_address());
        assert!(signer::address_of(src) == permission_config.operator, OPERATOR);
    }

    public entry fun set_admin(src: &signer, admin: address) acquires GlobalState {
        only_admin(src);
        let permission_config = borrow_global_mut<GlobalState>(get_address());
        permission_config.new_admin = admin;
    }

    public entry fun accept_admin(src: &signer) acquires GlobalState {
        let permission_config = borrow_global_mut<GlobalState>(get_address());
        assert!(permission_config.new_admin != @0x0, 3);
        assert!(signer::address_of(src) == permission_config.new_admin, ADMIN);
        permission_config.admin = permission_config.new_admin;
        permission_config.new_admin = @0x0;
    }

    public entry fun set_operator(src: &signer, operator: address) acquires GlobalState {
        only_admin(src);
        let permission_config = borrow_global_mut<GlobalState>(get_address());
        permission_config.operator = operator;
    }

    public(friend) fun get_signer(): signer acquires GlobalState {
        object::generate_signer_for_extending(&borrow_global<GlobalState>(get_address()).extend_ref)
    }

    public fun format_coin<CoinType>(): String {
        type_info::type_name<CoinType>()
    }

    public fun format_fungible_asset(fungible_asset: Object<Metadata>): String {
        let fa_address = object::object_address(&fungible_asset);
        // This will create "@0x123"
        let fa_address_str = string_utils::to_string(&fa_address);
        // We want to strip the prefix "@"
        string::sub_string(&fa_address_str, 1, string::length(&fa_address_str))
    }

    #[test_only]
    friend slime::test_helpers;
    #[test_only]
    public fun initialize_for_test(deployer: &signer) {
        init_module(deployer);
    }
}
