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

    func testQuantErrorsAreDescribedInTheActiveLanguage() {
        XCTAssertEqual(L10nStrings.zh.describe(QuantError.tooShort(minimum: 60)), "历史数据太短,至少需要 60 根日线")
        XCTAssertTrue(L10nStrings.en.describe(QuantError.tooShort(minimum: 60)).contains("60"))
        XCTAssertNotEqual(L10nStrings.zh.describe(QuantError.invalidParameter("x")), L10nStrings.en.describe(QuantError.invalidParameter("x")))
    }
}
