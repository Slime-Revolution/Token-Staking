/// This module defines a struct storing the metadata of the block and new block events.
module slime::nft {
    use aptos_framework::aptos_account;
    use aptos_framework::coin;
    use aptos_framework::event;
    use aptos_framework::fungible_asset::{Self, Metadata, FungibleAsset};
    use aptos_framework::object::{Self, Object, TransferRef, DeleteRef};
    use aptos_framework::primary_fungible_store;
    use aptos_std::smart_table::{Self, SmartTable};
    use aptos_std::smart_vector::{Self, SmartVector};
    use aptos_std::string_utils;
    use aptos_token_objects::collection;
    use aptos_token_objects::royalty::Royalty;
    use aptos_token_objects::token::BurnRef;
    use aptos_token_objects::token;
    use slime::package_manager::{only_operator, format_coin, format_fungible_asset, only_admin, add_balances,
        sub_balances
    };
    use slime::package_manager;
    use std::option;
    use std::signer;
    use std::string::String;
    use std::string;
    use aptos_std::debug::print;
    use aptos_framework::coin::Coin;

    const COLLECTION_NAME: vector<u8> = b"Slime NFT";
    const COLLECTION_DESC: vector<u8> = b"Slime NFT";
    const TOKEN_NAME: vector<u8> = b"SlimeNFT";
    const TOKEN_DESC: vector<u8> = b"Slime NFT";
    const NFT_URI: vector<u8> = b"https://aptos.slimerevolution.com/static/media/";
    const MIN_LOCKUP_EPOCHS: u64 = 2;
    // 2 weeks
    const MAX_LOCKUP_EPOCHS: u64 = 104; // 2 years (52 weeks = 1 year)

