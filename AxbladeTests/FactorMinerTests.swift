import XCTest
@testable import Axblade

final class FactorMinerTests: XCTestCase {
    // MARK: - Spearman

    func testSpearmanPerfectMonotone() {
        XCTAssertEqual(FactorMiner.spearman([1, 2, 3, 4], [10, 20, 30, 40]), 1.0, accuracy: 1e-12)
        XCTAssertEqual(FactorMiner.spearman([1, 2, 3, 4], [40, 30, 20, 10]), -1.0, accuracy: 1e-12)
    }

    func testSpearmanIsRankBasedNotLinear() {
        // 单调但非线性:秩相关仍为 1
        XCTAssertEqual(FactorMiner.spearman([1, 2, 3, 4], [1, 10, 100, 1000]), 1.0, accuracy: 1e-12)
    }

    func testSpearmanHandlesTiesWithAverageRanks() {
        // [1,2,2,3] 的秩 = [1, 2.5, 2.5, 4]
        let value = FactorMiner.spearman([1, 2, 2, 3], [1, 2, 3, 4])
        XCTAssertEqual(value, 0.9487, accuracy: 0.001)   // 手算:cov/σσ ≈ 0.9487
    }

    func testSpearmanDegenerateInputs() {
        XCTAssertEqual(FactorMiner.spearman([1, 1, 1], [1, 2, 3]), 0)   // 常数列约定 0
        XCTAssertEqual(FactorMiner.spearman([1], [2]), 0)
        XCTAssertEqual(FactorMiner.spearman([], []), 0)
    }

    // MARK: - 因子检验

    /// 严格交替 ±2% 的序列:次日收益 = -今日收益,「反转1日」应拿满分 IC ≈ 1 并排第一。
    func testAlternatingSeriesCrownsOneDayReversal() throws {
        var closes = [100.0]
        for day in 0..<160 {
            closes.append(closes.last! * (day % 2 == 0 ? 1.02 : 0.98))
        }

        let report = try FactorMiner.run(closes: closes)

        XCTAssertEqual(report.rankings.first?.name, "反转1日")
        // 复利浮点让 ±2% 的并列组内秩带噪声,理论 1.0 实际 ~0.93
        XCTAssertGreaterThan(report.rankings.first?.ic ?? 0, 0.9)
        // 多空分层:因子高的日子次日收益应显著高于因子低的日子
        XCTAssertGreaterThan(report.rankings.first?.spread ?? 0, 0.03)
    }

    /// 强自相关(动量)序列:动量类因子 IC 为正、反转1日 IC 为负。
    func testTrendingSeriesFavorsMomentum() throws {
        var closes = [100.0]
        var r = 0.01
        for day in 0..<200 {
            r = 0.6 * r + 0.015 * sin(Double(day) / 5)   // AR(1) 收益,确定性
            closes.append(closes.last! * (1 + r))
        }

        let report = try FactorMiner.run(closes: closes)
        let byName = Dictionary(uniqueKeysWithValues: report.rankings.map { ($0.name, $0.ic) })

        XCTAssertGreaterThan(byName["动量5日"] ?? 0, 0.3)
        XCTAssertLessThan(byName["反转1日"] ?? 0, -0.3)
    }

    func testReportHasAllNineFactorsRankedByAbsIC() throws {
        // 拆开写:混合 Int/Double 的字面量表达式在 CI 的 Xcode 26.3 上类型推导超时
        let closes: [Double] = (0..<150).map { i -> Double in
            let t = Double(i)
            let wave: Double = 10.0 * sin(t / 6.0)
            let drift: Double = t * 0.05
            return 100.0 + wave + drift
        }

        let report = try FactorMiner.run(closes: closes)

        XCTAssertEqual(report.rankings.count, 9)
        let absICs = report.rankings.map { abs($0.ic) }
        XCTAssertEqual(absICs, absICs.sorted(by: >), "应按 |IC| 降序")
        XCTAssertTrue(report.promptText.contains("因子挖掘"))
        XCTAssertTrue(report.promptText.contains("IC"))
        XCTAssertTrue(report.promptText.contains("多空分层"))
    }

    func testShortHistoryThrows() {
        XCTAssertThrowsError(try FactorMiner.run(closes: (0..<50).map(Double.init))) { error in
            XCTAssertEqual(error as? QuantError, .tooShort(minimum: 60))
        }
    }

    func testFactorToolSitsAboveBacktest() {
        let order = QuantTool.allCases
        let factorIndex = order.firstIndex(of: .factor)!
        let backtestIndex = order.firstIndex(of: .backtest)!
        XCTAssertEqual(backtestIndex, factorIndex + 1, "因子挖掘应紧邻历史回测上方")
    }
}
