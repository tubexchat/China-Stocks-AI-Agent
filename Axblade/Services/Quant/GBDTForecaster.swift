import Foundation

/// GBDT 次日涨跌预测结果。
struct Forecast: Equatable, Sendable {
    var symbol = ""
    var sourceName = ""
    var predictedReturn: Double
    var direction: String            // "看涨" / "看跌"
    var validationHitRate: Double    // 验证集方向命中率
    var trainSamples: Int
    var validationSamples: Int
    var trees: Int
    var depth: Int
    var featureImportance: [(String, Double)]

    static func == (lhs: Forecast, rhs: Forecast) -> Bool {
        lhs.predictedReturn == rhs.predictedReturn
            && lhs.validationHitRate == rhs.validationHitRate
            && lhs.direction == rhs.direction
    }

    var promptText: String {
        let ranked = featureImportance
            .sorted { $0.1 > $1.1 }
            .prefix(4)
            .map { "\($0.0) \(RiskReport.percent($0.1))" }
            .joined(separator: "、")
        return """
        【梯度提升树预测 · \(sourceName) · \(symbol) · \(trees) 棵/深度 \(depth)】
        次日方向 \(direction)(预测收益 \(RiskReport.percent(predictedReturn)))
        验证集方向命中率 \(RiskReport.percent(validationHitRate))(训练 \(trainSamples) / 验证 \(validationSamples) 样本,按时间序切分)
        特征重要性(前四): \(ranked)
        """
    }
}

/// 特征工程 + 时间序切分训练。全部确定性,无随机源。
enum GBDTForecaster {
    static let featureNames = ["r1", "r2", "r3", "r4", "r5", "ma5/ma20-1", "mom10", "vol10"]

    static func run(closes: [Double], trees: Int = 120, depth: Int = 3) throws -> Forecast {
        // 特征窗口最长 20(ma20),再留出足够训练样本
        guard closes.count >= 90 else { throw QuantError.tooShort(minimum: 90) }

        let returns = QuantMath.dailyReturns(closes)
        var features: [[Double]] = []
        var targets: [Double] = []

        // t 从 20 起有完整特征;标签是 t+1 日收益(returns[t])
        for t in 20..<(closes.count - 1) {
            features.append(featureRow(closes: closes, returns: returns, at: t))
            targets.append(returns[t])
        }

        let split = Int(Double(features.count) * 0.8)
        guard split >= 30, features.count - split >= 10 else { throw QuantError.tooShort(minimum: 90) }

        var model = GBDT(trees: trees, depth: depth, learningRate: 0.1, minSamplesLeaf: 5)
        model.fit(features: Array(features[..<split]), targets: Array(targets[..<split]))

        var hits = 0
        for index in split..<features.count {
            let predicted = model.predict(features[index])
            if (predicted >= 0) == (targets[index] >= 0) { hits += 1 }
        }
        let hitRate = Double(hits) / Double(features.count - split)

        // 用最新一行特征预测明日
        let latest = featureRow(closes: closes, returns: returns, at: closes.count - 1)
        let predictedReturn = model.predict(latest)

        return Forecast(
            predictedReturn: predictedReturn,
            direction: predictedReturn >= 0 ? "看涨" : "看跌",
            validationHitRate: hitRate,
            trainSamples: split,
            validationSamples: features.count - split,
            trees: trees,
            depth: depth,
            featureImportance: zip(featureNames, model.featureImportance).map { ($0, $1) }
        )
    }

    /// t 日收盘后的特征(只用 t 及更早的数据,不偷看未来)。
    private static func featureRow(closes: [Double], returns: [Double], at t: Int) -> [Double] {
        // returns[i] = closes[i+1]/closes[i]-1,t 日最近一日收益是 returns[t-1]
        let r = { (lag: Int) -> Double in t - lag >= 0 ? returns[t - lag] : 0 }
        let window = { (n: Int) -> ArraySlice<Double> in closes[(t - n + 1)...t] }
        let ma5 = window(5).reduce(0, +) / 5
        let ma20 = window(20).reduce(0, +) / 20
        let mom10 = closes[t - 10] == 0 ? 0 : closes[t] / closes[t - 10] - 1
        let recent = Array(returns[max(0, t - 10)..<t])
        let vol10 = QuantMath.annualizedVolatility(returns: recent) / (252.0).squareRoot()

        return [r(1), r(2), r(3), r(4), r(5), ma20 == 0 ? 0 : ma5 / ma20 - 1, mom10, vol10]
    }
}
