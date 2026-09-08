import Foundation

// MARK: - 市场宽度(全市场快照)

struct MarketBreadth: Codable, Equatable, Sendable {
    struct Bucket: Codable, Equatable, Sendable, Identifiable {
        var label: String
        var count: Int
        var id: String { label }
    }

    struct BoardStat: Codable, Equatable, Sendable, Identifiable {
        var board: String
        var total: Int
        var up: Int
        var down: Int
        var medianChange: Double
        var turnover: Double
        var id: String { board }
    }

    var date: String
    var total: Int
    var up: Int
    var down: Int
    var flat: Int
    var limitUpLike: Int
    var limitDownLike: Int
    var medianChange: Double
    var meanChange: Double
    var totalTurnover: Double
    /// 成交额前 100 只占全市场比重。
    var top100TurnoverShare: Double
    var buckets: [Bucket]
    var boards: [BoardStat]
    var topGainers: [PriceSnapshotItem]
    var topLosers: [PriceSnapshotItem]
    var topTurnover: [PriceSnapshotItem]

    var upRatio: Double { total == 0 ? 0 : Double(up) / Double(total) }

    static let bucketEdges: [(String, Double, Double)] = [
        ("≤-7%", -.infinity, -7), ("-7~-5", -7, -5), ("-5~-3", -5, -3), ("-3~-1", -3, -1), ("-1~0", -1, 0),
        ("0", 0, 0), ("0~1", 0, 1), ("1~3", 1, 3), ("3~5", 3, 5), ("5~7", 5, 7), ("≥7%", 7, .infinity)
    ]

    static func compute(date: String, items: [PriceSnapshotItem]) -> MarketBreadth {
        let priced = items.filter { ($0.last_price ?? 0) > 0 && $0.price_change_ratio_pct != nil }
        let changes = priced.compactMap(\.price_change_ratio_pct)
        let up = changes.filter { $0 > 0 }.count
        let down = changes.filter { $0 < 0 }.count
        let sorted = changes.sorted()
        let median = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
        let mean = changes.isEmpty ? 0 : changes.reduce(0, +) / Double(changes.count)
        let turnovers = priced.map { $0.turnover ?? 0 }.sorted(by: >)
        let totalTurnover = turnovers.reduce(0, +)
        let top100 = turnovers.prefix(100).reduce(0, +)

        var counts = [Int](repeating: 0, count: bucketEdges.count)
        for change in changes {
            if change == 0 { counts[5] += 1; continue }
            for (index, edge) in bucketEdges.enumerated() where index != 5 && change > edge.1 && change <= edge.2 {
                counts[index] += 1
                break
            }
        }

        var byBoard: [String: [PriceSnapshotItem]] = [:]
        for item in priced { byBoard[AShareSymbol.board(of: item.thscode), default: []].append(item) }
        let boards = ["主板", "创业板", "科创板", "北交所"].compactMap { name -> BoardStat? in
            guard let list = byBoard[name], !list.isEmpty else { return nil }
            let c = list.compactMap(\.price_change_ratio_pct).sorted()
            return BoardStat(
                board: name, total: list.count,
                up: c.filter { $0 > 0 }.count, down: c.filter { $0 < 0 }.count,
                medianChange: c.isEmpty ? 0 : c[c.count / 2],
                turnover: list.reduce(0) { $0 + ($1.turnover ?? 0) }
            )
        }

        let byChange = priced.sorted { ($0.price_change_ratio_pct ?? 0) > ($1.price_change_ratio_pct ?? 0) }
        return MarketBreadth(
            date: date,
            total: priced.count, up: up, down: down, flat: priced.count - up - down,
            limitUpLike: changes.filter { $0 >= 9.5 }.count,
            limitDownLike: changes.filter { $0 <= -9.5 }.count,
            medianChange: median, meanChange: mean,
            totalTurnover: totalTurnover,
            top100TurnoverShare: totalTurnover == 0 ? 0 : top100 / totalTurnover,
            buckets: zip(bucketEdges.map(\.0), counts).map { Bucket(label: $0, count: $1) },
            boards: boards,
            topGainers: Array(byChange.prefix(10)),
            topLosers: Array(byChange.suffix(10).reversed()),
            topTurnover: Array(priced.sorted { ($0.turnover ?? 0) > ($1.turnover ?? 0) }.prefix(10))
        )
    }
}

