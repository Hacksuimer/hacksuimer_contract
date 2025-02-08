// Hacksuimer 黑客松合约逻辑说明：
//
// 1. 合约结构
//    - HackathonEvent: 黑客松活动主体，存储活动配置和状态
//    - Proposal: 参赛项目，包含项目信息和得分
//    - JudgeComment: 评委评论，记录评价内容和时间
//
// 2. 活动状态流程
//    - 未开始 (STATE_NOT_STARTED)
//    - 活动中 (STATE_ACTIVE)：接受项目提交
//    - 投票中 (STATE_VOTING)：评委和社区投票
//    - 已结束 (STATE_ENDED)
//
// 3. 投票机制
//    - 评委投票：每个评委有固定票数限制
//    - 社区投票：根据钱包SUI余额决定票数(1 SUI = 1票)
//    - 评委可以对项目进行评论
//
// 4. 限制控制
//    - 每位用户的提案数量限制
//    - 活动总提案数量限制
//    - 评委投票额度限制
//    - 社区投票最小金额限制
//
// 5. 安全机制
//    - 活动状态检查
//    - 权限控制（创建者、评委）
//    - 时间控制（开始、结束）
//    - 投票额度控制
//
// Hacksuimer Contract Logic:
//
// 1. Contract Structure
//    - HackathonEvent: Main event object, stores event configuration and status
//    - Proposal: Project submission, contains project info and scores
//    - JudgeComment: Judge comments, records evaluation content and timestamp
//
// 2. Event Status Flow
//    - Not Started (STATE_NOT_STARTED)
//    - Active (STATE_ACTIVE): Accepting project submissions
//    - Voting (STATE_VOTING): Judge and community voting
//    - Ended (STATE_ENDED)
//
// 3. Voting Mechanism
//    - Judge Voting: Each judge has a fixed vote limit
//    - Community Voting: Based on wallet SUI balance (1 SUI = 1 vote)
//    - Judges can comment on projects
//
// 4. Limitation Controls
//    - Proposal limit per user
//    - Total proposal limit
//    - Judge voting limit
//    - Minimum community vote amount
//
// 5. Security Mechanisms
//    - Event status validation
//    - Permission control (creator, judges)
//    - Time control (start, end)
//    - Vote limit control

module hacksuimer_contract::hacksuimer {
    use std::string::{Self, String};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::table::{Self, Table};
    use sui::url::{Self, Url};
    use sui::clock::{Self, Clock};
    use sui::event;
    use hacksuimer_contract::hacksuimer_sorting::{Self,RankingConfig};
    use hacksuimer_contract::profile_nft::{Self,ProfileNFT};


    // 错误码
    // Error codes
    const EInvalidState: u64 = 0;
    const ENotAuthorized: u64 = 1;
    const EInvalidTime: u64 = 2;
    const EInvalidAmount: u64 = 3;
    const ENameTooLong: u64 = 4;
    const EInvalidProposalLimit: u64 = 5;
    const EInvalidVotingPeriod: u64 = 6;
    const EMaxProposalsPerUserReached: u64 = 7;
    const EMaxProposalsReached: u64 = 8;
    const ESubmissionDeadlinePassed: u64 = 9;
    const EAlreadyVoted: u64 = 10;

    // 活动状态
    // Event status
    const STATE_NOT_STARTED: u8 = 0;
    const STATE_ACTIVE: u8 = 1;
    const STATE_VOTING: u8 = 2;
    const STATE_ENDED: u8 = 3;

    // 常量
    // Constants
    const MIN_VOTE_AMOUNT: u64 = 1_000_000_000; // 1 SUI

    // 事件结构体定义
    public struct HackathonCreatedEvent has copy, drop {
        hackathon_id: ID,
        creator: address,
        name: String,
        start_time: u64,
        end_time: u64
    }

    public struct ProposalSubmittedEvent has copy, drop {
        proposal_id: ID,
        hackathon_id: ID,
        creator: address,
        name: String
    }

    public struct JudgeVoteEvent has copy, drop {
        proposal_id: ID,
        hackathon_id: ID,
        judge: address,
        vote_amount: u64
    }

    public struct CommunityVoteEvent has copy, drop {
        proposal_id: ID,
        hackathon_id: ID,
        votes: u64
    }

    public struct HackathonEndedEvent has copy, drop {
        hackathon_id: ID,
        end_time: u64
    }

