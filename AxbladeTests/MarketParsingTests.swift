import XCTest
@testable import Axblade

/// fixture 全部来自 2026-08-11 对真实端点的抓取,只删减了无关字段。
final class MarketParsingTests: XCTestCase {
    private let noon = MarketModelsTests.noon

    // MARK: - Binance

    func testBinanceTickerAndKlines() throws {
        let ticker = #"{"symbol":"BTCUSDT","priceChangePercent":"-1.468","lastPrice":"64038.00000000","highPrice":"65379.13000000","lowPrice":"63806.27000000","volume":"13675.87112000"}"#
        let klines = #"[[1786233600000,"64962.60000000","65474.46","64730.08","64901.59000000","7031.2",1786319999999,"457366207",803981,"3207","208616902","0"],[1786320000000,"64901.59","65391.14","63806.27","63970.01000000","13638.4",1786406399999,"880502559",2054347,"6946","448395344","0"]]"#

        let snapshot = try BinanceMarketService.parse(
            symbol: "BTCUSDT", tickerData: Data(ticker.utf8), klinesData: Data(klines.utf8), fetchedAt: noon
        )

        XCTAssertEqual(snapshot.source, .binance)
        XCTAssertEqual(snapshot.price, 64038.0)
        XCTAssertEqual(snapshot.changePercent, -1.468)   // Binance 直接给百分数
        XCTAssertEqual(snapshot.high, 65379.13)
        XCTAssertEqual(snapshot.low, 63806.27)
        XCTAssertEqual(snapshot.volume, 13675.87112)
        XCTAssertEqual(snapshot.closes, [64901.59, 63970.01])
    }

    func testBinanceInvalidSymbolCode() {
        let body = #"{"code":-1121,"msg":"Invalid symbol."}"#

        XCTAssertThrowsError(
            try BinanceMarketService.parse(
                symbol: "XXXUSDT", tickerData: Data(body.utf8), klinesData: Data("[]".utf8), fetchedAt: noon
            )
        ) { error in
            XCTAssertEqual(error as? MarketDataError, .invalidSymbol("XXXUSDT"))
        }
    }

    /// 地区封锁(HTTP 451)的响应不能误报成「代码不存在」,要把服务端消息带给用户。
    func testBinanceRestrictedLocationSurfacesServerMessage() {
        let body = #"{"code":0,"msg":"Service unavailable from a restricted location according to 'b. Eligibility' in https://www.binance.com/en/terms."}"#

        XCTAssertThrowsError(
            try BinanceMarketService.parse(
                symbol: "BTCUSDT", tickerData: Data(body.utf8), klinesData: Data("[]".utf8), fetchedAt: noon
            )
        ) { error in
            guard case .network(let message)? = error as? MarketDataError else {
                return XCTFail("应报 network,实际 \(error)")
            }
            XCTAssertTrue(message.contains("restricted location"), message)
        }
    }

    // MARK: - MEXC:priceChangePercent 是小数,必须 ×100

    func testMEXCChangePercentIsAFractionNotAPercent() throws {
        let ticker = #"{"symbol":"BTCUSDT","priceChangePercent":"-0.0149","lastPrice":"64034.6","highPrice":"65369.57","lowPrice":"63824.58","volume":"6808.333275"}"#
        let klines = #"[[1786320000000,"64901.59","65391.14","63806.27","63970.01","13638.4",1786406399999,"880502559"]]"#

        let snapshot = try MEXCMarketService.parse(
            symbol: "BTCUSDT", tickerData: Data(ticker.utf8), klinesData: Data(klines.utf8), fetchedAt: noon
        )

        XCTAssertEqual(snapshot.source, .mexc)
        XCTAssertEqual(snapshot.changePercent!, -1.49, accuracy: 0.0001)
    }

    // MARK: - OKX:自算涨跌,candles 新→旧要反转

