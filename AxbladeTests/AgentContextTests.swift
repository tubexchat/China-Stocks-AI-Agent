import XCTest
@testable import Axblade

/// 智能体的意图路由与上下文拼装。
final class AgentContextTests: XCTestCase {
    func testIntentRouting() {
        XCTAssertEqual(AgentIntentRouter.route("今天涨停情绪怎么样"), [.limitUp])
        XCTAssertEqual(AgentIntentRouter.route("昨天龙虎榜有哪些游资在买"), [.dragonTiger])
        XCTAssertEqual(AgentIntentRouter.route("现在热度最高的股票"), [.heat])
        XCTAssertEqual(AgentIntentRouter.route("大盘和板块趋势"), [.market])
        XCTAssertEqual(AgentIntentRouter.route("竞价风向标"), [.auction])
        XCTAssertEqual(AgentIntentRouter.route("连板高度和机构席位"), [.limitUp, .dragonTiger])
        XCTAssertEqual(AgentIntentRouter.route("你好"), [])
        XCTAssertEqual(AgentIntentRouter.route("How is the market trend?"), [.market])
    }

    func testNameCandidate() {
        XCTAssertEqual(AgentIntentRouter.nameCandidate(in: "分析一下贵州茅台"), "贵州茅台")
        XCTAssertEqual(AgentIntentRouter.nameCandidate(in: "宁德时代怎么样?"), "宁德时代")
        XCTAssertNil(AgentIntentRouter.nameCandidate(in: "今天市场怎么样,有什么机会"))
        XCTAssertNil(AgentIntentRouter.nameCandidate(in: "你好"))
        XCTAssertNil(AgentIntentRouter.nameCandidate(in: "600519"))
    }

    func testBuilderAttachesStockBlockForCode() async {
        let stub = StubDataProvider()
        let builder = AgentContextBuilder(data: stub, now: { Date(timeIntervalSince1970: 1_788_856_106) })
        let context = await builder.build(for: "分析一下 600519", language: .zh)
        XCTAssertEqual(context.labels, ["600519.SH 贵州茅台"])
        XCTAssertTrue(context.text.contains("【A股行情 · 600519.SH(贵州茅台)"))
        XCTAssertTrue(context.text.contains("现价 1309.3 CNY"))
        XCTAssertTrue(context.text.contains("近30日收盘"))
        XCTAssertEqual(stub.count("snapshot"), 1)
        XCTAssertEqual(stub.count("limitUpPool"), 0, "没问涨停就别拉涨停池")
    }

    func testBuilderResolvesChineseNameViaSearch() async {
        let stub = StubDataProvider()
        let builder = AgentContextBuilder(data: stub)
        let context = await builder.build(for: "贵州茅台怎么样", language: .zh)
        XCTAssertEqual(context.labels, ["600519.SH 贵州茅台"])
        XCTAssertGreaterThanOrEqual(stub.count("searchTickers"), 1)
    }

    func testBuilderPullsLiveModuleDataByIntent() async {
        let stub = StubDataProvider()
        let builder = AgentContextBuilder(data: stub)
        let context = await builder.build(for: "今天涨停情绪如何,龙虎榜谁在买,热度最高的是谁", language: .zh)
        XCTAssertEqual(context.labels, ["涨停情绪", "龙虎榜", "热度雷达"])
        XCTAssertTrue(context.blocks[0].hasPrefix("【涨停情绪市场脉冲"))
        XCTAssertTrue(context.blocks[1].hasPrefix("【龙虎榜资金流拓扑"))
        XCTAssertTrue(context.blocks[2].hasPrefix("【市场热度与飙升雷达"))
        XCTAssertEqual(stub.count("limitUpPool"), 1)
        XCTAssertEqual(stub.count("dragonTiger"), 2)
    }

    func testBuilderPrefersCachedModuleReports() async {
        let stub = StubDataProvider()
        var builder = AgentContextBuilder(data: stub)
        builder.cachedReports = { [.limitUp: "【缓存的涨停报告】"] }
        let context = await builder.build(for: "涨停情绪", language: .zh)
        XCTAssertEqual(context.blocks, ["【缓存的涨停报告】"])
        XCTAssertEqual(stub.count("limitUpPool"), 0)
    }

    func testBuilderSwallowsDataFailures() async {
        let stub = StubDataProvider()
        stub.failing = ["limitUpPool", "snapshot"]
        let builder = AgentContextBuilder(data: stub)
        let context = await builder.build(for: "600519 今天涨停情绪", language: .zh)
        XCTAssertTrue(context.isEmpty, "数据拉不到就不附带,不能让发消息失败")
    }

    func testPlainGreetingMakesNoRequests() async {
        let stub = StubDataProvider()
        let builder = AgentContextBuilder(data: stub)
        let context = await builder.build(for: "你好", language: .zh)
        XCTAssertTrue(context.isEmpty)
        XCTAssertTrue(stub.calls.isEmpty)
    }

    func testSystemPromptFollowsLanguage() {
        XCTAssertTrue(AgentContextBuilder.systemPrompt(language: .zh).contains("A股智能体"))
        XCTAssertTrue(AgentContextBuilder.systemPrompt(language: .en).contains("A-Share Agent"))
    }
}