    public struct HackathonEvent has key {
        id: UID,
        name: String,
        description: String,
        image_url: Option<Url>,
        contact_info: Option<String>,
        reward_description: String,
        evaluation_criteria: Option<String>,
        creator: address,
        start_time: u64,
        voting_delay: u64,
        voting_period: u64,
        end_time: u64,
        status: u8,
        judges: vector<address>,
        proposals: vector<ID>,
        max_proposal_count: u64,
        proposals_per_user: u64,
        votes: Table<ID, u64>,  // 总票数表 // Total votes table
        judge_vote_limits: Table<address, u64>,  // 评委投票限制 // Judge vote limits
        user_proposal_counts: Table<address, u64>,
        ranking_config: RankingConfig,
        user_voted: Table<address, bool>, // 用户是否已投票 // Whether the user has voted
    }


    public struct JudgeComment has store, drop {  
        judge: address,
        comment: String,
        timestamp: u64
    }

    public struct Proposal has key {
        id: UID,
        event_id: ID,
        creator: address,
        name: String,
        description: String,
        repository_url: String,
        creation_time: u64,
        total_score: u64,  // 总分 // Total score
        judge_comments: Table<address, JudgeComment>  // 评委评论 // Judge comments
    }

    public entry fun update_hackathon_status(
        hackathon: &mut HackathonEvent,
        clock: &Clock,
        _ctx: &mut TxContext
    ) {
        let current_time = clock::timestamp_ms(clock);
        
        // 根据当前时间更新状态
        if (current_time < hackathon.start_time) {
            hackathon.status = STATE_NOT_STARTED;
        } else if (current_time >= hackathon.start_time && current_time < hackathon.start_time + hackathon.voting_delay) {
            hackathon.status = STATE_ACTIVE;
        } else if (current_time >= hackathon.start_time + hackathon.voting_delay && current_time < hackathon.end_time) {
            hackathon.status = STATE_VOTING;
        } else if (current_time >= hackathon.end_time) {
            hackathon.status = STATE_ENDED;
        }
    }

    // 创建黑客松活动
    // Create a hackathon event
    public entry fun create_hacksuimer_event(
        name: vector<u8>,
        description: vector<u8>,
        mut image_url: Option<vector<u8>>,
        mut contact_info: Option<vector<u8>>,
        reward_description: vector<u8>,
        mut evaluation_criteria: Option<vector<u8>>,
        contest_start: u64,
        voting_delay: u64,
        voting_period: u64,
        proposals_per_user: u64,
        max_proposal_count: u64,
        judges: vector<address>,
        judge_vote_limits: vector<u64>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // 验证参数
        // Validate parameters
        assert!(string::length(&string::utf8(name)) <= 30, ENameTooLong);
        assert!(proposals_per_user > 0 && max_proposal_count > 0, EInvalidProposalLimit);
        assert!(voting_delay > 0 && voting_period > 0, EInvalidVotingPeriod);
        
        // 计算结束时间
        // Calculate the end time
        let end_time = contest_start + voting_delay + voting_period;
        
        // 创建可选字段
        // Create optional fields
        let image = if (option::is_some(&image_url)) {
            option::some(url::new_unsafe_from_bytes(option::extract(&mut image_url)))
        } else {
            option::none()
        };
        
        let contact = if (option::is_some(&contact_info)) {
            option::some(string::utf8(option::extract(&mut contact_info)))
        } else {
            option::none()
        };
        
        let criteria = if (option::is_some(&evaluation_criteria)) {
            option::some(string::utf8(option::extract(&mut evaluation_criteria)))
        } else {
            option::none()
        };

        let mut judge_limits_table = table::new(ctx);
        let mut i = 0;
        while (i < vector::length(&judges)) {
            let judge = *vector::borrow(&judges, i);
            let vote_limit = *vector::borrow(&judge_vote_limits, i);
            table::add(&mut judge_limits_table, judge, vote_limit);
            i = i + 1;
        };

        let ranking_config = hacksuimer_sorting::init_ranking(max_proposal_count);
        let mut hackathon = HackathonEvent {
            id: object::new(ctx),
            name: string::utf8(name),
            description: string::utf8(description),
            image_url: image,
            contact_info: contact,
            reward_description: string::utf8(reward_description),
            evaluation_criteria: criteria,
            creator: tx_context::sender(ctx),
            start_time: contest_start,
            voting_delay,
            voting_period,
            end_time,
            status: STATE_NOT_STARTED,
            judges,
            proposals: vector::empty(),
            max_proposal_count,
            proposals_per_user,
            votes: table::new(ctx),
            judge_vote_limits: judge_limits_table,
            user_proposal_counts: table::new(ctx),
            ranking_config,
            user_voted: table::new(ctx)
        };
        update_hackathon_status(&mut hackathon, clock, ctx);
        // 释放创建事件
        // Release the creation event
        event::emit(HackathonCreatedEvent {
            hackathon_id: object::uid_to_inner(&hackathon.id),
            creator: tx_context::sender(ctx),
            name: string::utf8(name),
            start_time: contest_start,
            end_time
        });
        transfer::share_object(hackathon);
    }