    func testOKXComputesChangeAndReversesCandles() throws {
        let ticker = #"{"code":"0","msg":"","data":[{"instId":"BTC-USDT","last":"64039.4","open24h":"65010","high24h":"65368","low24h":"63818.1","vol24h":"3382.90837753"}]}"#
        let candles = #"{"code":"0","msg":"","data":[["1786377600000","64298","64355.8","63818.1","64039.4","1435.5","91906590","91906590","0"],["1786291200000","65230.4","65490.3","64205.6","64298","3098.0","201179206","201179206","1"]]}"#

        let snapshot = try OKXMarketService.parse(
            symbol: "BTC-USDT", tickerData: Data(ticker.utf8), klinesData: Data(candles.utf8), fetchedAt: noon
        )

        XCTAssertEqual(snapshot.price, 64039.4)
        XCTAssertEqual(snapshot.changePercent!, (64039.4 - 65010) / 65010 * 100, accuracy: 0.0001)
        XCTAssertEqual(snapshot.closes, [64298, 64039.4])   // 反转成旧→新
        XCTAssertEqual(snapshot.volume, 3382.90837753)
    }

    func testOKXUnknownInstrumentThrowsInvalidSymbol() {
        let empty = #"{"code":"51001","msg":"Instrument ID does not exist","data":[]}"#

        XCTAssertThrowsError(
            try OKXMarketService.parse(
                symbol: "XXX-USDT", tickerData: Data(empty.utf8), klinesData: Data(empty.utf8), fetchedAt: noon
            )
        ) { error in
            XCTAssertEqual(error as? MarketDataError, .invalidSymbol("XXX-USDT"))
        }
    }

    // MARK: - Yahoo

    func testYahooChartParsing() throws {
        let chart = #"""
        {"chart":{"result":[{"meta":{"currency":"USD","symbol":"AAPL","regularMarketPrice":308.26,"regularMarketDayHigh":308.26,"regularMarketDayLow":304.63,"regularMarketVolume":43391681,"longName":"Apple Inc.","chartPreviousClose":303.42},"timestamp":[1786195800,1786282200],"indicators":{"quote":[{"close":[303.42,null,308.26]}]}}],"error":null}}
        """#

        let snapshot = try YahooFinanceService.parse(
            symbol: "AAPL", market: .usStock, chartData: Data(chart.utf8), fetchedAt: noon
        )

        XCTAssertEqual(snapshot.source, .usStock)
        XCTAssertEqual(snapshot.name, "Apple Inc.")
        XCTAssertEqual(snapshot.price, 308.26)
        XCTAssertEqual(snapshot.currency, "USD")
        XCTAssertEqual(snapshot.changePercent!, (308.26 - 303.42) / 303.42 * 100, accuracy: 0.0001)
        XCTAssertEqual(snapshot.closes, [303.42, 308.26])   // null 被过滤
        XCTAssertEqual(snapshot.volume, 43_391_681)
    }

    func testYahooUnknownSymbolThrowsInvalidSymbol() {
        let notFound = #"{"chart":{"result":null,"error":{"code":"Not Found","description":"No data found, symbol may be delisted"}}}"#

        XCTAssertThrowsError(
            try YahooFinanceService.parse(
                symbol: "NOPE.SS", market: .aShare, chartData: Data(notFound.utf8), fetchedAt: noon
            )
        ) { error in
            XCTAssertEqual(error as? MarketDataError, .invalidSymbol("NOPE.SS"))
        }
    }

    func testEveryMarketDataErrorHasChineseDescription() {
        let errors: [MarketDataError] = [.invalidSymbol("X"), .http(500), .decoding, .network("超时")]
        for error in errors {
            XCTAssertFalse((error.errorDescription ?? "").isEmpty, "\(error) 缺少中文描述")
        }
    }

    func testRegistryCoversAllSevenSources() {
        let services = MarketServiceRegistry.services()
        XCTAssertEqual(Set(services.keys), Set(MarketSourceKind.allCases))
    }
}