// MARK: - 趋势指标(单条序列)

struct TrendMetrics: Codable, Equatable, Sendable {
    var last: Double
    var ret1: Double
    var ret5: Double
    var ret20: Double
    var ret60: Double
    var ma5: Double?
    var ma20: Double?
    var ma60: Double?
    /// MA20 近 5 日斜率(相对)。
    var ma20Slope: Double
    var annualVol: Double
    var maxDrawdown60: Double
    /// 多头排列(价 > MA5 > MA20 > MA60)。
    var bullishAlignment: Bool
    /// 空头排列。
    var bearishAlignment: Bool
    /// 60 日区间位置 0–1。
    var rangePosition: Double

    static func compute(closes: [Double]) -> TrendMetrics? {
        guard closes.count >= 2, let last = closes.last, last > 0 else { return nil }
        func ret(_ n: Int) -> Double {
            guard closes.count > n, closes[closes.count - 1 - n] > 0 else { return 0 }
            return last / closes[closes.count - 1 - n] - 1
        }
        func ma(_ n: Int) -> Double? {
            guard closes.count >= n else { return nil }
            return closes.suffix(n).reduce(0, +) / Double(n)
        }
        let ma5 = ma(5), ma20 = ma(20), ma60 = ma(60)
        var slope = 0.0
        if closes.count >= 25, let now = ma20 {
            let earlier = closes[(closes.count - 25)..<(closes.count - 5)].reduce(0, +) / 20
            slope = earlier > 0 ? now / earlier - 1 : 0
        }
        let window = Array(closes.suffix(60))
        let returns = QuantMath.dailyReturns(window)
        let low = window.min() ?? last, high = window.max() ?? last
        let bullish = ma5.map { m5 in ma20.map { m20 in ma60.map { m60 in last > m5 && m5 > m20 && m20 > m60 } ?? (last > m5 && m5 > m20) } ?? false } ?? false
        let bearish = ma5.map { m5 in ma20.map { m20 in ma60.map { m60 in last < m5 && m5 < m20 && m20 < m60 } ?? (last < m5 && m5 < m20) } ?? false } ?? false
        return TrendMetrics(
            last: last, ret1: ret(1), ret5: ret(5), ret20: ret(20), ret60: ret(60),
            ma5: ma5, ma20: ma20, ma60: ma60, ma20Slope: slope,
            annualVol: QuantMath.annualizedVolatility(returns: returns),
            maxDrawdown60: QuantMath.maxDrawdown(window),
            bullishAlignment: bullish, bearishAlignment: bearish,
            rangePosition: high - low == 0 ? 0.5 : (last - low) / (high - low)
        )
    }

    /// 0–100 趋势分:20/60 日动量 + 均线结构 + 区间位置。
    var score: Int {
        var raw = 50.0
        raw += max(-20, min(20, ret20 * 100 * 1.0))
        raw += max(-15, min(15, ret60 * 100 * 0.4))
        raw += bullishAlignment ? 10 : (bearishAlignment ? -10 : 0)
        raw += (rangePosition - 0.5) * 10
        return Int(max(0, min(100, raw)).rounded())
    }
}

// MARK: - 板块趋势

struct SectorSeries: Codable, Equatable, Sendable, Identifiable {
    var thscode: String
    var name: String
    var bars: [PriceBar]
    var id: String { thscode }
}

struct SectorTrend: Equatable, Sendable, Identifiable {
    var thscode: String
    var name: String
    var metrics: TrendMetrics
    /// 近 10 日逐日收益(旧 → 新),给轮动热力图。
    var recentReturns: [Double]
    var closes: [Double]
    var id: String { thscode }
    var score: Int { metrics.score }
}

