#[test_only]
module hacksuimer_contract::test_profile_nft {
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use std::string::{Self};
    use hacksuimer_contract::profile_nft::{Self, ProfileNFT};
    use sui::object::{Self, ID};

    // Test addresses
    const ADMIN: address = @0xAD;
    const USER: address = @0xB0B;

    // Helper to set up test scenario
    fun create_profile_scenario(): Scenario {
        let mut scenario = test::begin(@0xAD);
        next_tx(&mut scenario, ADMIN);
        {
            profile_nft::create_profile(
                string::utf8(b"Test Profile"),
                b"http://example.com/image.png",
                ctx(&mut scenario)
            );
        };
        scenario
    }

    #[test]
    fun test_create_profile_success() {
        let mut scenario = test::begin(@0xAD);
        next_tx(&mut scenario, ADMIN);
        {
            profile_nft::create_profile(
                string::utf8(b"Test Profile"),
                b"http://example.com/image.png",
                ctx(&mut scenario)
            );
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = profile_nft::EINVALID_NAME)]
    fun test_create_profile_empty_name() {
        let mut scenario = test::begin(@0xAD);
        next_tx(&mut scenario, ADMIN);
        {
            profile_nft::create_profile(
                string::utf8(b""),
                b"http://example.com/image.png",
                ctx(&mut scenario)
            );
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = profile_nft::EINVALID_IMAGE)]
    fun test_create_profile_empty_image() {
        let mut scenario = test::begin(@0xAD);
        next_tx(&mut scenario, ADMIN);
        {
            profile_nft::create_profile(
                string::utf8(b"Test Profile"),
                b"",
                ctx(&mut scenario)
            );
        };
        test::end(scenario);
    }

    #[test]
    fun test_add_achievement_success() {
        let mut scenario = create_profile_scenario();
        next_tx(&mut scenario, ADMIN);
        {
            let mut profile = test::take_from_sender<ProfileNFT>(&scenario);
            profile_nft::add_achievement(
                &mut profile,
                string::utf8(b"Test Achievement"),
                string::utf8(b"Description"),
                ctx(&mut scenario)
            );
            test::return_to_sender(&scenario, profile);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = profile_nft::ENO_PERMISSION)]
    fun test_add_achievement_no_permission() {
        let mut scenario = create_profile_scenario();
        next_tx(&mut scenario, USER);
        {
            let mut profile = test::take_from_address<ProfileNFT>(&scenario, ADMIN);
            profile_nft::add_achievement(
                &mut profile,
                string::utf8(b"Test Achievement"),
                string::utf8(b"Description"),
                ctx(&mut scenario)
            );
            test::return_to_address(ADMIN, profile);
        };
        test::end(scenario);
    }

    #[test]
    fun test_view_achievements() {
        let mut scenario = create_profile_scenario();
        next_tx(&mut scenario, ADMIN);
        {
            let profile = test::take_from_sender<ProfileNFT>(&scenario);
            let achievements = profile_nft::view_achievements(&profile);
            assert!(std::vector::length(achievements) == 0, 0);
            test::return_to_sender(&scenario, profile);
        };
        test::end(scenario);
    }

    #[test]
    fun test_update_rank_success() {
        let mut scenario = create_profile_scenario();
        next_tx(&mut scenario, ADMIN);
        {
            let mut profile = test::take_from_sender<ProfileNFT>(&scenario);
            profile_nft::update_rank(&mut profile, 10, ctx(&mut scenario));
            test::return_to_sender(&scenario, profile);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = profile_nft::ENO_PERMISSION)]
    fun test_update_rank_no_permission() {
        let mut scenario = create_profile_scenario();
        next_tx(&mut scenario, USER);
        {
            let mut profile = test::take_from_address<ProfileNFT>(&scenario, ADMIN);
            profile_nft::update_rank(&mut profile, 100, ctx(&mut scenario));
            test::return_to_address(ADMIN, profile);
        };
        test::end(scenario);
    }


    #[test]
    fun test_add_project_success() {
        let mut scenario = create_profile_scenario();
        next_tx(&mut scenario, ADMIN);
        {
            let mut profile = test::take_from_sender<ProfileNFT>(&scenario);
            profile_nft::add_project(
                &mut profile,
                object::id_from_address(@0x1),
                object::id_from_address(@0x2),
                100,
                ctx(&mut scenario)
            );
            test::return_to_sender(&scenario, profile);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = profile_nft::ENO_PERMISSION)]
    fun test_add_project_no_permission() {
        let mut scenario = create_profile_scenario();
        next_tx(&mut scenario, USER);
        {
            let mut profile = test::take_from_address<ProfileNFT>(&scenario, ADMIN);
            profile_nft::add_project(
                &mut profile,
                object::id_from_address(@0x1),
                object::id_from_address(@0x2),
                100,
                ctx(&mut scenario)
            );
            test::return_to_address(ADMIN, profile);
        };
        test::end(scenario);
    }
}