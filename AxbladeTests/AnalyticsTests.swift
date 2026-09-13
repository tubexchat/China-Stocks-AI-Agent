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

    // MARK: - 行业强度作战矩阵

    private func industrySeries(scale: Double, turnoverBoost: Double = 1) -> [PriceBar] {
        Fixtures.indexBars.enumerated().map { index, bar in
            var copy = bar
            copy.close_price = bar.close * pow(scale, Double(index) / Double(Fixtures.indexBars.count))
            if index >= Fixtures.indexBars.count - 5 { copy.turnover = (bar.turnover ?? 0) * turnoverBoost }
            return copy
        }
    }

    func testIndustryStrengthRanksRelativeToBenchmark() throws {
        let benchmark = SectorSeries(thscode: "000300.SH", name: "沪深300", bars: Fixtures.indexBars)
        let sectors = [
            SectorSeries(thscode: "A.TI", name: "强势", bars: industrySeries(scale: 1.4, turnoverBoost: 2)),
            SectorSeries(thscode: "B.TI", name: "跟随", bars: Fixtures.indexBars),
            SectorSeries(thscode: "C.TI", name: "弱势", bars: industrySeries(scale: 0.7))
        ]
        let report = try XCTUnwrap(IndustryStrengthAnalyzer.run(benchmark: benchmark, sectors: sectors))
        XCTAssertEqual(report.rows.map(\.name), ["强势", "跟随", "弱势"])
        XCTAssertEqual(report.rows[0].rank, 1)
        XCTAssertEqual(report.rows[2].rank, 3)
        let follower = report.rows[1]
        XCTAssertEqual(follower.rs20!, 0, accuracy: 1e-9, "与基准同走势 → 相对强度为 0")
        XCTAssertEqual(follower.ret20!, report.benchmarkRet20!, accuracy: 1e-12)
        XCTAssertGreaterThan(report.rows[0].rs20!, 0)
        XCTAssertLessThan(report.rows[2].rs20!, 0)
        XCTAssertGreaterThan(report.rows[0].turnoverPulse!, follower.turnoverPulse!)
        XCTAssertEqual(follower.turnoverPulse!, IndustryStrengthAnalyzer.turnoverPulse(Fixtures.indexBars.map { $0.turnover ?? 0 })!, accuracy: 1e-12)
        XCTAssertEqual(report.rows[0].score, 100)
        XCTAssertEqual(report.rows[2].score, 0)
        XCTAssertEqual(report.breadth.total, 3)
        XCTAssertEqual(report.breadth.outperform20, 1)
        XCTAssertEqual(report.recentDates.count, 20)
        XCTAssertEqual(report.rows[0].recentReturns.count, 20)
        XCTAssertEqual(report.dataDate, ShanghaiDate.string(Fixtures.indexBars.last!.date))
        XCTAssertNotNil(report.rows[0].previousRank)
        XCTAssertTrue(report.promptText.contains("最强行业"))
        XCTAssertNil(IndustryStrengthAnalyzer.run(benchmark: nil, sectors: []))
    }

    func testIndustryStrengthWithoutBenchmarkFallsBackToAbsolute() throws {
        let sectors = [SectorSeries(thscode: "A.TI", name: "A", bars: Fixtures.indexBars)]
        let report = try XCTUnwrap(IndustryStrengthAnalyzer.run(benchmark: nil, sectors: sectors))
        XCTAssertNil(report.benchmarkName)
        XCTAssertEqual(report.rows[0].rs20, report.rows[0].ret20)
        XCTAssertEqual(IndustryStrengthAnalyzer.percentile(5, in: [1, 5, 9]), 50)
        XCTAssertNil(IndustryStrengthAnalyzer.turnoverPulse(Array(repeating: 0, count: 30)))
        XCTAssertNil(IndustryStrengthAnalyzer.trailingReturn([1, 2, 3], 5))
    }

    func testConstituentEvidenceUsesEqualWeightProxy() {
        let members = [
            TickerSearchItem(thscode: "600519.SH", ticker: "600519", name: "贵州茅台", exchange: "SH", asset_type: "a-share", currency: "CNY"),
            TickerSearchItem(thscode: "000001.SZ", ticker: "000001", name: "平安银行", exchange: "SZ", asset_type: "a-share", currency: "CNY"),
            TickerSearchItem(thscode: "999999.SZ", ticker: "999999", name: "无报价", exchange: "SZ", asset_type: "a-share", currency: "CNY")
        ]
        let index = PriceSnapshotItem(thscode: "881101.TI", price_change_ratio_pct: 1.5)
        let evidence = IndustryConstituentAnalyzer.run(thscode: "881101.TI", name: "测试行业", constituents: members, snapshot: Fixtures.snapshot, indexSnapshot: index)
        XCTAssertEqual(evidence.total, 3)
        XCTAssertEqual(evidence.priced, 2, "没有报价的成分不计入涨跌家数")
        XCTAssertEqual(evidence.up, 1)
        XCTAssertEqual(evidence.down, 1)
        XCTAssertEqual(evidence.equalWeightChange!, (-0.509875 + 0.683761) / 2, accuracy: 1e-9)
        XCTAssertEqual(evidence.indexChange, 1.5)
        XCTAssertEqual(evidence.weightGap!, 1.5 - evidence.equalWeightChange!, accuracy: 1e-9)
        XCTAssertNotNil(evidence.dispersion)
        XCTAssertEqual(evidence.topGainers.first?.name, "平安银行")
        XCTAssertEqual(evidence.topTurnover.first?.name, "贵州茅台")
        XCTAssertEqual(evidence.top5TurnoverShare!, 1, accuracy: 1e-9)
        XCTAssertTrue(evidence.promptText.contains("不是指数贡献"))
    }

    // MARK: - 现金流质量稽核台

    func testCashFlowMetricsMatchDefinitionsAndLeaveBlanksOnZero() {
        let income = Fixtures.incomeAnnual.last!, balance = Fixtures.balanceAnnual.last!, cash = Fixtures.cashFlowAnnual.last!
        let m = CashFlowMetrics.compute(income: income, balance: balance, cashFlow: cash)
        XCTAssertEqual(m.cashConversion!, 3_774_236_497.7 / 3_205_102_614.07, accuracy: 1e-12)
        XCTAssertEqual(m.fcfMargin!, (3_774_236_497.7 - 142_421_212.4) / 6_028_985_966.48, accuracy: 1e-12)
        XCTAssertEqual(m.accrualRatio!, (3_205_102_614.07 - 3_774_236_497.7) / 15_832_994_333.52, accuracy: 1e-12)
        XCTAssertEqual(m.receivablePressure!, 20_639_274.98 / 6_028_985_966.48, accuracy: 1e-12)
        XCTAssertEqual(m.netCashRatio!, (14_036_333_777.03 - 6_341_039_595.3) / 15_832_994_333.52, accuracy: 1e-12)

        var zeroProfit = income
        zeroProfit.net_profit = 0
        XCTAssertNil(CashFlowMetrics.compute(income: zeroProfit, balance: balance, cashFlow: cash).cashConversion, "分母为 0 留空")
        var noCapex = cash
        noCapex.pay_fixed_assets_etc_cash = nil
        XCTAssertNil(CashFlowMetrics.compute(income: income, balance: balance, cashFlow: noCapex).fcfMargin, "任一侧缺失留空")
        XCTAssertNil(CashFlowMetrics.compute(income: nil, balance: nil, cashFlow: nil).netCashRatio)
    }

    func testCashFlowAuditAlignsPeriodsAndGatesByReportDate() {
        let input = CashFlowAuditAnalyzer.Input(thscode: "300033.SZ", name: "同花顺", income: Fixtures.incomeAnnual, balance: Fixtures.balanceAnnual, cashFlow: Fixtures.cashFlowAnnual)
        let report = CashFlowAuditAnalyzer.run(asOf: Date(timeIntervalSince1970: 1_800_000_000), inputs: [input])
        let company = report.companies[0]
        XCTAssertEqual(company.periods.count, 5)
        XCTAssertEqual(company.periods.map(\.label), ["2021 FY", "2022 FY", "2023 FY", "2024 FY", "2025 FY"])
        XCTAssertTrue(company.periods.allSatisfy { $0.income != nil && $0.balance != nil && $0.cashFlow != nil })
        XCTAssertEqual(company.yearsComparable, 5)
        XCTAssertEqual(company.yearsCashCovered, 5, "同花顺 2021–2025 每年经营现金流都高于净利润")
        XCTAssertEqual(company.missingFields, 0)
        XCTAssertEqual(company.expectedFields, 40)
        XCTAssertEqual(report.fields.count, 8)
        XCTAssertTrue(report.fields.allSatisfy { $0.present == 5 && $0.expected == 5 })
        XCTAssertEqual(report.overallCompleteness, 1)
        XCTAssertNotNil(company.fcfTotal)

        // 披露时点回拨到 2026-01-01:2025 年报(披露 2026-03-10)和 2024 年报(重述披露日同为 2026-03-10)都还看不到。
        let earlier = CashFlowAuditAnalyzer.run(asOf: ShanghaiDate.date("2026-01-01")!, inputs: [input]).companies[0]
        XCTAssertEqual(earlier.periods.last?.label, "2023 FY")
        XCTAssertEqual(earlier.periods.count, 3)

        let failed = CashFlowAuditAnalyzer.run(asOf: Date(), inputs: [.init(thscode: "000001.SZ", name: "x", error: "boom")])
        XCTAssertEqual(failed.failed.count, 1)
        XCTAssertTrue(failed.loaded.isEmpty)
        XCTAssertTrue(failed.promptText.contains("取数失败"))
    }

    func testCashFlowAuditSortingPutsBlanksLast() {
        var partial = Fixtures.incomeAnnual
        partial[4].net_profit = nil
        let inputs = [
            CashFlowAuditAnalyzer.Input(thscode: "A.SZ", name: "有值", income: Fixtures.incomeAnnual, balance: Fixtures.balanceAnnual, cashFlow: Fixtures.cashFlowAnnual),
            CashFlowAuditAnalyzer.Input(thscode: "B.SZ", name: "缺净利", income: partial, balance: Fixtures.balanceAnnual, cashFlow: Fixtures.cashFlowAnnual)
        ]
        let report = CashFlowAuditAnalyzer.run(asOf: Date(timeIntervalSince1970: 1_800_000_000), inputs: inputs)
        XCTAssertNil(report.companies[1].latest?.metrics.cashConversion)
        XCTAssertEqual(report.sorted(by: .cashConversion).map(\.name), ["有值", "缺净利"])
        XCTAssertEqual(report.companies[1].missingFields, 1)
        XCTAssertEqual(report.fields.first { $0.field == "net_profit" }?.present, 9)
        XCTAssertLessThan(report.overallCompleteness, 1)
    }

    // MARK: - 单股财务体检

    func testFinancialHealthAlignsQuartersAndDerivesSingleQuarter() throws {
        let report = FinancialHealthAnalyzer.run(
            thscode: "300033.SZ", name: "同花顺",
            income: Fixtures.incomeQuarterly, balance: Fixtures.balanceQuarterly, cashFlow: Fixtures.cashFlowQuarterly,
            indicators: Fixtures.indicators, indicatorReport: "2026-2"
        )
        XCTAssertEqual(report.periods.count, 8)
        XCTAssertEqual(report.periods.map(\.label), ["2024 Q3", "2024 Q4", "2025 Q1", "2025 Q2", "2025 Q3", "2025 Q4", "2026 Q1", "2026 Q2"])
        XCTAssertEqual(report.completePeriods, 8)
        let latest = try XCTUnwrap(report.latest)
        XCTAssertEqual(latest.revenue, 2_645_653_616.14)
        // 单季 = Q2 累计 − Q1 累计
        XCTAssertEqual(latest.revenueQ!, 2_645_653_616.14 - 1_053_494_727.58, accuracy: 1e-6)
        XCTAssertEqual(latest.netProfitQ!, 952_339_823.8 - 255_922_385.71, accuracy: 1e-6)
        // Q1 单季 = 累计本身
        let q1 = report.periods[6]
        XCTAssertEqual(q1.revenueQ, q1.revenue)
        // 2024 Q3 的上一期(2024 Q2)不在 8 期里 → 单季留空
        XCTAssertNil(report.periods[0].revenueQ)
        // 同比:2026 Q2 vs 2025 Q2
        XCTAssertEqual(latest.revenueYoY!, (2_645_653_616.14 - 1_779_405_283.66) / 1_779_405_283.66, accuracy: 1e-9)
        XCTAssertNil(report.periods[0].revenueYoY, "8 期里没有 2023 Q3")
        XCTAssertEqual(report.yearAgo?.label, "2025 Q2")
        XCTAssertEqual(report.previous?.label, "2026 Q1")
        XCTAssertNotNil(latest.grossMargin)
        XCTAssertNotNil(latest.debtRatio)
        XCTAssertEqual(latest.fcf!, 2_219_388_283.46 - 89_055_588.26, accuracy: 1e-6)
        XCTAssertEqual(report.currency, "CNY")
        XCTAssertEqual(report.indicatorReport, "2026-2")
        XCTAssertTrue(report.promptText.contains("累计"))
        XCTAssertTrue(report.promptText.contains("不补零"))
    }

    func testFinancialHealthKeepsNullsAndHandlesMissingStatements() {
        var income = Fixtures.incomeQuarterly
        income[7].operating_income = nil
        let report = FinancialHealthAnalyzer.run(
            thscode: "300033.SZ", name: "同花顺", income: income, balance: [], cashFlow: Array(Fixtures.cashFlowQuarterly.prefix(7)),
            indicators: nil, indicatorReport: nil
        )
        XCTAssertNil(report.latest?.revenue)
        XCTAssertNil(report.latest?.revenueQ)
        XCTAssertNil(report.latest?.revenueYoY)
        XCTAssertNil(report.latest?.grossMargin)
        XCTAssertNil(report.latest?.debtRatio, "没有资产负债表 → 杠杆留空")
        XCTAssertNil(report.latest?.ocf, "最新期现金流量表缺失")
        XCTAssertEqual(report.completePeriods, 0)
        XCTAssertNil(FinancialHealthAnalyzer.yoy(current: 1, previous: 0))
        XCTAssertNil(FinancialHealthAnalyzer.singleQuarter(current: 10, previousCumulative: nil, quarter: 3))
        XCTAssertEqual(FinancialHealthAnalyzer.singleQuarter(current: 10, previousCumulative: nil, quarter: 1), 10)
        XCTAssertEqual(FinancialHealthAnalyzer.yoy(current: 90, previous: -100)!, 1.9, accuracy: 1e-12)
    }
}
