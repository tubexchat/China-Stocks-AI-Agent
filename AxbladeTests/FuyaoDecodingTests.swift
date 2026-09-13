import XCTest
@testable import Axblade

/// 用真实响应夹具验证每个端点的模型都能解码,且关键字段读对了。
final class FuyaoDecodingTests: XCTestCase {
    func testEnvelopeUnwrapsBusinessErrors() {
        let body = Data(#"{"code":2001,"message":"unauthorized","request_id":"x","data":null}"#.utf8)
        XCTAssertThrowsError(try FuyaoClient.unwrap(body, as: FuyaoList<TradingDay>.self)) { error in
            XCTAssertEqual(error as? FuyaoError, .api(code: 2001, message: "unauthorized"))
        }
    }

    func testEnvelopeWithMissingItemDecodesAsEmptyList() throws {
        let body = Data(#"{"code":0,"message":"success","data":{"timestamp":1}}"#.utf8)
        let list = try FuyaoClient.unwrap(body, as: FuyaoList<TradingDay>.self)
        XCTAssertTrue(list.item.isEmpty)
    }

    func testTradingDaysFixture() {
        let days = Fixtures.tradingDays
        XCTAssertEqual(days.count, 243)
        XCTAssertEqual(days.first?.date, "20250908")
    }

    func testLimitUpPoolFixture() {
        let items = Fixtures.limitUp
        XCTAssertEqual(items.count, 72)
        let first = items[0]
        XCTAssertEqual(first.name, "爱仕达")
        XCTAssertEqual(first.continue_day_cnt, 4)
        XCTAssertEqual(first.themes, ["人形机器人", "工业机器人", "炊具小家电"])
        XCTAssertEqual(first.limit_up_time, "09:25")
        XCTAssertEqual(Fixtures.limitBreak.count, 37)
        XCTAssertTrue(Fixtures.limitDown.isEmpty)
    }

    func testLadderFixtureUsesDashedDatesAndSealFlags() {
        let ladder = Fixtures.ladder
        XCTAssertEqual(ladder.item.count, 30)
        XCTAssertEqual(ladder.item.first?.date, "2026-09-08")
        XCTAssertNil(ladder.item.first?.boards.two_board.first?.seal_nextday, "最近一天没有次日数据")
        XCTAssertEqual(ladder.item[1].boards.two_board.first?.seal_nextday, true)
        XCTAssertEqual(ladder.item[1].boards.tiers.map(\.boards), [2, 3, 4, 5, 6, 7])
    }

    func testHotListFixturesParseHeatStrings() {
        let hot = Fixtures.hot
        XCTAssertEqual(hot.count, 30)
        XCTAssertEqual(hot.first?.name, "金健米业")
        XCTAssertEqual(hot.first?.heatValue, 5_842_339)
        XCTAssertEqual(Fixtures.surge.first?.rank, 1)
    }

    func testAnomalyFixture() {
        let items = Fixtures.anomalies
        XCTAssertEqual(items.count, 40)
        XCTAssertEqual(items.first?.stock_name, "ST富煌")
        XCTAssertEqual(items.first?.keyword_list, ["ST警示", "账户冻结", "业绩亏损"])
        XCTAssertEqual(items.first?.tag_name, "跌停")
    }

    func testDragonTigerFixtures() {
        let all = Fixtures.dragonAll
        XCTAssertEqual(all.trade_date, "2026-09-07")
        XCTAssertEqual(all.stock_items.count, 68)
        XCTAssertTrue(all.hot_money_items.isEmpty)
        XCTAssertEqual(all.stock_items.first?.concepts.first, "芯片概念")

        let org = Fixtures.dragonOrg
        XCTAssertEqual(org.stock_items.first?.org_buy_num, 3)

        let hotMoney = Fixtures.dragonHotMoney
        XCTAssertEqual(hotMoney.hot_money_items.count, 13)
        XCTAssertEqual(hotMoney.hot_money_items.first?.name, "低位挖掘")
        XCTAssertEqual(hotMoney.hot_money_items.first?.rows.count, 6)
        XCTAssertEqual(hotMoney.hot_money_items.first?.rows.first?.hot_money_item_net_value, 172_853_621.27)
    }

    func testSnapshotAndHistoricalFixtures() {
        XCTAssertEqual(Fixtures.fullSnapshot.count, 600)
        XCTAssertEqual(Fixtures.snapshot.first?.thscode, "600519.SH")
        XCTAssertEqual(Fixtures.snapshot.first?.last_price, 1309.3)
        XCTAssertEqual(Fixtures.stockBars.count, 267)
        XCTAssertEqual(Fixtures.indexBars.count, 267)
        XCTAssertGreaterThan(Fixtures.stockBars.last!.date_ms, Fixtures.stockBars.first!.date_ms)
        XCTAssertEqual(Fixtures.search.first?.name, "贵州茅台")
        XCTAssertEqual(Fixtures.rankTrend.count, 31)
        XCTAssertEqual(Fixtures.benchmark.first?.tags, ["粮油加工", "玉米"])
        XCTAssertEqual(Fixtures.industry.first?.name, "种植业与林业")
    }

    func testFinancialStatementFixtures() {
        let income = Fixtures.incomeAnnual
        XCTAssertEqual(income.count, 5)
        XCTAssertEqual(income.first?.fiscal_year, 2021)
        XCTAssertEqual(income.last?.periodLabel, "2025 FY")
        XCTAssertEqual(income.last?.operating_income, 6_028_985_966.48)
        XCTAssertNil(income.last?.interest_expenses, "null 保持缺失")
        XCTAssertEqual(income.last?.indicatorReport, "2025-4")

        let quarterly = Fixtures.incomeQuarterly
        XCTAssertEqual(quarterly.count, 8)
        XCTAssertEqual(quarterly.last?.periodLabel, "2026 Q2")
        XCTAssertEqual(quarterly.last?.indicatorReport, "2026-2")
        XCTAssertEqual(quarterly.last?.quarterIndex, 2)
        XCTAssertGreaterThan(quarterly.last!.operating_income!, quarterly[quarterly.count - 2].operating_income!, "季度值是年初至今累计")

        let balance = Fixtures.balanceAnnual
        XCTAssertEqual(balance.last?.cash, 14_036_333_777.03)
        XCTAssertEqual(balance.last?.total_debt, 6_341_039_595.3)
        let cash = Fixtures.cashFlowAnnual
        XCTAssertEqual(cash.last?.act_cash_flow_net, 3_774_236_497.7)
        XCTAssertEqual(cash.last?.pay_fixed_assets_etc_cash, 142_421_212.4)
        XCTAssertEqual(Set(income.map(\.period_end_ms)), Set(cash.map(\.period_end_ms)), "三表报告期一致")
    }

    func testFinancialIndicatorsFixture() {
        let data = Fixtures.indicators
        XCTAssertEqual(data.report, "2026-2")
        XCTAssertEqual(data.abilities.map(\.ability), ["growth", "profitability", "solvency", "operation", "cash-flow"])
        XCTAssertEqual(data.value("sale_gross_margin")!, 88.971, accuracy: 1e-9)
        XCTAssertNil(data.value("earned_interest_multiple"), "上游 null 不补零")
        XCTAssertNil(data.value("nope"))
        XCTAssertFalse(data.isEmpty)
        XCTAssertEqual(FinancialIndicatorCatalog.name("sale_gross_margin"), "销售毛利率")
        XCTAssertTrue(FinancialIndicatorCatalog.isPercent("sale_gross_margin"))
        XCTAssertFalse(FinancialIndicatorCatalog.isPercent("current_ratio"))
        XCTAssertEqual(FinancialIndicatorCatalog.display(FinancialIndicator(index_id: "sale_gross_margin", value: "88.9710")), "88.97%")
        XCTAssertEqual(FinancialIndicatorCatalog.display(FinancialIndicator(index_id: "current_ratio", value: "1.9394")), "1.94")
        XCTAssertEqual(FinancialIndicatorCatalog.display(FinancialIndicator(index_id: "current_ratio", value: nil)), "—")
    }

    func testConstituentsAndSearchFixtures() {
        XCTAssertEqual(Fixtures.constituents.first?.name, "国投丰乐")
        XCTAssertGreaterThan(Fixtures.constituents.count, 5)
        let ths = Fixtures.searchTHS
        XCTAssertEqual(ths.first?.thscode, "300033.SZ")
        XCTAssertEqual(ths.filter { $0.asset_type == "a-share" }.count, 1, "「同花顺」只对应一只 A 股,其余是指数")
    }

    func testFinancialRequestsAreSingleTickerAndClamped() throws {
        let client = FuyaoClient(keyProvider: { "sk-test" })
        let service = FuyaoDataService(client: client)
        _ = service
        let request = try client.makeRequest(path: "/api/a-share/financials/income-statements", query: ["thscode": "300033.SZ", "period": "annual", "limit": "5"])
        XCTAssertEqual(request.url?.absoluteString, "https://fuyao.aicubes.cn/api/a-share/financials/income-statements?limit=5&period=annual&thscode=300033.SZ")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-api-key"), "sk-test")
    }

    func testRequestCarriesAPIKeyHeaderAndSortedQuery() throws {
        let client = FuyaoClient(keyProvider: { "sk-test" })
        let request = try client.makeRequest(path: "/api/a-share/prices/snapshot", query: ["thscodes": "600519.SH", "limit": "10"])
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-api-key"), "sk-test")
        XCTAssertEqual(request.url?.absoluteString, "https://fuyao.aicubes.cn/api/a-share/prices/snapshot?limit=10&thscodes=600519.SH")
    }

    func testMissingKeyFailsBeforeAnyRequest() {
        let client = FuyaoClient(keyProvider: { nil })
        XCTAssertThrowsError(try client.makeRequest(path: "/x", query: [:])) { error in
            XCTAssertEqual(error as? FuyaoError, .missingKey)
        }
    }

    func testRateLimitIsRetriedThenSucceeds() async throws {
        MockHTTPProtocol.install([
            ("/calendar", 200, #"{"code":4001,"message":"rate limited","data":null}"#),
            ("/calendar", 200, #"{"code":0,"message":"ok","data":{"timestamp":1,"item":[{"date_ms":1,"date":"20260908"}]}}"#)
        ])
        var client = FuyaoClient(session: MockHTTPProtocol.session(), keyProvider: { "k" })
        client.sleeper = { _ in }
        let list = try await client.get("/api/a-share/calendar/trading-days", as: FuyaoList<TradingDay>.self)
        XCTAssertEqual(list.item.first?.date, "20260908")
    }

    func testHTTP429IsRetriedWithLongerBackoff() async throws {
        MockHTTPProtocol.install([
            ("/calendar", 429, ""),
            ("/calendar", 200, #"{"code":0,"message":"ok","data":{"timestamp":1,"item":[{"date_ms":1,"date":"20260908"}]}}"#)
        ])
        let waits = WaitLog()
        var client = FuyaoClient(session: MockHTTPProtocol.session(), keyProvider: { "k" })
        client.sleeper = { waits.record($0) }
        let list = try await client.get("/api/a-share/calendar/trading-days", as: FuyaoList<TradingDay>.self)
        XCTAssertEqual(list.item.count, 1)
        XCTAssertEqual(waits.values, [1.5])
        XCTAssertTrue(FuyaoError.http(429).isRetryable)
        XCTAssertTrue(FuyaoError.http(503).isRetryable)
        XCTAssertFalse(FuyaoError.http(404).isRetryable)
    }

    func testBusinessErrorSurfacesAsFuyaoError() async {
        MockHTTPProtocol.install([("/snapshot", 200, #"{"code":3001,"message":"not found","data":null}"#)])
        let client = FuyaoClient(session: MockHTTPProtocol.session(), keyProvider: { "k" })
        do {
            _ = try await client.get("/api/a-share/prices/snapshot", as: SnapshotData.self)
            XCTFail("应该抛错")
        } catch {
            XCTAssertEqual(error as? FuyaoError, .api(code: 3001, message: "not found"))
        }
    }

    private final class WaitLog: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var values: [Double] = []
        func record(_ value: Double) { lock.lock(); values.append(value); lock.unlock() }
    }

    // MARK: - 代码与日期工具

    func testSymbolNormalization() {
        XCTAssertEqual(AShareSymbol.normalize("600519"), "600519.SH")
        XCTAssertEqual(AShareSymbol.normalize("000001"), "000001.SZ")
        XCTAssertEqual(AShareSymbol.normalize("300750"), "300750.SZ")
        XCTAssertEqual(AShareSymbol.normalize("430001"), "430001.BJ")
        XCTAssertEqual(AShareSymbol.normalize("600519.ss"), "600519.SH")
        XCTAssertEqual(AShareSymbol.normalize("sh600519"), "600519.SH")
        XCTAssertEqual(AShareSymbol.normalize(" 000001.SZ "), "000001.SZ")
        XCTAssertEqual(AShareSymbol.normalize("AAPL"), "AAPL")
    }

    func testCodesExtractedFromFreeText() {
        XCTAssertEqual(AShareSymbol.codes(in: "看看 600519 和 000001.SZ,还有 sz300750,600519 重复"), ["600519.SH", "000001.SZ", "300750.SZ"])
        XCTAssertEqual(AShareSymbol.codes(in: "今天涨停 72 家,2026年9月8日"), [])
        XCTAssertEqual(AShareSymbol.codes(in: "1234567"), [], "7 位数字不是代码")
    }

    func testBoardClassification() {
        XCTAssertEqual(AShareSymbol.board(of: "688795.SH"), "科创板")
        XCTAssertEqual(AShareSymbol.board(of: "300684.SZ"), "创业板")
        XCTAssertEqual(AShareSymbol.board(of: "430001.BJ"), "北交所")
        XCTAssertEqual(AShareSymbol.board(of: "600519.SH"), "主板")
    }

    func testShanghaiDateHelpers() {
        XCTAssertEqual(ShanghaiDate.normalizeDay("20260908"), "2026-09-08")
        XCTAssertEqual(ShanghaiDate.normalizeDay("2026-09-08"), "2026-09-08")
        let date = ShanghaiDate.date("2026-09-08")!
        XCTAssertEqual(ShanghaiDate.startOfDayMs(date), 1_788_796_800_000)
        XCTAssertEqual(ShanghaiDate.string(date), "2026-09-08")
    }

    func testMoneyFormat() {
        XCTAssertEqual(MoneyFormat.yuan(1_786_253_128.23), "17.86亿")
        XCTAssertEqual(MoneyFormat.yuan(-30_600_000), "-3060万")
        XCTAssertEqual(MoneyFormat.yuan(1234), "1234")
    }
}
