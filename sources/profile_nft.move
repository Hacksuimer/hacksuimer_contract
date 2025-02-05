module hacksuimer_contract::profile_nft {
    use sui::url::{Self, Url};
    use sui::dynamic_field as df;
    use std::string::{String};
    use sui::event;

    // 错误码
    // error code   
    const ENO_PERMISSION: u64 = 0;
    const EINVALID_RANK: u64 = 1;
    const EINVALID_NAME: u64 = 2;
    const EINVALID_IMAGE: u64 = 3;

    // NFT配置文件
    // NFT profile
    public struct ProfileNFT has key, store {
        id: UID,
        owner: address,
        name: String,
        image_url: Url,
        rank: u64,
        created_at: u64,
    }

    // 成就记录
    // Achievement record
    public struct Achievement has key,store {
        id: UID,
        name: String,
        description: String,
        achieved_at: u64
    }

    // 项目历史
    // Project history
    public struct ProjectHistory has key,store {
        id: UID,
        project_id: address,
        hackathon_id: address,
        submission_time: u64,
        score: u64
    }

    // 个人资料事件
    // Profile created event
    public struct ProfileCreatedEvent has copy, drop {
        creator: address,
        profile_id: ID,
        timestamp: u64,
    }

    // 为动态字段定义类型别名
    // Define type aliases for dynamic fields
    public struct AchievementsKey has copy, drop, store { }
    public struct ProjectsKey has copy, drop, store { }

    // 创建NFT配置文件
    // Create NFT profile
    public fun create_profile(
        name: String,
        image_url: vector<u8>,
        ctx: &mut TxContext
    ) {
        assert!(std::string::length(&name) > 0, EINVALID_NAME);
        assert!(vector::length(&image_url) > 0, EINVALID_IMAGE);
        let sender = tx_context::sender(ctx);
        let mut profile = ProfileNFT {
            id: object::new(ctx),
            owner: sender,
            name,
            image_url: url::new_unsafe_from_bytes(image_url),
            rank: 0,
            created_at: tx_context::epoch(ctx)
        };

        // 初始化成就列表和项目历史
        // Initialize the list of achievements and project history
        df::add(&mut profile.id, AchievementsKey {}, vector::empty<Achievement>());
        df::add(&mut profile.id, ProjectsKey {}, vector::empty<ProjectHistory>());

        // 释放事件
        // Emit event
        event::emit(ProfileCreatedEvent {
            creator: sender,
            profile_id: object::id(&profile),
            timestamp: tx_context::epoch(ctx)
        });

        transfer::transfer(profile, sender);
    }

    // 添加成就
    // Add achievement
    public fun add_achievement(
        profile: &mut ProfileNFT,
        name: String,
        description: String,
        ctx: &mut TxContext
    ) {

        assert!(profile.owner == tx_context::sender(ctx), ENO_PERMISSION);
        
        let achievement = Achievement {
            id: object::new(ctx),
            name,
            description,
            achieved_at: tx_context::epoch(ctx)
        };

        let achievements = df::borrow_mut<AchievementsKey, vector<Achievement>>(
            &mut profile.id,
            AchievementsKey {}
        );
        vector::push_back(achievements, achievement);
    }

    // 查看成就
    // View achievements
    public fun view_achievements(profile: &ProfileNFT): &vector<Achievement> {
        df::borrow(&profile.id, AchievementsKey {})
    }


    // 更新排名
    // Update rank
    public fun update_rank(
        profile: &mut ProfileNFT,
        new_rank: u64,
        ctx: &mut TxContext
    ) {
        assert!(profile.owner == tx_context::sender(ctx), ENO_PERMISSION);
        assert!(new_rank >= 0, EINVALID_RANK);
        
        profile.rank = new_rank;
    }

    // 添加项目历史
    // Add project history
    public fun add_project(
        profile: &mut ProfileNFT,
        project_id: address,
        hackathon_id: address,
        score: u64,
        ctx: &mut TxContext
    ) {
        assert!(profile.owner == tx_context::sender(ctx), ENO_PERMISSION);

        let project = ProjectHistory {
            id: object::new(ctx),
            project_id,
            hackathon_id,
            submission_time: tx_context::epoch(ctx),
            score
        };

        let projects = df::borrow_mut<ProjectsKey, vector<ProjectHistory>>(
            &mut profile.id,
            ProjectsKey {}
        );
        vector::push_back(projects, project);
    }
}