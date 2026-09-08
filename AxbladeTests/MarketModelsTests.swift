import XCTest
@testable import Axblade

final class MarketModelsTests: XCTestCase {
    func testFiveModulesInDisplayOrder() {
        XCTAssertEqual(AgentModule.allCases, [.limitUpPulse, .dragonTigerTopology, .heatRadar, .marketTrend, .dragonTigerWatch])
        XCTAssertEqual(QuantTool.allCases, [.gbdt, .risk, .factor, .backtest])
    }

    func testNumberFormattingTrimsNoise() {
        XCTAssertEqual(MarketSnapshot.formatNumber(64038.0), "64038")
        XCTAssertEqual(MarketSnapshot.formatNumber(2.31), "2.31")
        XCTAssertEqual(MarketSnapshot.formatNumber(65379.13), "65379.13")
        XCTAssertEqual(MarketSnapshot.formatNumber(0.001234), "0.001234")
    }

    func testChipTextShowsNameAndSignedChange() {
        var snapshot = Self.sampleMoutai
        XCTAssertEqual(snapshot.chipText, "贵州茅台 -0.51%")

        snapshot.changePercent = 2.309
        XCTAssertEqual(snapshot.chipText, "贵州茅台 +2.31%")

        snapshot.changePercent = nil
        XCTAssertEqual(snapshot.chipText, "贵州茅台")

        snapshot.name = nil
        XCTAssertEqual(snapshot.chipText, "600519.SH")
    }

    func testPromptTextForAShare() {
        XCTAssertEqual(Self.sampleMoutai.promptText, """
        【A股行情 · 600519.SH(贵州茅台) · 2026-08-11 12:00】
        现价 1309.3 CNY;涨跌 -0.51%;高 1323 / 低 1309.05;成交额 23.03亿
        近3日收盘(旧→新): 1316.01, 1318, 1309.3
        """)
    }

    func testPromptTextOmitsMissingFields() {
        let snapshot = MarketSnapshot(symbol: "000001.SZ", price: 11.78, currency: nil, closes: [], fetchedAt: Self.noon)
        XCTAssertEqual(snapshot.promptText, """
        【A股行情 · 000001.SZ · 2026-08-11 12:00】
        现价 11.78
        """)
    }

    func testSnapshotBuiltFromFuyaoItem() {
        let item = Fixtures.snapshot[0]
        let snapshot = MarketSnapshot(from: item, name: "贵州茅台", closes: [1, 2], fetchedAt: Self.noon)
        XCTAssertEqual(snapshot.symbol, "600519.SH")
        XCTAssertEqual(snapshot.price, 1309.3)
        XCTAssertEqual(snapshot.changePercent, -0.509875)
        XCTAssertEqual(snapshot.turnover, 2_302_823_800)
        XCTAssertEqual(snapshot.currency, "CNY")
    }

    func testReportAttachmentUsesItsOwnText() {
        let attachment = MarketSnapshot(symbol: "涨停情绪", price: 0, closes: [], fetchedAt: Self.noon, reportText: "【涨停情绪】情绪分 66")
        XCTAssertEqual(attachment.chipText, "涨停情绪")
        XCTAssertEqual(attachment.promptText, "【涨停情绪】情绪分 66")
        XCTAssertEqual(attachment.promptText(in: .en), "【涨停情绪】情绪分 66")
    }

    // 2026-08-11 12:00 本地时区
    static let noon: Date = {
        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = 11
        components.hour = 12; components.minute = 0
        return Calendar.current.date(from: components)!
    }()

    static let sampleMoutai = MarketSnapshot(
        symbol: "600519.SH", name: "贵州茅台",
        price: 1309.3, changePercent: -0.509875,
        high: 1323, low: 1309.05, volume: 1_753_404, turnover: 2_302_823_800,
        closes: [1316.01, 1318, 1309.3], fetchedAt: noon
    )
}
