import Foundation

/// 涨停情绪市场脉冲:把涨停 / 跌停 / 炸板池与连板天梯压成一组可读指标。
/// 纯函数,无网络;输入按交易日拉好后一次算完。
struct LimitUpPulseReport: Equatable, Sendable {
    struct ThemeCluster: Equatable, Sendable, Identifiable {
        var name: String
        var stocks: [LimitUpItem]
        var id: String { name }
        var count: Int { stocks.count }
        var maxBoards: Int { stocks.map(\.boards).max() ?? 1 }
    }

    struct TimeBucket: Equatable, Sendable, Identifiable {
        var label: String
        var count: Int
        var id: String { label }
    }

    struct LadderPoint: Equatable, Sendable, Identifiable {
        /// `yyyy-MM-dd`
        var date: String
        /// 2 板及以上的股票数(天梯只列 2 板+)。
        var consecutiveCount: Int
        var highestBoard: Int
        /// 次日晋级率;最近一天没有次日数据为 nil。
        var promotionRate: Double?
        var id: String { date }
    }

    var date: String
    var limitUpCount: Int
    var limitDownCount: Int
    var breakCount: Int
    var firstBoardCount: Int
    var consecutiveCount: Int
    var highestBoard: Int
    /// 板位 → 数量,键 1..highestBoard。
    var boardDistribution: [Int: Int]
    /// 封板率 = 涨停 / (涨停 + 炸板)。
    var sealRate: Double
    /// 10:00 前封板占比。
    var earlySealRatio: Double
    /// 封单强度:均值(当前封单 / 峰值封单)。
    var sealStrength: Double
    var totalSealMoney: Double
    var timeBuckets: [TimeBucket]
    var themes: [ThemeCluster]
    var topSeals: [LimitUpItem]
    var leaders: [LimitUpItem]
    var ladder: [LadderPoint]
    /// 0–100 综合情绪分。
    var score: Int
    var regime: String
    var stItems: [LimitUpItem]

    /// 分级:冰点 / 低迷 / 修复 / 活跃 / 亢奋。
    static func regime(for score: Int) -> String {
        switch score {
        case ..<20: "冰点"
        case 20..<40: "低迷"
        case 40..<60: "修复"
        case 60..<80: "活跃"
        default: "亢奋"
        }
    }

    var promptText: String {
        let dist = boardDistribution.keys.sorted().map { "\($0)板 \(boardDistribution[$0] ?? 0)" }.joined(separator: "、")
        let themeText = themes.prefix(8).map { "\($0.name)(\($0.count)只,最高\($0.maxBoards)板)" }.joined(separator: ";")
        let leaderText = leaders.prefix(6).map { "\($0.name) \($0.continue_day_text ?? "\($0.boards)板")\($0.limit_up_reason.map { "[\($0)]" } ?? "")" }.joined(separator: ";")
        let ladderText = ladder.suffix(10).map { point in
            let rate = point.promotionRate.map { RiskReport.percent($0) } ?? "—"
            return "\(point.date.suffix(5)) 高度\(point.highestBoard)板/连板\(point.consecutiveCount)只/晋级率\(rate)"
        }.joined(separator: ";")
        let times = timeBuckets.map { "\($0.label) \($0.count)" }.joined(separator: "、")
        return """
        【涨停情绪市场脉冲 · \(date)】
        情绪分 \(score)/100(\(regime));涨停 \(limitUpCount) 家 / 跌停 \(limitDownCount) 家 / 炸板 \(breakCount) 家;封板率 \(RiskReport.percent(sealRate))
        首板 \(firstBoardCount),连板 \(consecutiveCount),最高 \(highestBoard) 板;板位分布:\(dist)
        10 点前封板占比 \(RiskReport.percent(earlySealRatio));封单强度 \(RiskReport.percent(sealStrength));总封单 \(MoneyFormat.yuan(totalSealMoney))
        涨停时间分布:\(times)
        题材聚类(按涨停家数):\(themeText)
        高度龙头:\(leaderText)
        近 10 日连板天梯:\(ladderText)
        """
    }
}

enum MoneyFormat {
    /// 元 → 「1.23亿」/「4567万」。
    static func yuan(_ value: Double) -> String {
        let absValue = abs(value)
        let sign = value < 0 ? "-" : ""
        if absValue >= 1e8 { return sign + NumberFormat.number(absValue / 1e8) + "亿" }
        if absValue >= 1e4 { return sign + NumberFormat.number((absValue / 1e4).rounded()) + "万" }
        return sign + NumberFormat.number(absValue)
    }
}

enum LimitUpPulseAnalyzer {
    static let timeBucketLabels = ["竞价一字", "开盘半小时", "早盘", "午后", "尾盘"]

    static func timeBucketIndex(_ time: String?) -> Int? {
        guard let time, time.count >= 5,
              let hour = Int(time.prefix(2)), let minute = Int(time.dropFirst(3).prefix(2))
        else { return nil }
        let minutes = hour * 60 + minute
        switch minutes {
        case ..<(9 * 60 + 30): return 0
        case ..<(10 * 60): return 1
        case ..<(11 * 60 + 31): return 2
        case ..<(14 * 60): return 3
        default: return 4
        }
    }

