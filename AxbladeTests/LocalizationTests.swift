import XCTest
@testable import Axblade

final class LocalizationTests: XCTestCase {
    func testBothLanguageTablesHaveNoEmptyStrings() {
        for (language, table) in [("zh", L10nStrings.zh), ("en", L10nStrings.en)] {
            for child in Mirror(reflecting: table).children {
                if let value = child.value as? String {
                    XCTAssertFalse(
                        value.isEmpty,
                        "\(language).\(child.label ?? "?") 是空字符串"
                    )
                }
            }
        }
    }

    /// 英文表是在中文默认值上逐字段覆盖出来的:任何一个字段两边相同,
    /// 就说明忘了翻译——必须红。
    func testEveryFieldIsTranslated() {
        let zh = Mirror(reflecting: L10nStrings.zh).children
        let en = Mirror(reflecting: L10nStrings.en).children

        for (zhChild, enChild) in zip(zh, en) {
            guard let zhValue = zhChild.value as? String,
                  let enValue = enChild.value as? String else { continue }
            XCTAssertNotEqual(
                zhValue, enValue,
                "字段 \(zhChild.label ?? "?") 没有翻译"
            )
        }
    }

    func testLanguageDisplayNamesAreFixed() {
        XCTAssertEqual(AppLanguage.zh.displayName, "简体中文")
        XCTAssertEqual(AppLanguage.en.displayName, "English")
        XCTAssertEqual(AppLanguage.allCases, [.zh, .en])
    }

    func testChatErrorsAreDescribedInTheActiveLanguage() {
        let error = ChatServiceError.http(401, "unauthorized")

        XCTAssertTrue(L10nStrings.zh.describe(error).contains("服务返回 HTTP 401"))
        XCTAssertTrue(L10nStrings.en.describe(error).contains("HTTP 401"))
        XCTAssertFalse(L10nStrings.en.describe(error).contains("服务"))

        let stream = ChatServiceError.stream("overloaded")
        XCTAssertTrue(L10nStrings.zh.describe(stream).contains("生成中断"))
        XCTAssertTrue(L10nStrings.en.describe(stream).contains("interrupted"))
    }

    func testMarketErrorsAreDescribedInTheActiveLanguage() {
        let notFound = MarketDataError.invalidSymbol("XXXX")

        XCTAssertTrue(L10nStrings.zh.describe(notFound).contains("XXXX"))
        XCTAssertTrue(L10nStrings.en.describe(notFound).contains("XXXX"))
        XCTAssertNotEqual(L10nStrings.zh.describe(notFound), L10nStrings.en.describe(notFound))
    }

    func testSourceAndToolNamesAreLocalized() {
        XCTAssertEqual(L10nStrings.zh.sourceName(.usStock), "美股")
        XCTAssertEqual(L10nStrings.en.sourceName(.usStock), "US Stocks")
        XCTAssertEqual(L10nStrings.en.sourceName(.binance), "Binance")
        XCTAssertEqual(L10nStrings.zh.toolName(.backtest), "历史回测")
        XCTAssertEqual(L10nStrings.en.toolName(.backtest), "Backtest")
    }

    func testMarketSnapshotPromptTextFollowsLanguage() {
        let snapshot = MarketSnapshot(
            source: .binance, symbol: "BTCUSDT", name: nil,
            price: 64038, changePercent: -1.47,
            high: nil, low: nil, volume: nil, currency: nil,
            closes: [], fetchedAt: Date(timeIntervalSince1970: 1_786_500_000)
        )

        XCTAssertTrue(snapshot.promptText(in: .zh).contains("【行情数据"))
        XCTAssertTrue(snapshot.promptText(in: .en).contains("[Market data"))
        // 无参版本保持中文,老调用与既有测试不受影响
        XCTAssertEqual(snapshot.promptText, snapshot.promptText(in: .zh))
    }
}