struct MarketTrendReport: Equatable, Sendable {
    struct IndexTrend: Equatable, Sendable, Identifiable {
        var thscode: String
        var name: String
        var metrics: TrendMetrics
        var closes: [Double]
        var id: String { thscode }
    }

    var generatedAt: Date
    var breadth: MarketBreadth?
    var breadthHistory: [MarketBreadth]
    var indices: [IndexTrend]
    var sectors: [SectorTrend]
    var sectorTag: String
    var recentDates: [String]

    var strongest: [SectorTrend] { sectors.sorted { $0.score > $1.score } }
    var weakest: [SectorTrend] { sectors.sorted { $0.score < $1.score } }
    var bullishCount: Int { sectors.filter(\.metrics.bullishAlignment).count }
    var bearishCount: Int { sectors.filter(\.metrics.bearishAlignment).count }

    /// 大盘综合判断。
    var regime: String {
        guard let benchmark = indices.first?.metrics else { return "数据不足" }
        let ratio = sectors.isEmpty ? 0.5 : Double(bullishCount) / Double(sectors.count)
        switch (benchmark.bullishAlignment, benchmark.bearishAlignment, ratio) {
        case (true, _, let r) where r > 0.5: return "多头趋势"
        case (true, _, _): return "指数强、板块分化"
        case (_, true, let r) where r < 0.2: return "空头趋势"
        case (_, true, _): return "指数弱、局部活跃"
        default: return benchmark.ret20 >= 0 ? "震荡偏强" : "震荡偏弱"
        }
    }

    var promptText: String {
        let idx = indices.map { "\($0.name) \(NumberFormat.number($0.metrics.last)) 20日\(RiskReport.percent($0.metrics.ret20)) 60日\(RiskReport.percent($0.metrics.ret60)) \($0.metrics.bullishAlignment ? "多头排列" : ($0.metrics.bearishAlignment ? "空头排列" : "均线交织"))" }.joined(separator: ";")
        let strong = strongest.prefix(10).map { "\($0.name)(分\($0.score),20日\(RiskReport.percent($0.metrics.ret20)))" }.joined(separator: ";")
        let weak = weakest.prefix(8).map { "\($0.name)(分\($0.score),20日\(RiskReport.percent($0.metrics.ret20)))" }.joined(separator: ";")
        var lines = ["【本地全市场趋势研究 · \(ShanghaiDate.dayFormatter.string(from: generatedAt))】", "大盘状态:\(regime);指数:\(idx)"]
        if let breadth {
            lines.append("市场宽度(\(breadth.date)):上涨 \(breadth.up) / 下跌 \(breadth.down) / 平盘 \(breadth.flat),涨幅≥9.5% \(breadth.limitUpLike) 家,跌幅≥9.5% \(breadth.limitDownLike) 家;中位涨跌 \(NumberFormat.percent(breadth.medianChange));总成交 \(MoneyFormat.yuan(breadth.totalTurnover)),前 100 只成交占比 \(RiskReport.percent(breadth.top100TurnoverShare))")
            lines.append("各板块:" + breadth.boards.map { "\($0.board) 涨\($0.up)/跌\($0.down) 中位\(NumberFormat.percent($0.medianChange))" }.joined(separator: ";"))
        }
        if breadthHistory.count >= 2 {
            lines.append("宽度历史(上涨占比):" + breadthHistory.suffix(10).map { "\($0.date.suffix(5)) \(RiskReport.percent($0.upRatio))" }.joined(separator: " "))
        }
        lines.append("板块(\(sectorTag == "industry" ? "行业" : "概念"),共 \(sectors.count)):多头排列 \(bullishCount),空头排列 \(bearishCount)")
        lines.append("最强板块:\(strong)")
        lines.append("最弱板块:\(weak)")
        return lines.joined(separator: "\n")
    }
}

enum MarketTrendAnalyzer {
    static let majorIndices: [(String, String)] = [
        ("000001.SH", "上证指数"), ("399001.SZ", "深证成指"), ("399006.SZ", "创业板指"),
        ("000300.SH", "沪深300"), ("000688.SH", "科创50"), ("399303.SZ", "国证2000")
    ]