    // 提交项目
    // Submit a project
    public entry fun submit_proposal(
        hackathon: &mut HackathonEvent,
        // profile: &mut profile_nft::ProfileNFT,
        name: vector<u8>,
        description: vector<u8>,
        repository_url: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        update_hackathon_status(hackathon, clock, ctx);
        // 验证状态
        // Validate status
        assert!(hackathon.status == STATE_ACTIVE, EInvalidState);
        let current_time = clock::timestamp_ms( clock);
        let submission_deadline = hackathon.start_time + hackathon.voting_delay;
        assert!(current_time <= submission_deadline, ESubmissionDeadlinePassed);

        let sender = tx_context::sender(ctx);
        
        // 初始化用户提案计数
        // Initialize user proposal count
        if (!table::contains(&hackathon.user_proposal_counts, sender)) {
            table::add(&mut hackathon.user_proposal_counts, sender, 0);
        };
        
        // 检查用户提案数量限制
        // Check the proposal limit per user
        let user_count = table::borrow(&hackathon.user_proposal_counts, sender);
        assert!(*user_count < hackathon.proposals_per_user, EMaxProposalsPerUserReached);
        
        // 检查总提案数量限制
        // Check the total proposal limit
        assert!(vector::length(&hackathon.proposals) < hackathon.max_proposal_count, EMaxProposalsReached);

        // 创建提案
        // Create a proposal
        let proposal = Proposal {
            id: object::new(ctx),
            event_id: object::uid_to_inner(&hackathon.id),
            creator: sender,
            name: string::utf8(name),
            description: string::utf8(description),
            repository_url: string::utf8(repository_url),
            creation_time: tx_context::epoch(ctx),
            total_score: 0,
            judge_comments: table::new(ctx)
        };
        
    
        // 更新 ProfileNFT 中的项目历史
        // profile_nft::add_project(
        //     profile,
        //     object::uid_to_inner(&proposal.id),  // project_id
        //     object::uid_to_inner(&hackathon.id),  // hackathon_id
        //     0,  // 初始分数为0
        //     ctx
        // );

        // 更新计数
        // Update count
        *table::borrow_mut(&mut hackathon.user_proposal_counts, sender) = *user_count + 1;
        vector::push_back(&mut hackathon.proposals, object::uid_to_inner(&proposal.id));
        // 释放提案提交事件
        // Release the proposal submission event
        event::emit(ProposalSubmittedEvent {
            proposal_id: object::uid_to_inner(&proposal.id),
            hackathon_id: object::uid_to_inner(&hackathon.id),
            creator: sender,
            name: string::utf8(name)
        });

        transfer::share_object(proposal);
    }

