import XCTest
@testable import Axblade

/// 五个模块的本地分析引擎,全部喂真实夹具。
final class AnalyticsTests: XCTestCase {
    // MARK: - 涨停情绪

    func testLimitUpPulseReportCountsAndClusters() {
        let report = LimitUpPulseAnalyzer.run(
            date: "2026-09-08", limitUp: Fixtures.limitUp, limitDown: Fixtures.limitDown,
            limitBreak: Fixtures.limitBreak, ladder: Fixtures.ladder
        )
        XCTAssertEqual(report.limitUpCount, 72)
        XCTAssertEqual(report.breakCount, 37)
        XCTAssertEqual(report.limitDownCount, 0)
        XCTAssertEqual(report.firstBoardCount, 54)
        XCTAssertEqual(report.consecutiveCount, 18)
        XCTAssertEqual(report.highestBoard, 4)
        XCTAssertEqual(report.boardDistribution, [1: 54, 2: 12, 3: 3, 4: 3])
        XCTAssertEqual(report.sealRate, 72.0 / 109.0, accuracy: 1e-9)
        XCTAssertEqual(report.timeBuckets.map(\.count).reduce(0, +), 72)
        XCTAssertEqual(report.timeBuckets[0].label, "竞价一字")
        XCTAssertEqual(report.leaders.first?.boards, 4)
        XCTAssertTrue(report.leaders.prefix(3).map(\.name).contains("爱仕达"))
        XCTAssertGreaterThanOrEqual(report.themes.first!.count, report.themes.last!.count)
        XCTAssertTrue(report.themes.allSatisfy { $0.count >= 2 })
        XCTAssertEqual(report.ladder.count, 30)
        XCTAssertEqual(report.ladder.first?.date, "2026-07-29", "天梯按日期升序")
        XCTAssertNil(report.ladder.last?.promotionRate, "最近一天没有晋级率")
        XCTAssertNotNil(report.ladder[report.ladder.count - 2].promotionRate)
        XCTAssertTrue((0...100).contains(report.score))
        XCTAssertEqual(report.regime, LimitUpPulseReport.regime(for: report.score))
        XCTAssertTrue(report.promptText.contains("涨停 72 家 / 跌停 0 家 / 炸板 37 家"))
    }

    func testTimeBuckets() {
        XCTAssertEqual(LimitUpPulseAnalyzer.timeBucketIndex("09:25"), 0)
        XCTAssertEqual(LimitUpPulseAnalyzer.timeBucketIndex("09:31"), 1)
        XCTAssertEqual(LimitUpPulseAnalyzer.timeBucketIndex("10:00"), 2)
        XCTAssertEqual(LimitUpPulseAnalyzer.timeBucketIndex("13:05"), 3)
        XCTAssertEqual(LimitUpPulseAnalyzer.timeBucketIndex("14:57"), 4)
        XCTAssertNil(LimitUpPulseAnalyzer.timeBucketIndex(nil))
    }

    func testSentimentScoreBounds() {
        XCTAssertEqual(LimitUpPulseAnalyzer.sentimentScore(sealRate: 1, limitUp: 100, limitDown: 0, consecutiveRatio: 0.5, highestBoard: 8, promotionRate: 1), 100)
        XCTAssertEqual(LimitUpPulseAnalyzer.sentimentScore(sealRate: 0, limitUp: 0, limitDown: 100, consecutiveRatio: 0, highestBoard: 0, promotionRate: 0), 0)
        XCTAssertEqual(LimitUpPulseReport.regime(for: 10), "冰点")
        XCTAssertEqual(LimitUpPulseReport.regime(for: 85), "亢奋")
    }

    // MARK: - 龙虎榜拓扑

