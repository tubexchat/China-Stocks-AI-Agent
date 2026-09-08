import XCTest
@testable import Axblade

final class SymbolNormalizationTests: XCTestCase {
    func testBinanceAndMEXCStripSeparatorsAndDefaultToUSDT() {
        for normalize in [BinanceMarketService.normalize, MEXCMarketService.normalize] {
            XCTAssertEqual(normalize("btcusdt"), "BTCUSDT")
            XCTAssertEqual(normalize("BTC-USDT"), "BTCUSDT")
            XCTAssertEqual(normalize("btc/usdt"), "BTCUSDT")
            XCTAssertEqual(normalize("btc"), "BTCUSDT")
            XCTAssertEqual(normalize(" eth "), "ETHUSDT")
            XCTAssertEqual(normalize("ETHBTC"), "ETHBTC")
        }
    }

    func testOKXWantsDashFormat() {
        XCTAssertEqual(OKXMarketService.normalize("BTC-USDT"), "BTC-USDT")
        XCTAssertEqual(OKXMarketService.normalize("btcusdt"), "BTC-USDT")
        XCTAssertEqual(OKXMarketService.normalize("btc/usdt"), "BTC-USDT")
        XCTAssertEqual(OKXMarketService.normalize("btc"), "BTC-USDT")
        XCTAssertEqual(OKXMarketService.normalize("ethbtc"), "ETH-BTC")
    }

    func testYahooKeepsUserSuffixAndUppercasesUS() {
        XCTAssertEqual(YahooFinanceService.normalize("aapl", market: .usStock), "AAPL")
        XCTAssertEqual(YahooFinanceService.normalize("605930.KQ", market: .krStock), "605930.KQ")
        XCTAssertEqual(YahooFinanceService.normalize("0700.hk", market: .hkStock), "0700.HK")
    }

    func testKoreanDigitsGetKSSuffix() {
        XCTAssertEqual(YahooFinanceService.normalize("005930", market: .krStock), "005930.KS")
    }

    func testHongKongDigitsArePaddedToFour() {
        XCTAssertEqual(YahooFinanceService.normalize("700", market: .hkStock), "0700.HK")
        XCTAssertEqual(YahooFinanceService.normalize("9988", market: .hkStock), "9988.HK")
        XCTAssertEqual(YahooFinanceService.normalize("00700", market: .hkStock), "0700.HK")
    }

    func testASharePicksExchangeByPrefix() {
        XCTAssertEqual(YahooFinanceService.normalize("600519", market: .aShare), "600519.SS")
        XCTAssertEqual(YahooFinanceService.normalize("688981", market: .aShare), "688981.SS")
        XCTAssertEqual(YahooFinanceService.normalize("900901", market: .aShare), "900901.SS")
        XCTAssertEqual(YahooFinanceService.normalize("000001", market: .aShare), "000001.SZ")
        XCTAssertEqual(YahooFinanceService.normalize("300750", market: .aShare), "300750.SZ")
    }
}
