import Foundation

/// 纯 Swift 梯度提升回归树(平方损失)。
/// 样本量在千级以内,用精确分裂(逐特征排序扫描)就足够快;无任何随机源,结果确定。
struct GBDT {
    var trees: Int
    var depth: Int
    var learningRate: Double
    var minSamplesLeaf: Int

    private var baseline = 0.0
    private var forest: [Node] = []
    private var importanceGains: [Double] = []

    init(trees: Int = 120, depth: Int = 3, learningRate: Double = 0.1, minSamplesLeaf: Int = 5) {
        self.trees = trees
        self.depth = depth
        self.learningRate = learningRate
        self.minSamplesLeaf = minSamplesLeaf
    }

    /// 分裂增益归一化后的特征重要性;未训练时为空。
    var featureImportance: [Double] {
        let total = importanceGains.reduce(0, +)
        guard total > 0 else { return importanceGains }
        return importanceGains.map { $0 / total }
    }

    mutating func fit(features: [[Double]], targets: [Double]) {
        guard !features.isEmpty, features.count == targets.count else { return }
        let featureCount = features[0].count
        importanceGains = [Double](repeating: 0, count: featureCount)
        forest.removeAll()

        baseline = targets.reduce(0, +) / Double(targets.count)
        var predictions = [Double](repeating: baseline, count: targets.count)

        for _ in 0..<trees {
            // 平方损失的负梯度就是残差
            let residuals = zip(targets, predictions).map(-)
            let tree = buildTree(
                features: features,
                targets: residuals,
                indices: Array(features.indices),
                remainingDepth: depth
            )
            forest.append(tree)
            for index in features.indices {
                predictions[index] += learningRate * evaluate(tree, features[index])
            }
        }
    }

    func predict(_ row: [Double]) -> Double {
        var value = baseline
        for tree in forest {
            value += learningRate * evaluate(tree, row)
        }
        return value
    }

    // MARK: - 树

    private indirect enum Node {
        case leaf(Double)
        case split(feature: Int, threshold: Double, left: Node, right: Node)
    }

    private func evaluate(_ node: Node, _ row: [Double]) -> Double {
        switch node {
        case .leaf(let value):
            return value
        case .split(let feature, let threshold, let left, let right):
            return row[feature] <= threshold ? evaluate(left, row) : evaluate(right, row)
        }
    }

    private mutating func buildTree(
        features: [[Double]], targets: [Double], indices: [Int], remainingDepth: Int
    ) -> Node {
        let mean = indices.map { targets[$0] }.reduce(0, +) / Double(indices.count)
        guard remainingDepth > 0, indices.count >= minSamplesLeaf * 2 else { return .leaf(mean) }

        guard let best = bestSplit(features: features, targets: targets, indices: indices) else {
            return .leaf(mean)
        }
        importanceGains[best.feature] += best.gain

        let left = buildTree(
            features: features, targets: targets, indices: best.leftIndices, remainingDepth: remainingDepth - 1
        )
        let right = buildTree(
            features: features, targets: targets, indices: best.rightIndices, remainingDepth: remainingDepth - 1
        )
        return .split(feature: best.feature, threshold: best.threshold, left: left, right: right)
    }

    private struct Split {
        var feature: Int
        var threshold: Double
        var gain: Double
        var leftIndices: [Int]
        var rightIndices: [Int]
    }

    /// 逐特征排序扫描,找平方和下降最大的分裂点。
    private func bestSplit(features: [[Double]], targets: [Double], indices: [Int]) -> Split? {
        let count = Double(indices.count)
        let totalSum = indices.map { targets[$0] }.reduce(0, +)
        let parentScore = totalSum * totalSum / count

        var best: Split?
        for feature in features[0].indices {
            let sorted = indices.sorted { features[$0][feature] < features[$1][feature] }
            var leftSum = 0.0
            for position in 0..<(sorted.count - 1) {
                leftSum += targets[sorted[position]]
                let leftCount = position + 1
                let rightCount = sorted.count - leftCount
                guard leftCount >= minSamplesLeaf, rightCount >= minSamplesLeaf else { continue }

                let a = features[sorted[position]][feature]
                let b = features[sorted[position + 1]][feature]
                guard a < b else { continue }   // 相同取值之间不能切

                let rightSum = totalSum - leftSum
                let gain = leftSum * leftSum / Double(leftCount)
                    + rightSum * rightSum / Double(rightCount)
                    - parentScore
                if gain > (best?.gain ?? 1e-12) {
                    best = Split(
                        feature: feature,
                        threshold: (a + b) / 2,
                        gain: gain,
                        leftIndices: Array(sorted[0...position]),
                        rightIndices: Array(sorted[(position + 1)...])
                    )
                }
            }
        }
        return best
    }
}
