import Foundation

/// 双均线回测结果。净值曲线从 1 起步,与 closes 等长。
struct BacktestResult: Equatable, Sendable {
    var symbol = ""
    var sourceName = ""
    var fast: Int
    var slow: Int
    var strategyReturn: Double
    var holdReturn: Double
    var annualized: Double
    var maxDrawdown: Double
    var trades: Int
    var winRate: Double
    var equityCurve: [Double]
    var holdCurve: [Double]

    var promptText: String {
        """
        【历史回测 · \(sourceName) · \(symbol) · MA\(fast)/MA\(slow) 双均线 · \(equityCurve.count) 根日线】
        策略收益 \(RiskReport.percent(strategyReturn));买入持有 \(RiskReport.percent(holdReturn));策略年化 \(RiskReport.percent(annualized))
        策略最大回撤 \(RiskReport.percent(maxDrawdown));交易次数 \(trades);胜率 \(RiskReport.percent(winRate))
        规则:快线上穿持仓、下穿空仓,信号次日生效,未计手续费与滑点
        """
    }
}

/// 双均线交叉回测:T 日出信号,T+1 日收盘生效;不计手续费(v1)。
enum Backtester {
    static func run(closes: [Double], fast: Int = 5, slow: Int = 20) throws -> BacktestResult {
        guard fast >= 1, slow > fast else {
            throw QuantError.invalidParameter("快线周期必须小于慢线周期")
        }
        guard closes.count >= max(30, slow + 10) else { throw QuantError.tooShort(minimum: 30) }

        let fastMA = movingAverage(closes, window: fast)
        let slowMA = movingAverage(closes, window: slow)

        var holding = false
        var equity = 1.0
        var equityCurve: [Double] = [1.0]
        var entryEquity = 1.0
        var trades = 0
        var wins = 0

        for day in 1..<closes.count {
            // 昨日信号今日生效
            if let f = fastMA[day - 1], let s = slowMA[day - 1] {
                let shouldHold = f > s
                if shouldHold && !holding {
                    holding = true
                    entryEquity = equity
                } else if !shouldHold && holding {
                    holding = false
                    trades += 1
                    if equity > entryEquity { wins += 1 }
                }
            }
            if holding {
                equity *= closes[day] / closes[day - 1]
            }
            equityCurve.append(equity)
        }
        // 期末仍持仓视为完成一笔
        if holding {
            trades += 1
            if equity > entryEquity { wins += 1 }
        }

        let holdCurve = closes.map { $0 / closes[0] }
        let strategyReturn = equity - 1
        let years = Double(closes.count) / 252
        let annualized = years > 0 && equity > 0 ? pow(equity, 1 / years) - 1 : 0

        return BacktestResult(
            fast: fast,
            slow: slow,
            strategyReturn: strategyReturn,
            holdReturn: closes[closes.count - 1] / closes[0] - 1,
            annualized: annualized,
            maxDrawdown: QuantMath.maxDrawdown(equityCurve),
            trades: trades,
            winRate: trades > 0 ? Double(wins) / Double(trades) : 0,
            equityCurve: equityCurve,
            holdCurve: holdCurve
        )
    }

    /// 简单移动平均;窗口未满处为 nil。
    static func movingAverage(_ values: [Double], window: Int) -> [Double?] {
        var result = [Double?](repeating: nil, count: values.count)
        guard window >= 1, values.count >= window else { return result }
        var sum = values[0..<window].reduce(0, +)
        result[window - 1] = sum / Double(window)
        for index in window..<values.count {
            sum += values[index] - values[index - window]
            result[index] = sum / Double(window)
        }
        return result
    }
}
