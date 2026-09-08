import XCTest
@testable import Axblade

final class GBDTTests: XCTestCase {
    private func mse(_ model: GBDT, _ features: [[Double]], _ targets: [Double]) -> Double {
        let errors = zip(features, targets).map { row, y in
            let p = model.predict(row)
            return (p - y) * (p - y)
        }
        return errors.reduce(0, +) / Double(errors.count)
    }

    func testFitsLinearFunction() {
        // y = 3x,x ∈ [0,1)
        let features = (0..<200).map { [Double($0) / 200] }
        let targets = features.map { 3 * $0[0] }
        let baseline = targets.map { y in
            let mean = targets.reduce(0, +) / Double(targets.count)
            return (y - mean) * (y - mean)
        }.reduce(0, +) / Double(targets.count)

        var model = GBDT(trees: 80, depth: 3, learningRate: 0.1, minSamplesLeaf: 5)
        model.fit(features: features, targets: targets)

        XCTAssertLessThan(mse(model, features, targets), baseline * 0.05, "MSE 应比只猜均值降 95%+")
    }

    func testFitsNonlinearFunction() {
        // y = x²,树模型的主场
        let features = (0..<300).map { [Double($0) / 150 - 1] }   // [-1, 1)
        let targets = features.map { $0[0] * $0[0] }

        var model = GBDT(trees: 120, depth: 3, learningRate: 0.1, minSamplesLeaf: 5)
        model.fit(features: features, targets: targets)

        XCTAssertLessThan(mse(model, features, targets), 0.005)
        XCTAssertEqual(model.predict([0.5]), 0.25, accuracy: 0.08)
        XCTAssertEqual(model.predict([-0.5]), 0.25, accuracy: 0.08)
    }

    func testImportanceConcentratesOnRealFeature() {
        // 特征 0 是真信号,特征 1 是常数噪声
        let features = (0..<200).map { [Double($0) / 200, 0.42] }
        let targets = features.map { 2 * $0[0] }

        var model = GBDT(trees: 50, depth: 2, learningRate: 0.1, minSamplesLeaf: 5)
        model.fit(features: features, targets: targets)

        XCTAssertEqual(model.featureImportance.count, 2)
        XCTAssertGreaterThan(model.featureImportance[0], 0.95)
        XCTAssertLessThan(model.featureImportance[1], 0.05)
    }

    func testPredictBeforeFitReturnsZero() {
        let model = GBDT()
        XCTAssertEqual(model.predict([1, 2, 3]), 0)
    }

    // MARK: - Forecaster

    func testForecasterRejectsShortHistory() {
        XCTAssertThrowsError(try GBDTForecaster.run(closes: (0..<50).map(Double.init))) { error in
            XCTAssertEqual(error as? QuantError, .tooShort(minimum: 90))
        }
    }

    func testForecasterProducesCompleteReport() throws {
        // 240 根带趋势和周期的合成价
        let closes: [Double] = (0..<240).map { (i: Int) -> Double in
            let x = Double(i)
            return 100 + x * 0.2 + 8 * sin(x / 9)
        }

        let forecast = try GBDTForecaster.run(closes: closes)

        XCTAssertTrue(["看涨", "看跌"].contains(forecast.direction))
        XCTAssertTrue((0...1).contains(forecast.validationHitRate))
        XCTAssertEqual(forecast.featureImportance.count, 8)   // r1..r5, ma5/ma20, mom10, vol10
        let weights: [Double] = forecast.featureImportance.map { $0.1 }
        XCTAssertEqual(weights.reduce(0, +), 1.0, accuracy: 0.01)
        XCTAssertTrue(forecast.promptText.contains("方向命中率"))
        XCTAssertTrue(forecast.promptText.contains("特征重要性"))
    }

    /// 确定性:同样输入两次训练结果一致(无随机源)。
    func testDeterministic() throws {
        let closes = (0..<200).map { 100 + 5 * sin(Double($0) / 7) }
        let a = try GBDTForecaster.run(closes: closes)
        let b = try GBDTForecaster.run(closes: closes)
        XCTAssertEqual(a.predictedReturn, b.predictedReturn)
        XCTAssertEqual(a.validationHitRate, b.validationHitRate)
    }
}
