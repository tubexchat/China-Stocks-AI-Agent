import Foundation

/// 因子挖掘结果:9 个价格类因子按 |IC| 降序。
struct FactorReport: Equatable, Sendable {
    struct Ranking: Equatable, Sendable {
        var name: String
        /// Spearman 秩相关 IC:因子值 vs 次日收益。
        var ic: Double
        /// 多空分层:因子最高 30% 的日子与最低 30% 的日子,次日平均收益之差。
        var spread: Double
    }

    var symbol = ""
    var sourceName = ""
    var days: Int
    var samples: Int
    var rankings: [Ranking]

    var promptText: String {
        let rows = rankings.map { r in
            "\(r.name): IC \(NumberFormat.number(r.ic));多空分层日均收益差 \(RiskReport.percent(r.spread))"
        }.joined(separator: "\n")
        return """
        【因子挖掘 · \(sourceName) · \(symbol) · 近\(days)日 · \(samples) 个样本】
        对次日收益的 Spearman 秩相关 IC(按预测力 |IC| 降序);多空分层 = 因子最高30%日 vs 最低30%日的次日均收益差
        \(rows)
        """
    }
}

/// 价格类因子的 IC 检验。因子在 t 日收盘后计算(只看 t 及更早),对齐 t+1 日收益。
enum FactorMiner {
    static func run(closes: [Double]) throws -> FactorReport {
        guard closes.count >= 60 else { throw QuantError.tooShort(minimum: 60) }
        let returns = QuantMath.dailyReturns(closes)

        // t 从 20 起(最长窗口 20),标签是 returns[t](= t+1 日收益)
        var factorSeries: [[Double]] = Array(repeating: [], count: factors.count)
        var nextReturns: [Double] = []
        for t in 20..<(closes.count - 1) {
            for (index, factor) in factors.enumerated() {
                factorSeries[index].append(factor.compute(closes, returns, t))
            }
            nextReturns.append(returns[t])
        }

        var rankings = zip(factors, factorSeries).map { factor, values in
            FactorReport.Ranking(
                name: factor.name,
                ic: spearman(values, nextReturns),
                spread: quantileSpread(factor: values, outcomes: nextReturns)
            )
        }
        rankings.sort { abs($0.ic) > abs($1.ic) }

        return FactorReport(days: closes.count, samples: nextReturns.count, rankings: rankings)
    }

    // MARK: - 因子库(只依赖收盘价)

    private struct Factor: Sendable {
        var name: String
        /// (closes, returns, t) -> 因子值;returns[i] = closes[i+1]/closes[i]-1
        var compute: @Sendable ([Double], [Double], Int) -> Double
    }

    private static let factors: [Factor] = [
        Factor(name: "反转1日") { _, returns, t in -returns[t - 1] },
        Factor(name: "动量5日") { closes, _, t in momentum(closes, t, 5) },
        Factor(name: "动量10日") { closes, _, t in momentum(closes, t, 10) },
        Factor(name: "动量20日") { closes, _, t in momentum(closes, t, 20) },
        Factor(name: "乖离5日") { closes, _, t in bias(closes, t, 5) },
        Factor(name: "乖离20日") { closes, _, t in bias(closes, t, 20) },
        Factor(name: "波动10日") { _, returns, t in
            let window = Array(returns[(t - 10)..<t])
            return QuantMath.annualizedVolatility(returns: window)
        },
        Factor(name: "RSI14") { _, returns, t in rsi(returns, t, 14) },
        Factor(name: "价格位置20日") { closes, _, t in
            let window = closes[(t - 19)...t]
            guard let low = window.min(), let high = window.max(), high > low else { return 0.5 }
            return (closes[t] - low) / (high - low)
        }
    ]

    private static func momentum(_ closes: [Double], _ t: Int, _ n: Int) -> Double {
        closes[t - n] == 0 ? 0 : closes[t] / closes[t - n] - 1
    }

    private static func bias(_ closes: [Double], _ t: Int, _ n: Int) -> Double {
        let ma = closes[(t - n + 1)...t].reduce(0, +) / Double(n)
        return ma == 0 ? 0 : closes[t] / ma - 1
    }

    private static func rsi(_ returns: [Double], _ t: Int, _ n: Int) -> Double {
        let window = returns[(t - n)..<t]
        let gains = window.filter { $0 > 0 }.reduce(0, +)
        let losses = -window.filter { $0 < 0 }.reduce(0, +)
        guard gains + losses > 0 else { return 50 }
        return 100 * gains / (gains + losses)
    }

    // MARK: - 统计

    /// Spearman 秩相关(并列取平均秩);常数列/样本不足约定返回 0。
    static func spearman(_ xs: [Double], _ ys: [Double]) -> Double {
        guard xs.count == ys.count, xs.count > 1 else { return 0 }
        let rx = averageRanks(xs)
        let ry = averageRanks(ys)

        let n = Double(xs.count)
        let meanX = rx.reduce(0, +) / n
        let meanY = ry.reduce(0, +) / n
        var covariance = 0.0, varianceX = 0.0, varianceY = 0.0
        for index in xs.indices {
            let dx = rx[index] - meanX
            let dy = ry[index] - meanY
            covariance += dx * dy
            varianceX += dx * dx
            varianceY += dy * dy
        }
        guard varianceX > 0, varianceY > 0 else { return 0 }
        return covariance / (varianceX * varianceY).squareRoot()
    }

    /// 值 → 平均秩(1 起,并列取平均)。
    static func averageRanks(_ values: [Double]) -> [Double] {
        let sorted = values.indices.sorted { values[$0] < values[$1] }
        var ranks = [Double](repeating: 0, count: values.count)
        var position = 0
        while position < sorted.count {
            var end = position
            while end + 1 < sorted.count, values[sorted[end + 1]] == values[sorted[position]] {
                end += 1
            }
            let averageRank = Double(position + end) / 2 + 1
            for offset in position...end {
                ranks[sorted[offset]] = averageRank
            }
            position = end + 1
        }
        return ranks
    }

    /// 因子最高 30% 样本与最低 30% 样本的平均 outcome 之差。
    static func quantileSpread(factor: [Double], outcomes: [Double]) -> Double {
        guard factor.count == outcomes.count, factor.count >= 10 else { return 0 }
        let order = factor.indices.sorted { factor[$0] < factor[$1] }
        let bucket = max(1, factor.count * 3 / 10)
        let low = order.prefix(bucket).map { outcomes[$0] }
        let high = order.suffix(bucket).map { outcomes[$0] }
        return high.reduce(0, +) / Double(high.count) - low.reduce(0, +) / Double(low.count)
    }
}
