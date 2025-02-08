/*
#[test_only]
module hacksuimer_contract::hacksuimer_contract_tests;
// uncomment this line to import the module
// use hacksuimer_contract::hacksuimer_contract;

const ENotImplemented: u64 = 0;

#[test]
fun test_hacksuimer_contract() {
    // pass
}

#[test, expected_failure(abort_code = ::hacksuimer_contract::hacksuimer_contract_tests::ENotImplemented)]
fun test_hacksuimer_contract_fail() {
    abort ENotImplemented
}
*/

#[test_only]
module hacksuimer_contract::hacksuimer_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::clock::{Self, Clock};
    use sui::balance;
    use sui::sui::SUI;
    use hacksuimer_contract::hacksuimer::{Self, HackathonEvent, Proposal};

    // 测试常量
    const CREATOR: address = @0xCAFE;
    const USER1: address = @0x123;
    const USER2: address = @0x456;
    const JUDGE1: address = @0x789;
    const JUDGE2: address = @0x101;

    // 辅助函数：创建测试场景
    fun create_test_scenario(): Scenario {
        ts::begin(CREATOR)
    }

    // 辅助函数：创建测试用 Clock
    fun create_test_clock(scenario: &mut Scenario): Clock {
        ts::next_tx(scenario, CREATOR);
        clock::create_for_testing(ts::ctx(scenario))
    }
    fun set_hackathon_status(scenario: &mut Scenario, status: u8) {
        ts::next_tx(scenario, CREATOR);
        let mut hackathon = ts::take_shared<HackathonEvent>(scenario);
        hacksuimer::set_status_for_testing(&mut hackathon, status);
        ts::return_shared(hackathon);
    }


    // 辅助函数：创建黑客松活动
    fun create_test_hackathon(scenario: &mut Scenario, clock: &Clock) {
        let name = b"Test Hackathon";
        let description = b"Test Description";
        let image_url = std::option::none();
        let contact_info = std::option::none();
        let reward_description = b"Test Rewards";
        let evaluation_criteria = std::option::none();
        
        // 设置当前时间作为开始时间
        let current_time = clock::timestamp_ms(clock);
        let start_time = current_time;  // 立即开始
        let voting_delay = 10000;
        let voting_period = 5000;
        let proposals_per_user = 2;
        let max_proposal_count = 10;
        
        let mut judges = vector::empty();
        vector::push_back(&mut judges, JUDGE1);
        vector::push_back(&mut judges, JUDGE2);
        
        let mut judge_vote_limits = vector::empty();
        vector::push_back(&mut judge_vote_limits, 100);
        vector::push_back(&mut judge_vote_limits, 100);

        ts::next_tx(scenario, CREATOR);
        hacksuimer::create_hacksuimer_event(
            name,
            description,
            image_url,
            contact_info,
            reward_description,
            evaluation_criteria,
            start_time,
            voting_delay,
            voting_period,
            proposals_per_user,
            max_proposal_count,
            judges,
            judge_vote_limits,
            ts::ctx(scenario)
        );
    }

    #[test]
    fun test_create_hackathon() {
        let mut scenario = create_test_scenario();
        let clock = create_test_clock(&mut scenario);
        
        // 创建黑客松活动
        create_test_hackathon(&mut scenario, &clock);
        
        // 验证活动已创建
        ts::next_tx(&mut scenario, USER1);
        {
            assert!(ts::has_most_recent_shared<HackathonEvent>(), 0);
        };
        
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_submit_proposal() {
        let mut scenario = create_test_scenario();
        let clock = create_test_clock(&mut scenario);
        
        create_test_hackathon(&mut scenario, &clock);
        // 设置活动状态为 ACTIVE
        set_hackathon_status(&mut scenario, 1); // STATE_ACTIVE
        
        ts::next_tx(&mut scenario, USER1);
        {
            let mut hackathon = ts::take_shared<HackathonEvent>(&scenario);
            assert!(hacksuimer::get_hackathon_status(&hackathon) == 1, 0);
            
            hacksuimer::submit_proposal(
                &mut hackathon,
                b"Test Project",
                b"Test Project Description",
                b"https://github.com/test",
                &clock,
                ts::ctx(&mut scenario)
            );
            ts::return_shared(hackathon);
        };
        
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = hacksuimer::EMaxProposalsPerUserReached)]
    fun test_submit_proposal_limit() {
        let mut scenario = create_test_scenario();
        let clock = create_test_clock(&mut scenario);
        
        create_test_hackathon(&mut scenario, &clock);
        set_hackathon_status(&mut scenario, 1); // 设置为 ACTIVE
        
        ts::next_tx(&mut scenario, USER1);
        {
            let mut hackathon = ts::take_shared<HackathonEvent>(&scenario);
            // 提交超过限制的提案
            hacksuimer::submit_proposal(
                &mut hackathon,
                b"Project 1",
                b"Description 1",
                b"https://github.com/test1",
                &clock,
                ts::ctx(&mut scenario)
            );
            hacksuimer::submit_proposal(
                &mut hackathon,
                b"Project 2",
                b"Description 2",
                b"https://github.com/test2",
                &clock,
                ts::ctx(&mut scenario)
            );
            // 第三个提案应该失败
            hacksuimer::submit_proposal(
                &mut hackathon,
                b"Project 3",
                b"Description 3",
                b"https://github.com/test3",
                &clock,
                ts::ctx(&mut scenario)
            );
            ts::return_shared(hackathon);
        };
        
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_judge_vote() {
        let mut scenario = create_test_scenario();
        let clock = create_test_clock(&mut scenario);
        
        create_test_hackathon(&mut scenario, &clock);
        set_hackathon_status(&mut scenario, 1); // 设置为 ACTIVE 以提交提案
        
        // 提交提案
        ts::next_tx(&mut scenario, USER1);
        {
            let mut hackathon = ts::take_shared<HackathonEvent>(&scenario);
            hacksuimer::submit_proposal(
                &mut hackathon,
                b"Test Project",
                b"Description",
                b"https://github.com/test",
                &clock,
                ts::ctx(&mut scenario)
            );
            ts::return_shared(hackathon);
        };
        
        set_hackathon_status(&mut scenario, 2); // 设置为 VOTING
        
        // 评委投票
        ts::next_tx(&mut scenario, JUDGE1);
        {
            let mut hackathon = ts::take_shared<HackathonEvent>(&scenario);
            let mut proposal = ts::take_shared<Proposal>(&scenario);
            hacksuimer::judge_vote(
                &mut hackathon,
                &mut proposal,
                50,
                b"Good project!",
                &clock,
                ts::ctx(&mut scenario)
            );
            ts::return_shared(hackathon);
            ts::return_shared(proposal);
        };
        
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_community_vote() {
        let mut scenario = create_test_scenario();
        let mut clock = create_test_clock(&mut scenario);
        
        create_test_hackathon(&mut scenario, &clock);
        
        // 首先设置状态为 ACTIVE 以允许提交提案
        set_hackathon_status(&mut scenario, 1); // STATE_ACTIVE
        
        // 提交提案
        ts::next_tx(&mut scenario, USER1);
        {
            let mut hackathon = ts::take_shared<HackathonEvent>(&scenario);
            hacksuimer::submit_proposal(
                &mut hackathon,
                b"Test Project",
                b"Description",
                b"https://github.com/test",
                &clock,
                ts::ctx(&mut scenario)
            );
            ts::return_shared(hackathon);
        };
        
        // 将状态设置为 VOTING 以允许投票
        set_hackathon_status(&mut scenario, 2); // STATE_VOTING
        
        // 社区投票
        ts::next_tx(&mut scenario, USER2);
        {
            let mut hackathon = ts::take_shared<HackathonEvent>(&scenario);
            let mut proposal = ts::take_shared<Proposal>(&scenario);
            let wallet_balance = balance::create_for_testing<SUI>(2_000_000_000); // 2 SUI
            
            hacksuimer::community_vote(
                &mut hackathon,
                &mut proposal,
                &wallet_balance,
                ts::ctx(&mut scenario)
            );
            
            balance::destroy_for_testing(wallet_balance);
            ts::return_shared(hackathon);
            ts::return_shared(proposal);
        };
        
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_end_hackathon() {
        let mut scenario = create_test_scenario();
        let mut clock = create_test_clock(&mut scenario);
        
        create_test_hackathon(&mut scenario, &clock);
        
        // 设置时间到结束时间之后
        clock::set_for_testing(&mut clock, 20000); // 设置时间超过 end_time
        
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut hackathon = ts::take_shared<HackathonEvent>(&scenario);
            hacksuimer::end_hackathon(
                &mut hackathon,
                &clock,
                ts::ctx(&mut scenario)
            );
            ts::return_shared(hackathon);
        };
        
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

}