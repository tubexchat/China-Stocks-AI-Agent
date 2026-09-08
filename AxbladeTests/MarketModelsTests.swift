import XCTest
@testable import Axblade

final class MarketModelsTests: XCTestCase {
    func testSevenSourcesSplitIntoCryptoAndEquity() {
        XCTAssertEqual(MarketSourceKind.allCases, [.binance, .okx, .mexc, .usStock, .krStock, .hkStock, .aShare])
        XCTAssertEqual(MarketSourceKind.allCases.filter(\.isCrypto), [.binance, .okx, .mexc])
        XCTAssertEqual(MarketSourceKind.aShare.displayName, "A股")
        XCTAssertEqual(MarketSourceKind.mexc.displayName, "抹茶 MEXC")
    }

    func testNumberFormattingTrimsNoise() {
        XCTAssertEqual(MarketSnapshot.formatNumber(64038.0), "64038")
        XCTAssertEqual(MarketSnapshot.formatNumber(2.31), "2.31")
        XCTAssertEqual(MarketSnapshot.formatNumber(65379.13), "65379.13")
        XCTAssertEqual(MarketSnapshot.formatNumber(0.001234), "0.001234")
    }

    func testChipTextShowsSymbolAndSignedChange() {
        var snapshot = Self.sampleCrypto
        XCTAssertEqual(snapshot.chipText, "BTCUSDT -1.47%")

        snapshot.changePercent = 2.309
        XCTAssertEqual(snapshot.chipText, "BTCUSDT +2.31%")

        snapshot.changePercent = nil
        XCTAssertEqual(snapshot.chipText, "BTCUSDT")
    }

    func testPromptTextForCrypto() {
        let text = Self.sampleCrypto.promptText
        XCTAssertEqual(text, """
        【行情数据 · Binance · BTCUSDT · 2026-08-11 12:00】
        现价 64038;24h 涨跌 -1.47%;高 65379.13 / 低 63806.27;量 13675.87
        近3日收盘(旧→新): 64962.6, 63970.01, 64038
        """)
    }

    func testPromptTextForEquityIncludesNameAndCurrency() {
        let snapshot = MarketSnapshot(
            source: .usStock, symbol: "AAPL", name: "Apple Inc.",
            price: 308.26, changePercent: 1.595,
            high: 308.26, low: 304.63, volume: 43_391_681, currency: "USD",
            closes: [303.42, 308.26], fetchedAt: Self.noon
        )
        XCTAssertEqual(snapshot.promptText, """
        【行情数据 · 美股 · AAPL(Apple Inc.) · 2026-08-11 12:00】
        现价 308.26 USD;24h 涨跌 +1.6%;高 308.26 / 低 304.63;量 43391681
        近2日收盘(旧→新): 303.42, 308.26
        """)
    }

    func testPromptTextOmitsMissingFields() {
        let snapshot = MarketSnapshot(
            source: .okx, symbol: "BTC-USDT", name: nil,
            price: 64039.4, changePercent: nil,
            high: nil, low: nil, volume: nil, currency: nil,
            closes: [], fetchedAt: Self.noon
        )
        XCTAssertEqual(snapshot.promptText, """
        【行情数据 · OKX · BTC-USDT · 2026-08-11 12:00】
        现价 64039.4
        """)
    }

    // 2026-08-11 12:00 本地时区
    static let noon: Date = {
        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = 11
        components.hour = 12; components.minute = 0
        return Calendar.current.date(from: components)!
    }()

    static let sampleCrypto = MarketSnapshot(
        source: .binance, symbol: "BTCUSDT", name: nil,
        price: 64038.0, changePercent: -1.468,
        high: 65379.13, low: 63806.27, volume: 13675.871, currency: nil,
        closes: [64962.6, 63970.01, 64038.0], fetchedAt: noon
    )
}