    /// The given lockup period is shorter than the minimum allowed.
    const ELOCKUP_TOO_SHORT: u64 = 2;
    /// The given lockup period is longer than the maximum allowed.
    const ELOCKUP_TOO_LONG: u64 = 3;
    /// The given token is not owned by the given signer.
    const ENOT_TOKEN_OWNER: u64 = 4;
    /// The amount to lockup must be more than zero.
    const EINVALID_AMOUNT: u64 = 5;
    /// Invalid whitelist token
    const EINVALID_TOKEN: u64 = 6;

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct SlimeNFT has key {
        locked_amount: u64,
        token: String,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    /// Separate struct in the same resource group as VeCellanaToken to isolate administrative capabilities.
    struct SlimeTokenRefs has key {
        burn_ref: BurnRef,
        transfer_ref: TransferRef,
        delete_ref: DeleteRef,

    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct SlimeCollection has key {
        address: address,
        whitelist_tokens: SmartVector<String>,
        balances: SmartTable<String, u64>
    }

    #[event]
    struct CreateLockEvent has drop, store {
        owner: address,
        amount: u64,
        token: String,
        nft_token: Object<SlimeNFT>
    }

    #[event]
    struct IncreaseAmountEvent has drop, store {
        owner: address,
        old_amount: u64,
        new_amount: u64,
        token: String,
        nft_token: Object<SlimeNFT>
    }

    #[event]
    struct WithdrawEvent has drop, store {
        owner: address,
        amount: u64,
        nft_token: Object<SlimeNFT>
    }

    #[view]
    public fun locked_tokens(token: Object<SlimeNFT>): String acquires SlimeNFT {
        safe_nft_token(&token).token
    }

    #[view]
    public fun locked_amount(token: Object<SlimeNFT>): u64 acquires SlimeNFT {
        safe_nft_token(&token).locked_amount
    }

    #[view]
    public fun nft_collection(): address {
        package_manager::get_collection()
    }

    #[view]
    public fun nft_exists(nft_token: address): bool {
        exists<SlimeNFT>(nft_token)
    }

    fun init_module(_: &signer) {
        let collection_construct_ref = &collection::create_unlimited_collection(
            &package_manager::get_signer(),
            string::utf8(COLLECTION_DESC),
            string::utf8(COLLECTION_NAME),
            option::none<Royalty>(),
            string::utf8(NFT_URI),
        );

        let collection_signer = &object::generate_signer(collection_construct_ref);
        move_to(collection_signer, SlimeCollection {
            address: signer::address_of(collection_signer),
            whitelist_tokens: smart_vector::new(),
            balances: smart_table::new(),
        });
        package_manager::set_collection(signer::address_of(collection_signer));
    }

    public entry fun whitelist_locked_coin<T>(src: &signer, is_accept: bool) acquires SlimeCollection {
        only_operator(src);
        if (is_accept) {
            add_whitelist(format_coin<T>());
        }else {
            remove_whitelist(format_coin<T>());
        }
    }

    public entry fun whitelist_locked_fungible(
        src: &signer,
        token: Object<Metadata>,
        is_accept: bool
    ) acquires SlimeCollection {
        only_operator(src);
        if (is_accept) {
            add_whitelist(format_fungible_asset(token));
            primary_fungible_store::ensure_primary_store_exists(signer::address_of(src), token);
        }else {
            remove_whitelist(format_fungible_asset(token));
        }
    }

    inline fun add_whitelist(token: String) {
        let collection = safe_mut_collection();
        smart_vector::push_back(&mut collection.whitelist_tokens, token);
    }

    inline fun remove_whitelist(token: String) {
        let collection = safe_mut_collection();
        let (exited, index) = smart_vector::index_of(&collection.whitelist_tokens, &token);
        if (exited) {
            smart_vector::remove(&mut collection.whitelist_tokens, index);
        }
    }

    public entry fun create_lock_coin_entry<T>(
        owner: &signer,
        amount: u64,
    ) acquires SlimeCollection {
        create_lock_coin<T>(owner, amount);
    }

    public fun create_lock_coin<T>(
        owner: &signer,
        amount: u64,
    ): Object<SlimeNFT> acquires SlimeCollection {
        asset_whitelisted_token(format_coin<T>());
        deposit_coin_to_pool<T>(coin::withdraw<T>(owner, amount));
        create_lock(amount, format_coin<T>(), signer::address_of(owner))
    }

    public entry fun create_lock_fa_entry(owner: &signer, amount: u64, token: Object<Metadata>) acquires SlimeCollection {
        create_lock_fa(owner, amount, token);
    }

    public fun create_lock_fa(
        owner: &signer,
        amount: u64,
        token: Object<Metadata>
    ): Object<SlimeNFT> acquires SlimeCollection {
        asset_whitelisted_token(format_fungible_asset(token));
        assert!(amount > 0, EINVALID_AMOUNT);
        deposit_fa_to_pool(primary_fungible_store::withdraw(owner, token, amount));
        create_lock(amount, format_fungible_asset(token), signer::address_of(owner))
    }

    fun create_lock(
        amount: u64,
        token: String,
        recipient: address,
    ): Object<SlimeNFT> {
        assert!(amount > 0, EINVALID_AMOUNT);

        // Mint a new veCELL NFT for the lock.
        let cellana_signer = &package_manager::get_signer();
        print(&signer::address_of(cellana_signer));
        let nft_token = &token::create_from_account(
            cellana_signer,
            string::utf8(COLLECTION_NAME),
            string::utf8(TOKEN_DESC),
            string::utf8(TOKEN_NAME),
            // No royalty.
            option::none<Royalty>(),
            string::utf8(NFT_URI),
        );
        let nft_token_signer = &object::generate_signer(nft_token);
        let token_data = SlimeNFT {
            locked_amount: amount,
            token,
        };
        move_to(nft_token_signer, token_data);
        move_to(nft_token_signer, SlimeTokenRefs {
            burn_ref: token::generate_burn_ref(nft_token),
            transfer_ref: object::generate_transfer_ref(nft_token),
            delete_ref: object::generate_delete_ref(nft_token),
        });
        // Transfer the veCELL token to the specified recipient.
        let mutator_ref = token::generate_mutator_ref(nft_token);
        let nft_token = object::object_from_constructor_ref(nft_token);
        let base_uri = string::utf8(NFT_URI);
        string::append(&mut base_uri, string_utils::to_string(&object::object_address(&nft_token)));
        token::set_uri(&mutator_ref, base_uri);
        event::emit(CreateLockEvent { owner: recipient, amount, nft_token, token });
        object::transfer(cellana_signer, nft_token, recipient);
        nft_token
    }

    public entry fun increase_amount_coin_entry<T>(
        owner: &signer,
        nft_token: Object<SlimeNFT>,
        amount: u64,
    ) acquires SlimeNFT {
        assert!(format_coin<T>() == locked_tokens(nft_token), EINVALID_TOKEN);
        deposit_coin_to_pool<T>(coin::withdraw<T>(owner, amount));
        assert!(object::is_owner(nft_token, signer::address_of(owner)), ENOT_TOKEN_OWNER);
        increase_amount_internal(nft_token, amount);
    }

    public entry fun increase_amount_fa_entry(
        owner: &signer,
        nft_token: Object<SlimeNFT>,
        token: Object<Metadata>,
        amount: u64,
    ) acquires SlimeNFT {
        assert!(object::is_owner(nft_token, signer::address_of(owner)), ENOT_TOKEN_OWNER);
        assert!(format_fungible_asset(token) == locked_tokens(nft_token), EINVALID_TOKEN);
        deposit_fa_to_pool(primary_fungible_store::withdraw(owner, token, amount));
        increase_amount_internal(nft_token, amount);
    }

    fun increase_amount_internal(
        nft_token: Object<SlimeNFT>,
        amount: u64,
    ) acquires SlimeNFT {
        // This allows anyone to add to an existing lock.
        let nft_token_data = safe_mut_nft(&nft_token);
        assert!(amount > 0, EINVALID_AMOUNT);
        let old_amount = nft_token_data.locked_amount;
        let new_amount = old_amount + amount;
        nft_token_data.locked_amount = new_amount;

        event::emit(
            IncreaseAmountEvent {
                owner: object::owner(
                    nft_token
                ), old_amount, new_amount, nft_token, token: nft_token_data.token
            },
        );
    }

    public entry fun withdraw_fa_entry(
        owner: &signer,
        nft_token: Object<SlimeNFT>,
        token: Object<Metadata>,
        amount: u64
    ) acquires SlimeNFT, SlimeTokenRefs {
        let amount = withdraw(owner, nft_token, format_fungible_asset(token),amount);
        primary_fungible_store::deposit(
            signer::address_of(owner),
            withdraw_fa_from_pool(token, amount)
        );
    }

    public entry fun withdraw_coin_entry<T>(
        owner: &signer,
        nft_token: Object<SlimeNFT>,
        amount: u64
    ) acquires SlimeNFT, SlimeTokenRefs {
        let amount = withdraw(owner, nft_token, format_coin<T>(), amount);
        aptos_account::deposit_coins(
            signer::address_of(owner),
            withdraw_coin_from_pool<T>(amount)
        );
    }

    fun withdraw(
        owner: &signer,
        nft_token: Object<SlimeNFT>,
        token: String,
        amount: u64
    ): u64 acquires SlimeNFT, SlimeTokenRefs {
        assert!(token == locked_tokens(nft_token), EINVALID_TOKEN);
        if (amount < locked_amount(nft_token)) {
            let token_data = safe_mut_nft(&nft_token);
            token_data.locked_amount = token_data.locked_amount - amount;
            return amount
        };
        let SlimeNFT { locked_amount, token: _ } =
            owner_only_destruct_token(owner, nft_token);
        event::emit(
            WithdrawEvent { owner: signer::address_of(owner), amount: locked_amount, nft_token },
        );
        locked_amount
    }

    /// Can only be called by voting_manager module to disallow transferring veCELL nfts or merging into another
    /// veCELL nft after it has voted in an epoch.
    public(friend) fun freeze_token(nft_token: Object<SlimeNFT>) acquires SlimeTokenRefs {
        let nft_token_data = safe_nft_refs(&nft_token);
        object::disable_ungated_transfer(&nft_token_data.transfer_ref);
    }

    /// Can only be called by voting_manager module to enable transferring veCELL nfts or merging into another
    /// veCELL nft after it has reset its vote in this epoch.
    public(friend) fun unfreeze_token(nft_token: Object<SlimeNFT>) acquires SlimeTokenRefs {
        let nft_token_data = safe_nft_refs(&nft_token);
        object::enable_ungated_transfer(&nft_token_data.transfer_ref);
    }


    inline fun owner_only_destruct_token(
        owner: &signer,
        nft_token: Object<SlimeNFT>,
    ): SlimeNFT acquires SlimeNFT, SlimeTokenRefs {
        assert!(object::is_owner(nft_token, signer::address_of(owner)), ENOT_TOKEN_OWNER);
        let nft_token_addr = object::object_address(&nft_token);
        let token_data = move_from<SlimeNFT>(nft_token_addr);

        // Burn the token and delete the object.
        let SlimeTokenRefs { burn_ref, transfer_ref: _, delete_ref: _ } = move_from<SlimeTokenRefs>(nft_token_addr);

        token::burn(burn_ref);
        token_data
    }

    inline fun increase_amount(
        token: String,
        amount: u64,
    ) acquires SlimeCollection {
        let balances = &mut safe_mut_collection().balances;
        let balance = smart_table::borrow_mut_with_default(balances, token, 0);
        *balance = *balance + amount;
    }

    inline fun decrease_amount(
        token: String,
        amount: u64,
    ) acquires SlimeCollection {
        let balances = &mut safe_mut_collection().balances;
        let balance = smart_table::borrow_mut(balances, token);
        if (*balance < amount) {
            *balance = 0;
        } else {
            *balance = *balance - amount;
        }
    }

    inline fun owner_only_mut_nft_token(
        owner: &signer,
        nft_token: Object<SlimeNFT>,
    ): &mut SlimeNFT acquires SlimeNFT {
        assert!(object::is_owner(nft_token, signer::address_of(owner)), ENOT_TOKEN_OWNER);
        safe_mut_nft(&nft_token)
    }

    inline fun safe_nft_token(nft_token: &Object<SlimeNFT>): &SlimeNFT acquires SlimeNFT {
        borrow_global<SlimeNFT>(object::object_address(nft_token))
    }

    inline fun safe_mut_nft(ve_token: &Object<SlimeNFT>): &mut SlimeNFT acquires SlimeNFT {
        borrow_global_mut<SlimeNFT>(object::object_address(ve_token))
    }

    inline fun safe_nft_refs(nft_token: &Object<SlimeNFT>): &SlimeTokenRefs acquires SlimeTokenRefs {
        borrow_global<SlimeTokenRefs>(object::object_address(nft_token))
    }

    inline fun asset_whitelisted_token(token: String) {
        let collection = safe_collection();
        assert!(smart_vector::contains(&collection.whitelist_tokens, &token), EINVALID_TOKEN);
    }

    inline fun safe_collection(): &SlimeCollection acquires SlimeCollection {
        borrow_global<SlimeCollection>(nft_collection())
    }

    inline fun safe_mut_collection(): &mut SlimeCollection acquires SlimeCollection {
        borrow_global_mut<SlimeCollection>(nft_collection())
    }

    // Emergency function
    inline fun deposit_fa_to_pool(token: FungibleAsset) {
        add_balances(
            format_fungible_asset(fungible_asset::metadata_from_asset(&token)),
            fungible_asset::amount(&token)
        );
        primary_fungible_store::deposit(package_manager::get_address(), token);
    }

    inline fun deposit_coin_to_pool<T>(token: Coin<T>) {
        add_balances(format_coin<T>(), coin::value(&token));
        aptos_account::deposit_coins(package_manager::get_address(), token);
    }

    inline fun withdraw_fa_from_pool(token: Object<Metadata>, amount: u64): FungibleAsset {
        sub_balances(format_fungible_asset(token), amount);
        primary_fungible_store::withdraw(&package_manager::get_signer(), token, amount)
    }

    inline fun withdraw_coin_from_pool<T>(amount: u64): Coin<T> {
        sub_balances(format_coin<T>(), amount);
        coin::withdraw(&package_manager::get_signer(), amount)
    }

    public entry fun emergency_treasury_withdraw(owner: &signer) {
        only_admin(owner);
    }

    #[test_only]
    public fun init_for_test(_deployer: &signer) {
        init_module(_deployer);
    }
}