    static func sectorTrend(_ series: SectorSeries) -> SectorTrend? {
        let closes = series.bars.map(\.close).filter { $0 > 0 }
        guard let metrics = TrendMetrics.compute(closes: closes) else { return nil }
        let recent = QuantMath.dailyReturns(Array(closes.suffix(11)))
        return SectorTrend(thscode: series.thscode, name: series.name, metrics: metrics, recentReturns: recent, closes: Array(closes.suffix(120)))
    }

    static func run(
        generatedAt: Date = Date(),
        breadth: MarketBreadth?,
        breadthHistory: [MarketBreadth],
        indices: [SectorSeries],
        sectors: [SectorSeries],
        sectorTag: String
    ) -> MarketTrendReport {
        let indexTrends = indices.compactMap { series -> MarketTrendReport.IndexTrend? in
            let closes = series.bars.map(\.close).filter { $0 > 0 }
            guard let metrics = TrendMetrics.compute(closes: closes) else { return nil }
            return .init(thscode: series.thscode, name: series.name, metrics: metrics, closes: Array(closes.suffix(120)))
        }
        let sectorTrends = sectors.compactMap(sectorTrend)
        let dates = (sectors.first ?? indices.first)?.bars.suffix(10).map { ShanghaiDate.string($0.date) } ?? []
        return MarketTrendReport(
            generatedAt: generatedAt,
            breadth: breadth,
            breadthHistory: breadthHistory.sorted { $0.date < $1.date },
            indices: indexTrends,
            sectors: sectorTrends,
            sectorTag: sectorTag,
            recentDates: dates
        )
    }
}

// MARK: - 本地研究数据库(JSON 文件)

/// 全市场研究数据落在本地:板块 / 指数日 K 增量更新,每日宽度快照追加。
/// 目录:Application Support/Axblade/research/
final class MarketResearchStore: Sendable {
    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    static func defaultDirectory() -> URL {
        SettingsStore.defaultDirectory().appendingPathComponent("research", isDirectory: true)
    }

    private func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    func loadSeries(tag: String) -> [SectorSeries] {
        decode([SectorSeries].self, from: url("series-\(tag).json")) ?? []
    }

    func saveSeries(_ series: [SectorSeries], tag: String) throws {
        try write(series, to: url("series-\(tag).json"))
    }

    func loadBreadthHistory() -> [MarketBreadth] {
        decode([MarketBreadth].self, from: url("breadth-history.json")) ?? []
    }

    /// 同一天覆盖,按日期升序保留最近 250 条。
    func appendBreadth(_ breadth: MarketBreadth) throws {
        var history = loadBreadthHistory().filter { $0.date != breadth.date }
        history.append(breadth)
        history.sort { $0.date < $1.date }
        try write(Array(history.suffix(250)), to: url("breadth-history.json"))
    }

    func loadSnapshot() -> (date: String, items: [PriceSnapshotItem])? {
        guard let stored = decode(StoredSnapshot.self, from: url("snapshot-latest.json")) else { return nil }
        return (stored.date, stored.items)
    }

    func saveSnapshot(date: String, items: [PriceSnapshotItem]) throws {
        try write(StoredSnapshot(date: date, items: items), to: url("snapshot-latest.json"))
    }

    /// 缓存总大小(字节)。
    func diskUsage() -> Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    private struct StoredSnapshot: Codable {
        var date: String
        var items: [PriceSnapshotItem]
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }
}

/// 把新拉的 K 线并进已缓存的序列:按日期去重,只保留最近 `keep` 根。
enum SeriesMerge {
    static func merge(cached: [PriceBar], fresh: [PriceBar], keep: Int = 300) -> [PriceBar] {
        var byDate: [Int64: PriceBar] = [:]
        for bar in cached { byDate[bar.date_ms] = bar }
        for bar in fresh { byDate[bar.date_ms] = bar }
        return Array(byDate.values.sorted { $0.date_ms < $1.date_ms }.suffix(keep))
    }
}