    // 评委投票
    // Judge vote
    public fun judge_vote(
        hackathon: &mut HackathonEvent,
        proposal: &mut Proposal,
        vote_amount: u64,
        comment: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        update_hackathon_status(hackathon, clock, ctx);
        let sender = tx_context::sender(ctx);
        assert!(vector::contains(&hackathon.judges, &sender), ENotAuthorized);
        assert!(hackathon.status == STATE_VOTING, EInvalidState);

        // 检查评委的投票额度
        // Check the judge's voting limit
        let vote_limit = table::borrow(&hackathon.judge_vote_limits, sender);
        assert!(vote_amount <= *vote_limit, EInvalidAmount);

        let proposal_id = object::uid_to_inner(&proposal.id);

        // 保存评论
        // Save comment
        let judge_comment = JudgeComment {
            judge: sender,
            comment: string::utf8(comment),
            timestamp: clock::timestamp_ms(clock)
        };
        
        if (!table::contains(&proposal.judge_comments, sender)) {
            table::add(&mut proposal.judge_comments, sender, judge_comment);
        } else {
            *table::borrow_mut(&mut proposal.judge_comments, sender) = judge_comment;
        };

        // 更新总票数
        // Update total votes
        if (!table::contains(&hackathon.votes, proposal_id)) {
            table::add(&mut hackathon.votes, proposal_id, vote_amount);
        } else {
            let current_votes = table::borrow_mut(&mut hackathon.votes, proposal_id);
            *current_votes = *current_votes + vote_amount;
        };

        // 更新评委剩余投票额度
        // Update the judge's remaining voting limit
        let remaining_votes = table::borrow_mut(&mut hackathon.judge_vote_limits, sender);
        *remaining_votes = *remaining_votes - vote_amount;

        // 更新项目总分
        // Update the project's total score
        proposal.total_score = *table::borrow(&hackathon.votes, proposal_id);

        // 更新排名
        // Update ranking
        hacksuimer_sorting::update_ranks(
            &mut hackathon.ranking_config,
            proposal_id,
            proposal.total_score,
            0,
            proposal.creation_time
        );
        // 释放评委投票事件
        // Release the judge vote event
        event::emit(JudgeVoteEvent {
            proposal_id: object::uid_to_inner(&proposal.id),
            hackathon_id: object::uid_to_inner(&hackathon.id),
            judge: sender,
            vote_amount
        });
    }

    // 社区投票，根据钱包中sui的数量来决定可以投的票数，1 SUI = 1票
    // Community vote, the number of votes that can be cast is determined by the amount of SUI in the wallet, 1 SUI = 1 vote
    public fun community_vote(
        hackathon: &mut HackathonEvent,
        proposal: &mut Proposal,
        wallet_balance: &Balance<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        update_hackathon_status(hackathon, clock, ctx);
        let sender = tx_context::sender(ctx);
        assert!(hackathon.status == STATE_VOTING, EInvalidState);
        assert!(!table::contains(&hackathon.user_voted, sender), EAlreadyVoted);
        
        // 获取钱包余额并计算票数
        // Get the wallet balance and calculate the number of votes
        let amount = balance::value(wallet_balance);
        assert!(amount >= MIN_VOTE_AMOUNT, EInvalidAmount);
        let votes = amount / MIN_VOTE_AMOUNT; // 1 SUI = 1票，向下取整 // 1 SUI = 1 vote, rounded down
        
        let proposal_id = object::uid_to_inner(&proposal.id);
        
        // 更新总票数
        // Update total votes
        if (!table::contains(&hackathon.votes, proposal_id)) {
            table::add(&mut hackathon.votes, proposal_id, votes);
        } else {
            let current_votes = table::borrow_mut(&mut hackathon.votes, proposal_id);
            *current_votes = *current_votes + votes;
        };

        // 标记用户已投票
        // Mark the user as voted
        table::add(&mut hackathon.user_voted, sender, true);

        // 更新项目总分
        // Update the project's total score
        proposal.total_score = *table::borrow(&hackathon.votes, proposal_id);

        // 更新排名
        // Update ranking
        hacksuimer_sorting::update_ranks(
            &mut hackathon.ranking_config,
            proposal_id,
            0,
            proposal.total_score,
            proposal.creation_time
        );
        // 释放社区投票事件
        // Release the community vote event
        event::emit(CommunityVoteEvent {
            proposal_id: object::uid_to_inner(&proposal.id),
            hackathon_id: object::uid_to_inner(&hackathon.id),
            votes
        });
    }

    // 结束活动
    // End the event
    public fun end_hackathon(
        hackathon: &mut HackathonEvent,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == hackathon.creator, ENotAuthorized);
        assert!(clock::timestamp_ms(clock) >= hackathon.end_time, EInvalidTime);
        
        hackathon.status = STATE_ENDED;
        // 释放活动结束事件
        // Release the event end event
        event::emit(HackathonEndedEvent {
            hackathon_id: object::uid_to_inner(&hackathon.id),
            end_time: clock::timestamp_ms(clock)
        });
    }

    // 获取活动状态
    // Get the event status
    public fun get_hackathon_status(hackathon: &HackathonEvent): u8 {
        hackathon.status
    }

    #[test_only]
    public fun set_status_for_testing(hackathon: &mut HackathonEvent, status: u8) {
        hackathon.status = status;
    }
}
