import XCTest
@testable import Axblade

/// 打真实 fuyao 接口的冒烟测试:五个模块模型各跑一遍。默认跳过;
/// 设 `AXBLADE_LIVE=1`,或在测试宿主容器的 tmp 里放一个 `AXBLADE_LIVE` 文件
/// (沙盒宿主收不到 xcodebuild 的环境变量)时启用。
@MainActor
final class LiveFuyaoSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("AXBLADE_LIVE")
        let enabled = ProcessInfo.processInfo.environment["AXBLADE_LIVE"] == "1" || FileManager.default.fileExists(atPath: marker.path)
        try XCTSkipUnless(enabled, "设 AXBLADE_LIVE=1 或创建 \(marker.path) 才打真实接口")
    }

    private func makeViewModel() -> AppViewModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AxbladeLive-\(UUID().uuidString)")
        let viewModel = AppViewModel(
            store: ConversationStore(directory: directory),
            accountService: AccountService(tokenProvider: { nil }),
            researchStore: MarketResearchStore(directory: directory.appendingPathComponent("research"))
        )
        viewModel.accountTask?.cancel()
        return viewModel
    }

    func testLimitUpPulseLive() async throws {
        let viewModel = makeViewModel()
        viewModel.limitUpPulse.load()
        await viewModel.limitUpPulse.task?.value
        XCTAssertNil(viewModel.limitUpPulse.errorText)
        let report = try XCTUnwrap(viewModel.limitUpPulse.report)
        print("LIVE 涨停脉冲:", report.promptText.prefix(400))
        XCTAssertEqual(report.ladder.count, 30)
    }

    func testDragonTigerLive() async throws {
        let viewModel = makeViewModel()
        viewModel.dragonTigerTopology.load()
        await viewModel.dragonTigerTopology.task?.value
        XCTAssertNil(viewModel.dragonTigerTopology.errorText)
        let graph = try XCTUnwrap(viewModel.dragonTigerTopology.graph)
        print("LIVE 拓扑:", graph.date, graph.nodes.count, "nodes", graph.edges.count, "edges")

        viewModel.dragonTigerWatch.days = 3
        viewModel.dragonTigerWatch.load()
        await viewModel.dragonTigerWatch.task?.value
        XCTAssertNil(viewModel.dragonTigerWatch.errorText)
        let watch = try XCTUnwrap(viewModel.dragonTigerWatch.report)
        print("LIVE 观察:", watch.dates, watch.players.count, "players")
        XCTAssertEqual(watch.dates.count, 3)
    }

    func testHeatRadarLive() async throws {
        let viewModel = makeViewModel()
        viewModel.heatRadar.load()
        await viewModel.heatRadar.task?.value
        XCTAssertNil(viewModel.heatRadar.errorText)
        let report = try XCTUnwrap(viewModel.heatRadar.report)
        print("LIVE 雷达:", report.points.count, "points", report.resonance.count, "resonance", report.anomalies.count, "anomalies")
        viewModel.heatRadar.select(report.points.first?.id)
        for _ in 0..<100 where viewModel.heatRadar.isLoadingTrend { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertFalse(viewModel.heatRadar.rankTrend.isEmpty)
    }

    func testMarketTrendLiveIncremental() async throws {
        let viewModel = makeViewModel()
        let start = Date()
        viewModel.marketTrend.refresh()
        await viewModel.marketTrend.task?.value
        XCTAssertNil(viewModel.marketTrend.errorText)
        let report = try XCTUnwrap(viewModel.marketTrend.report)
        print("LIVE 趋势:", Int(Date().timeIntervalSince(start)), "s;", report.sectors.count, "sectors;", report.regime, "; cache", viewModel.marketTrend.cacheBytes / 1024, "KB")
        XCTAssertGreaterThan(report.sectors.count, 250)
        XCTAssertEqual(report.indices.count, 6)
        XCTAssertGreaterThan(report.breadth?.total ?? 0, 5000)

        // 第二次应是增量(每个板块只补最后几根)
        let second = Date()
        viewModel.marketTrend.refresh()
        await viewModel.marketTrend.task?.value
        XCTAssertNil(viewModel.marketTrend.errorText)
        print("LIVE 增量刷新:", Int(Date().timeIntervalSince(second)), "s")

        viewModel.marketTrend.stockSymbol = "600519"
        viewModel.marketTrend.researchStock()
        for _ in 0..<200 where viewModel.marketTrend.isLoadingStock { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertNil(viewModel.marketTrend.stockError)
        XCTAssertEqual(viewModel.marketTrend.stockName, "贵州茅台")
        print("LIVE 个股:", viewModel.marketTrend.stockPromptText?.prefix(300) ?? "")
    }

    func testAgentContextLive() async throws {
        let viewModel = makeViewModel()
        let context = await viewModel.contextBuilder.build(for: "分析一下 600519,今天竞价风向标怎么样", language: .zh)
        print("LIVE 上下文:", context.labels, context.text.prefix(300))
        XCTAssertTrue(context.labels.contains("600519.SH 贵州茅台"))
    }
}