    static func run(
        date: String,
        limitUp: [LimitUpItem],
        limitDown: [LimitDownItem],
        limitBreak: [LimitBreakItem],
        ladder: LadderData?
    ) -> LimitUpPulseReport {
        let upCount = limitUp.count
        let breakCount = limitBreak.count
        let boards = limitUp.map(\.boards)
        var distribution: [Int: Int] = [:]
        for board in boards { distribution[board, default: 0] += 1 }
        let highest = boards.max() ?? 0
        let firstBoards = boards.filter { $0 == 1 }.count
        let consecutive = upCount - firstBoards
        let sealRate = upCount + breakCount == 0 ? 0 : Double(upCount) / Double(upCount + breakCount)

        var bucketCounts = [Int](repeating: 0, count: timeBucketLabels.count)
        var early = 0
        for item in limitUp {
            if let index = timeBucketIndex(item.limit_up_time) {
                bucketCounts[index] += 1
                if index <= 1 { early += 1 }
            }
        }
        let earlyRatio = upCount == 0 ? 0 : Double(early) / Double(upCount)

        let strengths = limitUp.compactMap { item -> Double? in
            guard let seal = item.seal_money, let peak = item.max_seal_money, peak > 0 else { return nil }
            return min(seal / peak, 1)
        }
        let sealStrength = strengths.isEmpty ? 0 : strengths.reduce(0, +) / Double(strengths.count)
        let totalSeal = limitUp.compactMap(\.seal_money).reduce(0, +)

        // 题材:同一只股票的多个原因各计一次;按家数降序,家数相同按最高板。
        var clusters: [String: [LimitUpItem]] = [:]
        for item in limitUp {
            for theme in item.themes { clusters[theme, default: []].append(item) }
        }
        let themes = clusters.map { LimitUpPulseReport.ThemeCluster(name: $0.key, stocks: $0.value.sorted { $0.boards > $1.boards }) }
            .filter { $0.count >= 2 }
            .sorted { ($0.count, $0.maxBoards, $0.name) > ($1.count, $1.maxBoards, $1.name) }

        let topSeals = limitUp.sorted { ($0.seal_money ?? 0) > ($1.seal_money ?? 0) }.prefix(8).map { $0 }
        let leaders = limitUp.sorted { ($0.boards, $0.seal_money ?? 0) > ($1.boards, $1.seal_money ?? 0) }.prefix(10).map { $0 }

        let ladderPoints = ladderSeries(ladder)
        let latestPromotion = ladderPoints.last(where: { $0.promotionRate != nil })?.promotionRate

        let score = sentimentScore(
            sealRate: sealRate,
            limitUp: upCount, limitDown: limitDown.count,
            consecutiveRatio: upCount == 0 ? 0 : Double(consecutive) / Double(upCount),
            highestBoard: highest,
            promotionRate: latestPromotion
        )

        return LimitUpPulseReport(
            date: date,
            limitUpCount: upCount,
            limitDownCount: limitDown.count,
            breakCount: breakCount,
            firstBoardCount: firstBoards,
            consecutiveCount: consecutive,
            highestBoard: highest,
            boardDistribution: distribution,
            sealRate: sealRate,
            earlySealRatio: earlyRatio,
            sealStrength: sealStrength,
            totalSealMoney: totalSeal,
            timeBuckets: zip(timeBucketLabels, bucketCounts).map { .init(label: $0, count: $1) },
            themes: themes,
            topSeals: topSeals,
            leaders: leaders,
            ladder: ladderPoints,
            score: score,
            regime: LimitUpPulseReport.regime(for: score),
            stItems: limitUp.filter { $0.is_st == true }
        )
    }

    /// 天梯按日期升序(旧 → 新)。
    static func ladderSeries(_ ladder: LadderData?) -> [LimitUpPulseReport.LadderPoint] {
        guard let ladder else { return [] }
        return ladder.item.map { day in
            let stocks = day.boards.all
            let judged = stocks.compactMap(\.seal_nextday)
            return LimitUpPulseReport.LadderPoint(
                date: ShanghaiDate.normalizeDay(day.date),
                consecutiveCount: stocks.count,
                highestBoard: stocks.map(\.board_num).max() ?? 0,
                promotionRate: judged.isEmpty ? nil : Double(judged.filter { $0 }.count) / Double(judged.count)
            )
        }
        .sorted { $0.date < $1.date }
    }

    /// 0–100:封板率 30 / 涨跌停对比 20 / 连板占比 20 / 高度 15 / 晋级率 15。
    static func sentimentScore(
        sealRate: Double, limitUp: Int, limitDown: Int,
        consecutiveRatio: Double, highestBoard: Int, promotionRate: Double?
    ) -> Int {
        let balance = limitUp + limitDown == 0 ? 0.5 : Double(limitUp) / Double(limitUp + limitDown)
        let height = min(Double(highestBoard) / 8, 1)
        let promotion = promotionRate ?? 0.5
        let raw = 0.30 * sealRate + 0.20 * balance + 0.20 * min(consecutiveRatio / 0.4, 1) + 0.15 * height + 0.15 * promotion
        return Int((raw * 100).rounded())
    }
}