    func testFlowGraphHasThreeLayersAndSignedEdges() {
        let graph = FlowGraphBuilder.build(date: "2026-09-07", all: Fixtures.dragonAll, hotMoney: Fixtures.dragonHotMoney)
        let players = graph.nodes(of: .player)
        XCTAssertEqual(players.count, 14, "13 个游资 + 机构")
        XCTAssertNotNil(graph.node(FlowGraph.institutionID))
        XCTAssertEqual(graph.nodes(of: .stock).count, 67, "同一股票的当日榜与 3 日榜合并")
        XCTAssertEqual(graph.nodes(of: .concept).count, 14)
        let lowBuyer = players.first { $0.label == "低位挖掘" }!
        XCTAssertEqual(lowBuyer.net, 205_157_361.25, accuracy: 1)
        let chengdu = players.first { $0.label == "成都系" }!
        XCTAssertLessThan(chengdu.net, 0)
        let edge = graph.edges.first { $0.from == "player:成都系" }!
        XCTAssertLessThan(edge.value, 0)
        XCTAssertTrue(graph.neighbors(of: "player:低位挖掘").contains("stock:300684.SZ"))
        XCTAssertTrue(graph.promptText.contains("席位净买入"))
    }

    // MARK: - 机构与游资观察

    func testWatchAggregatesAcrossDays() {
        var day2All = Fixtures.dragonAll
        day2All.trade_date = "2026-09-08"
        var day2Hot = Fixtures.dragonHotMoney
        day2Hot.trade_date = "2026-09-08"
        let report = DragonTigerWatchAnalyzer.run(days: [
            ("2026-09-07", Fixtures.dragonAll, Fixtures.dragonHotMoney),
            ("2026-09-08", day2All, day2Hot)
        ])
        XCTAssertEqual(report.dates, ["2026-09-07", "2026-09-08"])
        XCTAssertEqual(report.stocks.count, 67)
        XCTAssertTrue(report.stocks.allSatisfy { $0.appearances == 2 })
        XCTAssertEqual(report.repeated.count, 67)
        XCTAssertEqual(report.players.count, 13)
        let lowBuyer = report.players.first { $0.name == "低位挖掘" }!
        XCTAssertEqual(lowBuyer.netTotal, 2 * 205_157_361.25, accuracy: 1)
        XCTAssertEqual(lowBuyer.appearances, 12)
        XCTAssertEqual(lowBuyer.days, ["2026-09-07", "2026-09-08"])
        XCTAssertFalse(lowBuyer.conceptCounts.isEmpty)
        XCTAssertEqual(report.orgBuys.first?.name, "景旺电子")
        XCTAssertEqual(report.orgSells.first?.name, "摩尔线程")
        XCTAssertEqual(report.rows.count, 2 * Fixtures.dragonHotMoney.hot_money_items.flatMap(\.rows).count)
        XCTAssertTrue(report.promptText.contains("2 个交易日"))
    }

    // MARK: - 热度雷达

    func testHeatRadarCrossReferencesLists() {
        let report = HeatRadarAnalyzer.run(period: .day, hot: Fixtures.hot, surge: Fixtures.surge, anomalies: Fixtures.anomalies)
        XCTAssertEqual(report.points.filter { $0.hotRank != nil }.count, 30)
        XCTAssertEqual(report.points.filter { $0.surgeRank != nil }.count, 30)
        XCTAssertFalse(report.resonance.isEmpty)
        XCTAssertTrue(report.resonance.allSatisfy { $0.hotRank != nil && $0.surgeRank != nil })
        XCTAssertEqual(report.resonance.first?.name, "金健米业")
        XCTAssertEqual(report.tags.map(\.tag).sorted(), Set(Fixtures.anomalies.map(\.tag_name)).sorted())
        XCTAssertEqual(report.tags.map(\.count).reduce(0, +), 40)
        XCTAssertTrue(report.keywords.first!.count >= report.keywords.last!.count)
        XCTAssertTrue(report.climbers.allSatisfy { ($0.rankChange ?? 0) > 0 })
        XCTAssertTrue(report.promptText.contains("热股榜 Top15"))
    }

    // MARK: - 全市场趋势

    func testMarketBreadthFromSnapshot() {
        let breadth = MarketBreadth.compute(date: "2026-09-08", items: Fixtures.fullSnapshot)
        XCTAssertEqual(breadth.total, breadth.up + breadth.down + breadth.flat)
        XCTAssertGreaterThan(breadth.total, 500)
        XCTAssertEqual(breadth.buckets.map(\.count).reduce(0, +), breadth.total)
        XCTAssertEqual(breadth.buckets.count, 11)
        XCTAssertGreaterThan(breadth.totalTurnover, 0)
        XCTAssertTrue((0...1).contains(breadth.top100TurnoverShare))
        XCTAssertEqual(breadth.topGainers.count, 10)
        XCTAssertGreaterThanOrEqual(breadth.topGainers[0].price_change_ratio_pct!, breadth.topGainers[1].price_change_ratio_pct!)
        XCTAssertLessThanOrEqual(breadth.topLosers[0].price_change_ratio_pct!, breadth.topLosers[1].price_change_ratio_pct!)
        XCTAssertFalse(breadth.boards.isEmpty)
        XCTAssertEqual(breadth.boards.map(\.total).reduce(0, +), breadth.total)
    }

