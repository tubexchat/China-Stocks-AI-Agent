import Foundation

enum QuantError: LocalizedError, Equatable {
    case tooShort(minimum: Int)
    case invalidParameter(String)

    var errorDescription: String? {
        switch self {
        case .tooShort(let minimum):
            "历史数据太短,至少需要 \(minimum) 根日线;换个数据源或缩短均线/特征窗口"
        case .invalidParameter(let message):
            message
        }
    }
}

/// 基础量化统计。closes 一律旧→新;收益为日简单收益;年化按 √252。
enum QuantMath {
    static func dailyReturns(_ closes: [Double]) -> [Double] {
        guard closes.count > 1 else { return [] }
        return zip(closes.dropFirst(), closes).map { today, yesterday in
            yesterday == 0 ? 0 : today / yesterday - 1
        }
    }

    /// 样本标准差 × √252。
    static func annualizedVolatility(returns: [Double]) -> Double {
        guard returns.count > 1 else { return 0 }
        let mean = returns.reduce(0, +) / Double(returns.count)
        let variance = returns.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(returns.count - 1)
        return variance.squareRoot() * (252.0).squareRoot()
    }

    /// 峰值到谷底的最大跌幅,0.25 = 25%。
    static func maxDrawdown(_ closes: [Double]) -> Double {
        var peak = -Double.infinity
        var worst = 0.0
        for close in closes {
            peak = max(peak, close)
            if peak > 0 {
                worst = max(worst, 1 - close / peak)
            }
        }
        return worst
    }

    /// 历史模拟法 VaR:收益分布的左尾分位,返回正数损失幅度。
    static func historicalVaR(returns: [Double], confidence: Double) -> Double {
        guard !returns.isEmpty else { return 0 }
        let sorted = returns.sorted()
        let index = min(max(Int(Double(sorted.count) * (1 - confidence)), 0), sorted.count - 1)
        return max(0, -sorted[index])
    }

    /// 年化夏普(无风险利率取 0);零波动约定返回 0。
    static func sharpe(returns: [Double]) -> Double {
        let annualVol = annualizedVolatility(returns: returns)
        guard annualVol > 0, !returns.isEmpty else { return 0 }
        let meanDaily = returns.reduce(0, +) / Double(returns.count)
        return meanDaily * 252 / annualVol
    }
}

/// 风控指标汇总。
struct RiskReport: Equatable, Sendable {
    var symbol = ""
    var sourceName = ""
    var days: Int
    var var95: Double
    var var99: Double
    var maxDrawdown: Double
    var annualVol: Double
    var sharpe: Double

    var promptText: String {
        """
        【风控模型 · \(sourceName) · \(symbol) · 近\(days)日】
        单日 VaR(95%) \(Self.percent(var95));单日 VaR(99%) \(Self.percent(var99))
        最大回撤 \(Self.percent(maxDrawdown));年化波动率 \(Self.percent(annualVol));夏普比率 \(MarketSnapshot.formatNumber(sharpe))
        """
    }

    static func percent(_ value: Double) -> String {
        MarketSnapshot.formatNumber(value * 100) + "%"
    }
}

enum RiskAnalyzer {
    static func run(closes: [Double]) throws -> RiskReport {
        guard closes.count >= 30 else { throw QuantError.tooShort(minimum: 30) }
        let returns = QuantMath.dailyReturns(closes)
        return RiskReport(
            days: closes.count,
            var95: QuantMath.historicalVaR(returns: returns, confidence: 0.95),
            var99: QuantMath.historicalVaR(returns: returns, confidence: 0.99),
            maxDrawdown: QuantMath.maxDrawdown(closes),
            annualVol: QuantMath.annualizedVolatility(returns: returns),
            sharpe: QuantMath.sharpe(returns: returns)
        )
    }
}
