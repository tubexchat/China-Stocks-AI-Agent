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

    func testFuyaoErrorsAreDescribedInTheActiveLanguage() {
        XCTAssertTrue(L10nStrings.zh.describe(FuyaoError.api(code: 2001, message: "x")).contains("2001"))
        XCTAssertTrue(L10nStrings.en.describe(FuyaoError.api(code: 2001, message: "x")).contains("invalid or expired"))
        XCTAssertTrue(L10nStrings.zh.describe(FuyaoError.api(code: 4001, message: "x")).contains("频率"))
        XCTAssertTrue(L10nStrings.en.describe(FuyaoError.api(code: 3002, message: "x")).contains("not ready"))
        XCTAssertEqual(L10nStrings.zh.describe(FuyaoError.api(code: 1002, message: "bad date")), "数据接口错误 1002:bad date")
        XCTAssertEqual(L10nStrings.en.describe(FuyaoError.missingKey), L10nStrings.en.fuyaoMissingKey)
        XCTAssertNotEqual(L10nStrings.zh.describe(FuyaoError.network("x")), L10nStrings.en.describe(FuyaoError.network("x")))
    }

    func testModuleAndToolNamesAreLocalized() {
        XCTAssertEqual(L10nStrings.zh.moduleName(.limitUpPulse), "涨停情绪市场脉冲")
        XCTAssertEqual(L10nStrings.en.moduleName(.limitUpPulse), "Limit-Up Sentiment Pulse")
        XCTAssertEqual(L10nStrings.zh.moduleName(.dragonTigerWatch), "龙虎榜机构与游资观察")
        XCTAssertEqual(L10nStrings.zh.toolName(.backtest), "历史回测")
        XCTAssertEqual(L10nStrings.en.toolName(.backtest), "Backtest")
        for module in AgentModule.allCases {
            XCTAssertNotEqual(L10nStrings.zh.moduleSubtitle(module), L10nStrings.en.moduleSubtitle(module))
        }
    }

    func testMarketSnapshotPromptTextFollowsLanguage() {
        let snapshot = MarketSnapshot(
            symbol: "600519.SH", name: "贵州茅台",
            price: 1309.3, changePercent: -0.51,
            closes: [], fetchedAt: Date(timeIntervalSince1970: 1_786_500_000)
        )

        XCTAssertTrue(snapshot.promptText(in: .zh).contains("【A股行情"))
        XCTAssertTrue(snapshot.promptText(in: .en).contains("[A-share quote"))
        // 无参版本保持中文,老调用与既有测试不受影响
        XCTAssertEqual(snapshot.promptText, snapshot.promptText(in: .zh))
    }
}
