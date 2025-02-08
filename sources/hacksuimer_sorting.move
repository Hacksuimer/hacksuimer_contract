// Hacksuimer 排名系统逻辑说明：
//
// 1. 数据结构
//    - RankingConfig: 存储排名配置和排序项目列表
//    - ProjectScore: 存储项目得分信息，包括评委票数、社区票数和总分
//
// 2. 排名规则
//    - 按总分（评委票 + 社区票）降序排列
//    - 总分相同时，按创建时间升序排列（先提交的排前面）
//    - 维护固定数量（rank_limit）的排名列表
//
// 3. 投票累计机制
//    - 记录并累加评委投票
//    - 记录并累加社区投票
//    - 自动计算总分 = 评委票数 + 社区票数
//
// 4. 排名更新流程
//    a. 查找项目是否已存在于排名中
//    b. 如存在，获取旧的投票数据并移除旧记录
//    c. 计算新的总分
//    d. 根据排序规则找到正确的插入位置
//    e. 处理排名限制（只保留前N名）
//
// 5. 边界情况处理
//    - 空列表直接插入
//    - 超出排名限制时移除最后一名
//    - 新项目分数高于最后一名时替换
//    - 排序功能可通过 sorting_enabled 开关控制
//
// 6. 查询功能
//    - 获取项目当前排名
//    - 获取所有排名项目列表
//    - 获取排名数量限制
//    - 检查排序功能状态

// Hacksuimer Ranking System Logic:
//
// 1. Data Structures
//    - RankingConfig: Stores ranking configuration and sorted project list
//    - ProjectScore: Stores project score information, including judge votes, community votes and total score
//
// 2. Ranking Rules
//    - Sorted by total score (judge votes + community votes) in descending order
//    - When scores are equal, sorted by creation time in ascending order (earlier submissions ranked higher)
//    - Maintains a fixed number (rank_limit) of ranked projects
//
// 3. Vote Accumulation Mechanism
//    - Records and accumulates judge votes
//    - Records and accumulates community votes
//    - Automatically calculates total score = judge votes + community votes
//
// 4. Ranking Update Process
//    a. Check if project exists in ranking
//    b. If exists, retrieve old vote data and remove old record
//    c. Calculate new total score
//    d. Find correct insertion position based on sorting rules
//    e. Handle ranking limit (keep only top N)
//
// 5. Edge Case Handling
//    - Direct insertion for empty list
//    - Remove last place when exceeding rank limit
//    - Replace last place if new project scores higher
//    - Sorting can be toggled via sorting_enabled switch
//
// 6. Query Functions
//    - Get project current rank
//    - Get list of all ranked projects
//    - Get ranking limit
//    - Check sorting status

module hacksuimer_contract::hacksuimer_sorting {

    // 错误码
    // Error codes
    const ERankLimitZero: u64 = 100;

    public struct RankingConfig has store {
        sorting_enabled: bool,
        rank_limit: u64,
        sorted_projects: vector<ProjectScore>
    }

    // 项目得分
    // Project score 
    public struct ProjectScore has store, drop {
        project_id: ID,
        judge_votes: u64,    // 评委票数
        community_votes: u64, // 社区票数
        total_score: u64,     // 总票数 = judge_votes + community_votes
        creation_time: u64  // 创建时间 // creation time
    }

    public fun init_ranking(rank_limit: u64): RankingConfig {
        assert!(rank_limit > 0, ERankLimitZero);
        
        RankingConfig {
            sorting_enabled: true,
            rank_limit,
            sorted_projects: vector::empty()
        }
    }

    public fun update_ranks(
        config: &mut RankingConfig,
        project_id: ID,
        judge_votes: u64,
        community_votes: u64,
        creation_time: u64
    ) {
        if (!config.sorting_enabled) return;

        let ranks_len = vector::length(&config.sorted_projects);
        
        // 查找并获取旧的项目得分（如果存在）
        // Find and get the old project score (if it exists)
        let mut i = 0;
        let mut found = false;
        let mut old_judge_votes = 0;
        let mut old_community_votes = 0;
        
        while (i < ranks_len) {
            let current = vector::borrow(&config.sorted_projects, i);
            if (current.project_id == project_id) {
                old_judge_votes = current.judge_votes;
                old_community_votes = current.community_votes;
                vector::remove(&mut config.sorted_projects, i);
                found = true;
                break
            };
            i = i + 1;
        };

        // 计算新的总分
        // Calculate the new total score
        let new_judge_votes = old_judge_votes + judge_votes;
        let new_community_votes = old_community_votes + community_votes;
        let total_score = new_judge_votes + new_community_votes;

        // 创建新的项目得分对象
        // Create a new project score object
        let project_score = ProjectScore { 
            project_id,
            judge_votes: new_judge_votes,
            community_votes: new_community_votes,
            total_score,
            creation_time
        };

        // 如果是空列表，直接插入
        // If it is an empty list, insert directly
        if (vector::length(&config.sorted_projects) == 0) {
            vector::push_back(&mut config.sorted_projects, project_score);
            return
        };

        // 找到新的插入位置（按总分降序排列，同分按创建时间升序）
        //  Find the new insertion position (arranged in descending order of total score, and in ascending order of creation time for the same score)
        let mut insert_pos = 0;
        let current_len = vector::length(&config.sorted_projects);
        
        while (insert_pos < current_len) {
            let current = vector::borrow(&config.sorted_projects, insert_pos);
            if (total_score > current.total_score) {
                // 分数高的排前面
                // Higher scores are ranked first
                break
            } else if (total_score == current.total_score && creation_time < current.creation_time) {
                // 同分时，创建时间早的排前面
                // When the scores are the same, the earlier creation time is ranked first
                break
            };
            insert_pos = insert_pos + 1;
        };

        // 处理插入逻辑
        // Handle insertion logic
        if (insert_pos < config.rank_limit) {
            // 直接插入到正确位置
            // Insert directly to the correct position
            vector::insert(&mut config.sorted_projects, project_score, insert_pos);
            
            // 如果超出排名限制，移除最后一个
            // If it exceeds the ranking limit, remove the last one
            if (vector::length(&config.sorted_projects) > config.rank_limit) {
                vector::pop_back(&mut config.sorted_projects);
            };
        } else if (!found && total_score > vector::borrow(&config.sorted_projects, config.rank_limit - 1).total_score) {
            // 如果是新项目且分数高于最后一名，替换最后一名
            // If it is a new project and the score is higher than the last one, replace the last one
            vector::pop_back(&mut config.sorted_projects);
            vector::push_back(&mut config.sorted_projects, project_score);
        };
    }

    public fun get_project_rank(config: &RankingConfig, project_id: ID): (bool, u64) {
        let mut i = 0;
        let len = vector::length(&config.sorted_projects);
        
        while (i < len) {
            let current = vector::borrow(&config.sorted_projects, i);
            if (current.project_id == project_id) {
                return (true, i + 1)
            };
            i = i + 1;
        };
        
        (false, 0)
    }

    public fun get_top_projects(config: &RankingConfig): &vector<ProjectScore> {
        &config.sorted_projects
    }

    public fun get_rank_limit(config: &RankingConfig): u64 {
        config.rank_limit
    }

    public fun is_sorting_enabled(config: &RankingConfig): bool {
        config.sorting_enabled
    }


    #[test_only]
    public fun destroy_for_testing(config: RankingConfig) {
        let RankingConfig { 
            sorting_enabled: _,
            rank_limit: _,
            sorted_projects: _
        } = config;
    }
}