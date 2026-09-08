import XCTest
@testable import Axblade

final class QuantMathTests: XCTestCase {
    func testDailyReturns() {
        assertEqualArrays(QuantMath.dailyReturns([100, 110, 99]), [0.1, -0.1], accuracy: 1e-12)
        XCTAssertEqual(QuantMath.dailyReturns([100]), [])
        XCTAssertEqual(QuantMath.dailyReturns([]), [])
    }

    func testMaxDrawdown() {
        // 100→120→60→90:峰 120 谷 60,回撤 50%
        XCTAssertEqual(QuantMath.maxDrawdown([100, 120, 60, 90]), 0.5, accuracy: 1e-12)
        // 单调上涨无回撤
        XCTAssertEqual(QuantMath.maxDrawdown([1, 2, 3]), 0, accuracy: 1e-12)
        XCTAssertEqual(QuantMath.maxDrawdown([]), 0)
    }

    func testHistoricalVaR() {
        // 100 个收益:-0.100, -0.099, …, -0.001(升序排列即自身)
        let returns = (1...100).map { -Double($0) / 1000 }.sorted()
        // 95% 置信:第 5 百分位(索引 floor(0.05*100)=5 → 排序后第 6 小?约定:索引 Int(0.05*count) 处)
        let var95 = QuantMath.historicalVaR(returns: returns, confidence: 0.95)
        XCTAssertEqual(var95, 0.095, accuracy: 0.002)   // 损失幅度为正数
        XCTAssertGreaterThan(
            QuantMath.historicalVaR(returns: returns, confidence: 0.99), var95
        )
    }

    func testAnnualizedVolatilityScalesBySqrt252() {
        // 常数收益波动为 0
        XCTAssertEqual(QuantMath.annualizedVolatility(returns: [0.01, 0.01, 0.01]), 0, accuracy: 1e-12)
        // 已知样本标准差:[0.01, -0.01] 样本 std = 0.0141421…
        let vol = QuantMath.annualizedVolatility(returns: [0.01, -0.01])
        XCTAssertEqual(vol, 0.01414213 * (252.0).squareRoot(), accuracy: 1e-4)
    }

    func testSharpe() {
        // 平均日收益 0.001,日波动已知 → 年化夏普 = 0.001*252 / (std*√252)
        let returns = [0.002, 0.0, 0.001]
        let mean = 0.001
        let std = QuantMath.annualizedVolatility(returns: returns) / (252.0).squareRoot()
        XCTAssertEqual(
            QuantMath.sharpe(returns: returns),
            mean * 252 / (std * (252.0).squareRoot()),
            accuracy: 1e-9
        )
        XCTAssertEqual(QuantMath.sharpe(returns: [0.01, 0.01]), 0)   // 零波动约定返回 0
    }

    func testRiskAnalyzerBundlesEverything() throws {
        let closes = (0..<80).map { 100 + Double($0).truncatingRemainder(dividingBy: 7) }
        let report = try RiskAnalyzer.run(closes: closes)

        XCTAssertGreaterThan(report.annualVol, 0)
        XCTAssertGreaterThanOrEqual(report.var99, report.var95)
        XCTAssertTrue(report.promptText.contains("最大回撤"))
        XCTAssertTrue(report.promptText.contains("VaR"))
    }

    func testRiskAnalyzerRejectsShortHistory() {
        XCTAssertThrowsError(try RiskAnalyzer.run(closes: [1, 2, 3])) { error in
            XCTAssertEqual(error as? QuantError, .tooShort(minimum: 30))
        }
    }

    private func assertEqualArrays(_ a: [Double], _ b: [Double], accuracy: Double) {
        XCTAssertEqual(a.count, b.count)
        for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: accuracy) }
    }
}
