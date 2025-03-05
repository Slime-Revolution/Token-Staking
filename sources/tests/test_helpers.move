#[test_only]
module slime::test_helpers {
    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::fungible_asset::{Self, FungibleAsset};
    use aptos_framework::object;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;
    use std::option;
    use std::signer;
    use std::string;
    use std::vector;
    use slime::nft;
    use slime::package_manager;

    const GENESIS_EPOCH: u64 = 100;

    public fun set_up() {
        timestamp::set_time_has_started_for_testing(&account::create_signer_for_test(@0x1));
        // Bump starting epoch to GENESIS_EPOCH so we don't start at epoch 0, which is impossible in practice.
        package_manager::initialize_for_test(deployer());
        nft::init_for_test(deployer());
    }

    public fun genesis_epoch(): u64 {
        GENESIS_EPOCH
    }

    public fun clean_up(assets: vector<FungibleAsset>) {
        let deployer_addr = signer::address_of(deployer());
        vector::for_each(assets, |a| primary_fungible_store::deposit(deployer_addr, a));
    }

    public inline fun deployer(): &signer {
        &account::create_signer_for_test(@0xcafe)
    }

    public fun create_fungible_asset_and_mint(name: vector<u8>, decimals:  u8, amount: u64): FungibleAsset {
        let token_metadata = &object::create_named_object(deployer(), name);
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            token_metadata,
            option::none(),
            string::utf8(name),
            string::utf8(name),
            decimals,
            string::utf8(b""),
            string::utf8(b""),
        );
        let mint_ref = &fungible_asset::generate_mint_ref(token_metadata);
        fungible_asset::mint(mint_ref, amount)
    }

    public fun create_coin_and_mint<CoinType>(creator: &signer, amount: u64): Coin<CoinType> {
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<CoinType>(
            creator,
            string::utf8(b"Test"),
            string::utf8(b"Test"),
            8,
            true,
        );
        let coin = coin::mint<CoinType>(amount, &mint_cap);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_freeze_cap(freeze_cap);
        coin::destroy_mint_cap(mint_cap);
        coin
    }

    public fun in_range(value: u64, min: u64, max: u64): bool {
        value >= min && value <= max
    }

    public fun advance_time(seconds: u64) {
        timestamp::fast_forward_seconds(seconds);
    }
}
