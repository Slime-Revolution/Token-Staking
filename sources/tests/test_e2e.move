#[test_only]
module slime::test_e2e {

    use std::signer;
    use aptos_std::debug::print;
    use aptos_framework::account::create_account_for_test;
    use aptos_framework::aptos_account;
    use aptos_framework::coin;
    use aptos_framework::fungible_asset;
    use aptos_framework::primary_fungible_store;
    use slime::test_helpers::deployer;
    use slime::nft;
    use slime::test_helpers;

    struct TEST {}

    #[test(user_1 = @0xcafe3, user_2 = @0xdead)]
    fun test_create_lock_and_withdraw(user_1: &signer, user_2: &signer) {
        test_helpers::set_up();
        create_account_for_test(signer::address_of(user_1));
        create_account_for_test(signer::address_of(user_2));
        let token_fa = test_helpers::create_fungible_asset_and_mint(b"b", 8, 1000);
        let token_metadata = fungible_asset::metadata_from_asset(&token_fa);
        nft::whitelist_locked_fungible(deployer(), token_metadata, true);
        // Create a lock from an account's primary store.
        let user_1_addr = signer::address_of(user_1);
        primary_fungible_store::deposit(user_1_addr, token_fa);
        assert!(primary_fungible_store::balance(user_1_addr, token_metadata) == 1000, 0);
        let nft_1 = nft::create_lock_fa(user_1, 1000, token_metadata);
        print(&primary_fungible_store::balance(user_1_addr, token_metadata));
        assert!(primary_fungible_store::balance(user_1_addr, token_metadata) == 0, 0);


        let token_coin = test_helpers::create_coin_and_mint<TEST>(deployer(), 500);
        nft::whitelist_locked_coin<TEST>(deployer(), true);

        aptos_account::deposit_coins(signer::address_of(user_2), token_coin);
        assert!(coin::balance<TEST>(signer::address_of(user_2)) == 500, 0);
        let nft_2 = nft::create_lock_coin<TEST>(user_2, 500);
        assert!(coin::balance<TEST>(signer::address_of(user_2)) == 0, 0);

        // Withdraw the locked asset.
        nft::withdraw_coin_entry<TEST>(user_2, nft_2);
        nft::withdraw_fa_entry(user_1, nft_1, token_metadata);
    }
}
