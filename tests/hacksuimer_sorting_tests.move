#[test_only]
module hacksuimer_contract::hacksuimer_sorting_tests {
    use sui::test_scenario::{Self as ts};
    use hacksuimer_contract::hacksuimer_sorting::{Self, RankingConfig};

    const CREATOR: address = @0xCAFE;

    // 辅助函数：创建一个独特的项目ID
    fun create_test_id(ctx: &mut TxContext): ID {
        let uid = object::new(ctx);
        let id = object::uid_to_inner(&uid);
        object::delete(uid);  // 删除 UID，避免内存泄漏
        id
    }
    // 添加辅助函数来清理 RankingConfig
    fun destroy_ranking_config(config: RankingConfig) {
        // 如果 hacksuimer_sorting 模块提供了销毁函数就调用它
        // 否则我们需要在 hacksuimer_sorting 模块中添加一个
        hacksuimer_sorting::destroy_for_testing(config)
    }


    #[test]
    fun test_init_ranking() {
        let scenario = ts::begin(CREATOR);
        {
            let config = hacksuimer_sorting::init_ranking(10);
            assert!(hacksuimer_sorting::get_rank_limit(&config) == 10, 0);
            assert!(hacksuimer_sorting::is_sorting_enabled(&config), 1);
            assert!(vector::length(hacksuimer_sorting::get_top_projects(&config)) == 0, 2);
            destroy_ranking_config(config); // 销毁配置
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = hacksuimer_sorting::ERankLimitZero)]
    fun test_init_ranking_zero_limit() {
        let scenario = ts::begin(CREATOR);
        {
            let config = hacksuimer_sorting::init_ranking(0);
            destroy_ranking_config(config); // 即使预期失败也要尝试清理
        };
        ts::end(scenario);
    }

    #[test]
    fun test_update_ranks_single_project() {
        let mut scenario = ts::begin(CREATOR);
        let mut config = hacksuimer_sorting::init_ranking(5);
        let project_id = create_test_id(ts::ctx(&mut scenario));

        hacksuimer_sorting::update_ranks(
            &mut config,
            project_id,
            10,
            5,
            100
        );

        let (exists, rank) = hacksuimer_sorting::get_project_rank(&config, project_id);
        assert!(exists, 0);
        assert!(rank == 1, 1);
        
        destroy_ranking_config(config); // 销毁配置
        ts::end(scenario);
    }

    #[test]
    fun test_update_ranks_multiple_projects() {
        let mut scenario = ts::begin(CREATOR);
        let mut config = hacksuimer_sorting::init_ranking(5);
        
        // 创建三个项目ID
        let project1_id = create_test_id(ts::ctx(&mut scenario));
        let project2_id = create_test_id(ts::ctx(&mut scenario));
        let project3_id = create_test_id(ts::ctx(&mut scenario));

        // 添加三个项目，分数不同
        hacksuimer_sorting::update_ranks(&mut config, project1_id, 10, 5, 100); // 总分15
        hacksuimer_sorting::update_ranks(&mut config, project2_id, 20, 5, 200); // 总分25
        hacksuimer_sorting::update_ranks(&mut config, project3_id, 5, 5, 300);  // 总分10

        // 验证排名顺序（按分数降序）
        let (_, rank2) = hacksuimer_sorting::get_project_rank(&config, project2_id);
        let (_, rank1) = hacksuimer_sorting::get_project_rank(&config, project1_id);
        let (_, rank3) = hacksuimer_sorting::get_project_rank(&config, project3_id);

        assert!(rank2 == 1, 0); // project2应该第一（25分）
        assert!(rank1 == 2, 1); // project1应该第二（15分）
        assert!(rank3 == 3, 2); // project3应该第三（10分）

        destroy_ranking_config(config);
        ts::end(scenario);
    }

    #[test]
    fun test_update_ranks_equal_scores() {
        let mut scenario = ts::begin(CREATOR);
        let mut config = hacksuimer_sorting::init_ranking(5);
        
        // 创建两个具有相同分数但不同创建时间的项目
        let early_project_id = create_test_id(ts::ctx(&mut scenario));
        let late_project_id = create_test_id(ts::ctx(&mut scenario));

        // 添加两个总分相同的项目
        hacksuimer_sorting::update_ranks(&mut config, late_project_id, 10, 5, 200);  // 总分15，较晚
        hacksuimer_sorting::update_ranks(&mut config, early_project_id, 10, 5, 100); // 总分15，较早

        // 验证排名（创建时间早的应该排在前面）
        let (_, early_rank) = hacksuimer_sorting::get_project_rank(&config, early_project_id);
        let (_, late_rank) = hacksuimer_sorting::get_project_rank(&config, late_project_id);

        assert!(early_rank == 1, 0); // 早期项目应该排第一
        assert!(late_rank == 2, 1);  // 晚期项目应该排第二
        destroy_ranking_config(config);
        ts::end(scenario);
    }

    #[test]
    fun test_rank_limit_enforcement() {
        let mut scenario = ts::begin(CREATOR);
        let mut config = hacksuimer_sorting::init_ranking(2); // 只允许两个排名
        
        // 创建三个项目
        let project1_id = create_test_id(ts::ctx(&mut scenario));
        let project2_id = create_test_id(ts::ctx(&mut scenario));
        let project3_id = create_test_id(ts::ctx(&mut scenario));

        // 按分数顺序添加三个项目
        hacksuimer_sorting::update_ranks(&mut config, project1_id, 10, 0, 100); // 总分10
        hacksuimer_sorting::update_ranks(&mut config, project2_id, 20, 0, 200); // 总分20
        hacksuimer_sorting::update_ranks(&mut config, project3_id, 30, 0, 300); // 总分30

        // 验证只保留了最高分的两个项目
        let top_projects = hacksuimer_sorting::get_top_projects(&config);
        assert!(vector::length(top_projects) == 2, 0);

        // 验证排名1和2的项目
        let (exists1, _) = hacksuimer_sorting::get_project_rank(&config, project1_id);
        let (exists2, rank2) = hacksuimer_sorting::get_project_rank(&config, project2_id);
        let (exists3, rank3) = hacksuimer_sorting::get_project_rank(&config, project3_id);

        assert!(!exists1, 1);       // project1应该被排除
        assert!(exists2, 2);        // project2应该在榜
        assert!(exists3, 3);        // project3应该在榜
        assert!(rank3 == 1, 4);     // project3应该排第一
        assert!(rank2 == 2, 5);     // project2应该排第二
        destroy_ranking_config(config);
        ts::end(scenario);
    }
}