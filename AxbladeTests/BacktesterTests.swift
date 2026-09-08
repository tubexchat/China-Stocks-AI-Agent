import XCTest
@testable import Axblade

final class BacktesterTests: XCTestCase {
    /// fast=1(收盘价本身)、slow=2:上涨段快线在上→持仓吃到涨幅,下跌段空仓躲过。
    func testCrossoverCapturesUptrendAndDodgesDowntrend() throws {
        // 先涨 100→200(21 根),再跌回 140(12 根),共 33 根 ≥ 门槛 30
        var closes = stride(from: 100.0, through: 200.0, by: 5).map { $0 }
        closes += stride(from: 195.0, through: 140.0, by: -5).map { $0 }

        let result = try Backtester.run(closes: closes, fast: 1, slow: 2)

        // 买入持有:140/100 - 1 = 40%
        XCTAssertEqual(result.holdReturn, 0.4, accuracy: 1e-9)
        // 策略应显著好于持有(躲过大部分下跌),且至少完成一次买卖
        XCTAssertGreaterThan(result.strategyReturn, result.holdReturn)
        XCTAssertGreaterThanOrEqual(result.trades, 1)
        XCTAssertEqual(result.equityCurve.count, closes.count)
        XCTAssertEqual(result.holdCurve.count, closes.count)
        XCTAssertEqual(result.equityCurve.first!, 1.0, accuracy: 1e-9)   // 净值从 1 起步
    }

    func testPureUptrendStrategyStaysInvested() throws {
        let closes = stride(from: 100.0, through: 300.0, by: 4).map { $0 }   // 51 根

        let result = try Backtester.run(closes: closes, fast: 1, slow: 2)

        // 信号 T+1 生效,策略最多差一步,但应接近持有收益
        XCTAssertGreaterThan(result.strategyReturn, result.holdReturn * 0.9)
        XCTAssertEqual(result.winRate, 1.0, accuracy: 1e-9)   // 唯一一段持仓是赚的
    }

    func testShortHistoryThrows() {
        XCTAssertThrowsError(try Backtester.run(closes: [1, 2, 3], fast: 5, slow: 20)) { error in
            XCTAssertEqual(error as? QuantError, .tooShort(minimum: 30))
        }
    }

    func testInvalidWindowsThrow() {
        let closes = (0..<100).map(Double.init)
        XCTAssertThrowsError(try Backtester.run(closes: closes, fast: 20, slow: 5)) { error in
            XCTAssertEqual(error as? QuantError, .invalidParameter("快线周期必须小于慢线周期"))
        }
    }

    func testReportMentionsCoreMetrics() throws {
        let closes = (0..<120).map { 100 + 10 * sin(Double($0) / 8) }
        let result = try Backtester.run(closes: closes)

        XCTAssertTrue(result.promptText.contains("策略收益"))
        XCTAssertTrue(result.promptText.contains("买入持有"))
        XCTAssertTrue(result.promptText.contains("最大回撤"))
    }
}