    func testTrendMetricsOnIndexBars() throws {
        let closes = Fixtures.indexBars.map(\.close)
        let metrics = try XCTUnwrap(TrendMetrics.compute(closes: closes))
        XCTAssertEqual(metrics.last, closes.last!)
        XCTAssertEqual(metrics.ret20, closes.last! / closes[closes.count - 21] - 1, accuracy: 1e-12)
        XCTAssertNotNil(metrics.ma60)
        XCTAssertFalse(metrics.bullishAlignment && metrics.bearishAlignment)
        XCTAssertTrue((0...1).contains(metrics.rangePosition))
        XCTAssertTrue((0...100).contains(metrics.score))
        XCTAssertNil(TrendMetrics.compute(closes: [1]))
    }

    func testMarketTrendReportRanksSectors() {
        let series = Fixtures.industry.enumerated().map { index, item in
            // 给每个板块一条略有差异的序列,保证排序确定
            SectorSeries(thscode: item.thscode, name: item.name, bars: Fixtures.indexBars.map { bar in
                var copy = bar
                copy.close_price = bar.close * (1 + Double(index) * 0.001 * Double(bar.date_ms % 7))
                return copy
            })
        }
        let indices = [SectorSeries(thscode: "000001.SH", name: "上证指数", bars: Fixtures.indexBars)]
        let breadth = MarketBreadth.compute(date: "2026-09-08", items: Fixtures.fullSnapshot)
        let report = MarketTrendAnalyzer.run(breadth: breadth, breadthHistory: [breadth], indices: indices, sectors: series, sectorTag: "industry")
        XCTAssertEqual(report.sectors.count, 12)
        XCTAssertEqual(report.indices.first?.name, "上证指数")
        XCTAssertGreaterThanOrEqual(report.strongest.first!.score, report.strongest.last!.score)
        XCTAssertEqual(report.weakest.first?.id, report.strongest.last?.id)
        XCTAssertEqual(report.recentDates.count, 10)
        XCTAssertEqual(report.sectors.first?.recentReturns.count, 10)
        XCTAssertFalse(report.regime.isEmpty)
        XCTAssertTrue(report.promptText.contains("最强板块"))
    }

    func testSeriesMergeDedupesAndTrims() {
        let a = PriceBar(date_ms: 1, close_price: 1)
        let b = PriceBar(date_ms: 2, close_price: 2)
        let b2 = PriceBar(date_ms: 2, close_price: 2.5)
        let c = PriceBar(date_ms: 3, close_price: 3)
        let merged = SeriesMerge.merge(cached: [a, b], fresh: [b2, c], keep: 2)
        XCTAssertEqual(merged.map(\.date_ms), [2, 3])
        XCTAssertEqual(merged.first?.close, 2.5, "新数据覆盖旧数据")
    }

    func testResearchStoreRoundTrips() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AxbladeResearch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MarketResearchStore(directory: directory)
        let series = [SectorSeries(thscode: "881101.TI", name: "种植业", bars: Array(Fixtures.indexBars.prefix(5)))]
        try store.saveSeries(series, tag: "industry")
        XCTAssertEqual(store.loadSeries(tag: "industry"), series)
        let breadth = MarketBreadth.compute(date: "2026-09-08", items: Array(Fixtures.fullSnapshot.prefix(50)))
        try store.appendBreadth(breadth)
        try store.appendBreadth(breadth)
        XCTAssertEqual(store.loadBreadthHistory().count, 1, "同一天覆盖")
        try store.saveSnapshot(date: "2026-09-08", items: Array(Fixtures.fullSnapshot.prefix(3)))
        XCTAssertEqual(store.loadSnapshot()?.items.count, 3)
        XCTAssertGreaterThan(store.diskUsage(), 0)
        store.clear()
        XCTAssertTrue(store.loadSeries(tag: "industry").isEmpty)
    }
}
