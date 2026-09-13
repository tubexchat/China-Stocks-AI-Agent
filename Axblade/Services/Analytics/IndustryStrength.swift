import Foundation

// MARK: - 行业强度作战矩阵

/// 行业指数日 K → 5 / 20 / 60 日相对强度(相对基准指数)、成交额脉冲、排名变化与市场宽度。
/// 全部口径都是「指数自身」的价格与成交额;成分股层面的等权涨跌只是代理,见 `IndustryConstituentEvidence`。
struct IndustryStrengthReport: Equatable, Sendable {
    struct Row: Equatable, Sendable, Identifiable {
        var thscode: String
        var name: String
        var last: Double
        /// 绝对涨跌(小数)。
        var ret5: Double?
        var ret20: Double?
        var ret60: Double?
        /// 相对基准:(1 + 行业) / (1 + 基准) − 1;没有基准时等于绝对涨跌。
        var rs5: Double?
        var rs20: Double?
        var rs60: Double?
        /// 成交额脉冲:近 5 日均额 / 近 20 日均额;20 日均额为 0 或缺失时为 nil。
        var turnoverPulse: Double?
        /// 近 5 日日均成交额(元)。
        var turnover5: Double
        var aboveMA20: Bool
        /// 按 20 日相对强度的名次(1 = 最强)。
        var rank: Int
        /// 5 个交易日前的名次(同口径重算)。
        var previousRank: Int?
        /// 0–100 综合强度分:5 / 20 / 60 日相对强度的百分位按 0.2 / 0.5 / 0.3 加权。
        var score: Int
        /// 近 20 日逐日收益(旧 → 新),热力带用。
        var recentReturns: [Double]
        var id: String { thscode }
        /// 正数 = 名次上升。
        var rankChange: Int? { previousRank.map { $0 - rank } }
    }

    struct Breadth: Equatable, Sendable {
        var total: Int
        /// 20 日绝对收益 > 0 的行业数。
        var positive20: Int
        /// 20 日跑赢基准的行业数。
        var outperform20: Int
        var aboveMA20: Int
        /// 成交额脉冲 > 1 的行业数。
        var pulseAbove1: Int

        func ratio(_ count: Int) -> Double { total == 0 ? 0 : Double(count) / Double(total) }
    }

    var generatedAt: Date
    /// 最后一根 K 线的日期 `yyyy-MM-dd`。
    var dataDate: String
    var benchmarkCode: String?
    var benchmarkName: String?
    var benchmarkRet5: Double?
    var benchmarkRet20: Double?
    var benchmarkRet60: Double?
    /// 按综合强度分降序。
    var rows: [Row]
    var breadth: Breadth
    /// 近 20 个交易日 `yyyy-MM-dd`(旧 → 新)。
    var recentDates: [String]

    var strongest: [Row] { rows }
    var weakest: [Row] { rows.reversed() }
    /// 名次上升最多的行业。
    var climbers: [Row] { rows.filter { ($0.rankChange ?? 0) > 0 }.sorted { ($0.rankChange ?? 0) > ($1.rankChange ?? 0) } }
    var fallers: [Row] { rows.filter { ($0.rankChange ?? 0) < 0 }.sorted { ($0.rankChange ?? 0) < ($1.rankChange ?? 0) } }

    var promptText: String {
        func pct(_ value: Double?) -> String { value.map { RiskReport.percent($0) } ?? "—" }
        let bench = benchmarkName.map { "基准 \($0):5日\(pct(benchmarkRet5)) / 20日\(pct(benchmarkRet20)) / 60日\(pct(benchmarkRet60))" } ?? "无基准(相对强度 = 绝对涨跌)"
        let strong = rows.prefix(10).map { "\($0.name)(分\($0.score),RS20 \(pct($0.rs20)),脉冲 \($0.turnoverPulse.map { NumberFormat.number($0) } ?? "—")\($0.rankChange.map { $0 == 0 ? "" : ($0 > 0 ? ",↑\($0)" : ",↓\(-$0)") } ?? ""))" }.joined(separator: ";")
        let weak = rows.suffix(8).reversed().map { "\($0.name)(分\($0.score),RS20 \(pct($0.rs20)))" }.joined(separator: ";")
        let climb = climbers.prefix(6).map { "\($0.name) ↑\($0.rankChange ?? 0)" }.joined(separator: " ")
        return """
        【行业强度作战矩阵 · 数据日 \(dataDate) · \(rows.count) 个同花顺行业指数】
        \(bench)
        市场宽度:20 日上涨 \(breadth.positive20)/\(breadth.total),跑赢基准 \(breadth.outperform20)/\(breadth.total),站上 MA20 \(breadth.aboveMA20)/\(breadth.total),成交额脉冲 > 1 的 \(breadth.pulseAbove1)/\(breadth.total)
        最强行业:\(strong)
        最弱行业:\(weak)
        排名上升:\(climb.isEmpty ? "无" : climb)
        口径:相对强度 = (1+行业区间涨跌)/(1+基准区间涨跌)−1;成交额脉冲 = 5 日均额 / 20 日均额;强度分 = RS5/RS20/RS60 百分位 × 0.2/0.5/0.3;名次按 RS20。仅供研究参考,不构成投资建议。
        """
    }
}

enum IndustryStrengthAnalyzer {
    /// 相对强度的基准:沪深 300(与全市场趋势模块共用同一份指数缓存)。
    static let benchmark = (thscode: "000300.SH", name: "沪深300")

    static func trailingReturn(_ closes: [Double], _ n: Int) -> Double? {
        guard closes.count > n, let last = closes.last, closes[closes.count - 1 - n] > 0 else { return nil }
        return last / closes[closes.count - 1 - n] - 1
    }

    static func relative(_ ret: Double?, benchmark: Double?) -> Double? {
        guard let ret else { return nil }
        guard let benchmark, benchmark > -1 else { return ret }
        return (1 + ret) / (1 + benchmark) - 1
    }

    /// 成交额脉冲:近 5 日均额 / 近 20 日均额。
    static func turnoverPulse(_ turnovers: [Double]) -> Double? {
        guard turnovers.count >= 20 else { return nil }
        let short = turnovers.suffix(5).reduce(0, +) / 5
        let long = turnovers.suffix(20).reduce(0, +) / 20
        return long > 0 ? short / long : nil
    }

    /// 百分位(0–100):比自己小的个数 / (n − 1)。
    static func percentile(_ value: Double, in values: [Double]) -> Double {
        guard values.count > 1 else { return 50 }
        let below = values.filter { $0 < value }.count
        return Double(below) / Double(values.count - 1) * 100
    }

    /// 按 RS20 排名(降序,1 = 最强);nil 排最后。
    static func ranks(_ keyed: [(String, Double?)]) -> [String: Int] {
        let sorted = keyed.sorted { a, b in
            switch (a.1, b.1) {
            case let (x?, y?): return x > y
            case (nil, _?): return false
            case (_?, nil): return true
            default: return a.0 < b.0
            }
        }
        var result: [String: Int] = [:]
        for (index, entry) in sorted.enumerated() { result[entry.0] = index + 1 }
        return result
    }

    static func run(generatedAt: Date = Date(), benchmark: SectorSeries?, sectors: [SectorSeries]) -> IndustryStrengthReport? {
        let usable = sectors.filter { $0.bars.filter { $0.close > 0 }.count >= 2 }
        guard !usable.isEmpty else { return nil }

        let benchCloses = benchmark?.bars.map(\.close).filter { $0 > 0 } ?? []
        let b5 = trailingReturn(benchCloses, 5), b20 = trailingReturn(benchCloses, 20), b60 = trailingReturn(benchCloses, 60)
        // 5 个交易日前的基准区间收益(重算历史名次用)。
        let benchPrev = Array(benchCloses.dropLast(5))
        let b20Prev = trailingReturn(benchPrev, 20)

        struct Partial {
            var series: SectorSeries
            var closes: [Double]
            var ret5: Double?, ret20: Double?, ret60: Double?
            var rs5: Double?, rs20: Double?, rs60: Double?
            var rs20Prev: Double?
            var pulse: Double?
            var turnover5: Double
            var aboveMA20: Bool
        }
        let partials: [Partial] = usable.map { series in
            let closes = series.bars.map(\.close).filter { $0 > 0 }
            let r5 = trailingReturn(closes, 5), r20 = trailingReturn(closes, 20), r60 = trailingReturn(closes, 60)
            let turnovers = series.bars.map { $0.turnover ?? 0 }
            let ma20 = closes.count >= 20 ? closes.suffix(20).reduce(0, +) / 20 : nil
            return Partial(
                series: series, closes: closes,
                ret5: r5, ret20: r20, ret60: r60,
                rs5: relative(r5, benchmark: b5), rs20: relative(r20, benchmark: b20), rs60: relative(r60, benchmark: b60),
                rs20Prev: relative(trailingReturn(Array(closes.dropLast(5)), 20), benchmark: b20Prev),
                pulse: turnoverPulse(turnovers),
                turnover5: turnovers.suffix(5).reduce(0, +) / Double(max(min(turnovers.count, 5), 1)),
                aboveMA20: ma20.map { (closes.last ?? 0) > $0 } ?? false
            )
        }

        let rankNow = ranks(partials.map { ($0.series.thscode, $0.rs20) })
        let rankPrev = ranks(partials.map { ($0.series.thscode, $0.rs20Prev) })
        let pool5 = partials.compactMap(\.rs5), pool20 = partials.compactMap(\.rs20), pool60 = partials.compactMap(\.rs60)

        var rows: [IndustryStrengthReport.Row] = partials.map { p in
            var weighted = 0.0, weightSum = 0.0
            if let v = p.rs5 { weighted += 0.2 * percentile(v, in: pool5); weightSum += 0.2 }
            if let v = p.rs20 { weighted += 0.5 * percentile(v, in: pool20); weightSum += 0.5 }
            if let v = p.rs60 { weighted += 0.3 * percentile(v, in: pool60); weightSum += 0.3 }
            let score = weightSum > 0 ? Int((weighted / weightSum).rounded()) : 50
            return .init(
                thscode: p.series.thscode, name: p.series.name, last: p.closes.last ?? 0,
                ret5: p.ret5, ret20: p.ret20, ret60: p.ret60,
                rs5: p.rs5, rs20: p.rs20, rs60: p.rs60,
                turnoverPulse: p.pulse, turnover5: p.turnover5, aboveMA20: p.aboveMA20,
                rank: rankNow[p.series.thscode] ?? partials.count,
                previousRank: p.rs20Prev == nil ? nil : rankPrev[p.series.thscode],
                score: max(0, min(100, score)),
                recentReturns: QuantMath.dailyReturns(Array(p.closes.suffix(21)))
            )
        }
        rows.sort { ($0.score, $0.rs20 ?? -1, $0.name) > ($1.score, $1.rs20 ?? -1, $1.name) }

        let breadth = IndustryStrengthReport.Breadth(
            total: rows.count,
            positive20: rows.filter { ($0.ret20 ?? 0) > 0 }.count,
            outperform20: rows.filter { ($0.rs20 ?? 0) > 0 }.count,
            aboveMA20: rows.filter(\.aboveMA20).count,
            pulseAbove1: rows.filter { ($0.turnoverPulse ?? 0) > 1 }.count
        )
        let longest = usable.max { $0.bars.count < $1.bars.count } ?? usable[0]
        let dates = longest.bars.suffix(20).map { ShanghaiDate.string($0.date) }
        let lastDate = usable.compactMap { $0.bars.last?.date }.max().map(ShanghaiDate.string) ?? ""

        return IndustryStrengthReport(
            generatedAt: generatedAt, dataDate: lastDate,
            benchmarkCode: benchmark?.thscode, benchmarkName: benchmark?.name,
            benchmarkRet5: b5, benchmarkRet20: b20, benchmarkRet60: b60,
            rows: rows, breadth: breadth, recentDates: dates
        )
    }
}

// MARK: - 行业 — 个股联动证据(当前成分 + 快照)

/// 选中某个行业后:当前成分股快照 → 上涨 / 下跌家数、等权涨跌代理、成交额活跃度。
/// **等权涨跌代理不是指数贡献**:成分是「当前」清单,权重也不是指数权重,只能作为行业内部一致性的旁证。
struct IndustryConstituentEvidence: Equatable, Sendable {
    struct Member: Equatable, Sendable, Identifiable {
        var thscode: String
        var name: String
        var change: Double?
        var turnover: Double?
        var id: String { thscode }
    }

    var thscode: String
    var name: String
    var fetchedAt: Date
    var total: Int
    /// 有报价的成分数(快照缺失的不计入涨跌家数)。
    var priced: Int
    var up: Int
    var down: Int
    var flat: Int
    var limitUpLike: Int
    var limitDownLike: Int
    /// 等权涨跌代理:成分涨跌幅的简单平均(百分数)。
    var equalWeightChange: Double?
    var medianChange: Double?
    /// 涨跌幅离散度(样本标准差,百分数)。
    var dispersion: Double?
    /// 指数当日涨跌幅(百分数,来自指数快照)。
    var indexChange: Double?
    var totalTurnover: Double
    var averageTurnover: Double?
    /// 成交额前 5 只占行业成交比重。
    var top5TurnoverShare: Double?
    var topGainers: [Member]
    var topLosers: [Member]
    var topTurnover: [Member]

    var upRatio: Double { priced == 0 ? 0 : Double(up) / Double(priced) }
    /// 指数涨跌与等权代理的差(百分点);差得大说明权重股主导。
    var weightGap: Double? {
        guard let indexChange, let equalWeightChange else { return nil }
        return indexChange - equalWeightChange
    }

    var promptText: String {
        let pct: (Double?) -> String = { $0.map(NumberFormat.percent) ?? "—" }
        return """
        【行业—个股联动 · \(name) \(thscode) · \(ShanghaiDate.dayFormatter.string(from: fetchedAt))】
        当前成分 \(total) 只(有报价 \(priced)):上涨 \(up) / 下跌 \(down) / 平盘 \(flat),涨幅≥9.5% \(limitUpLike) 只,跌幅≥9.5% \(limitDownLike) 只
        指数涨跌 \(pct(indexChange));等权涨跌代理 \(pct(equalWeightChange))(中位 \(pct(medianChange)),离散度 \(dispersion.map { NumberFormat.number($0) } ?? "—") 个百分点);二者差 \(weightGap.map { NumberFormat.number($0) } ?? "—") 个百分点
        成交额合计 \(MoneyFormat.yuan(totalTurnover)),前 5 只占 \(top5TurnoverShare.map { RiskReport.percent($0) } ?? "—")
        领涨:\(topGainers.prefix(5).map { "\($0.name) \(pct($0.change))" }.joined(separator: " "));领跌:\(topLosers.prefix(5).map { "\($0.name) \(pct($0.change))" }.joined(separator: " "))
        注意:等权涨跌代理基于当前成分清单与等权口径,不是指数贡献拆解。
        """
    }
}

enum IndustryConstituentAnalyzer {
    static func run(
        thscode: String, name: String, fetchedAt: Date = Date(),
        constituents: [TickerSearchItem], snapshot: [PriceSnapshotItem], indexSnapshot: PriceSnapshotItem?
    ) -> IndustryConstituentEvidence {
        let byCode = Dictionary(snapshot.map { ($0.thscode, $0) }, uniquingKeysWith: { a, _ in a })
        let members: [IndustryConstituentEvidence.Member] = constituents.map { item in
            let quote = byCode[item.thscode]
            let priced = (quote?.last_price ?? 0) > 0
            return .init(thscode: item.thscode, name: item.name ?? item.ticker ?? item.thscode, change: priced ? quote?.price_change_ratio_pct : nil, turnover: quote?.turnover)
        }
        let changes = members.compactMap(\.change)
        let sorted = changes.sorted()
        let mean = changes.isEmpty ? nil : changes.reduce(0, +) / Double(changes.count)
        var dispersion: Double?
        if let mean, changes.count > 1 {
            dispersion = (changes.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(changes.count - 1)).squareRoot()
        }
        let turnovers = members.map { $0.turnover ?? 0 }.sorted(by: >)
        let total = turnovers.reduce(0, +)
        let byChange = members.filter { $0.change != nil }.sorted { ($0.change ?? 0) > ($1.change ?? 0) }
        return IndustryConstituentEvidence(
            thscode: thscode, name: name, fetchedAt: fetchedAt,
            total: members.count, priced: changes.count,
            up: changes.filter { $0 > 0 }.count, down: changes.filter { $0 < 0 }.count, flat: changes.filter { $0 == 0 }.count,
            limitUpLike: changes.filter { $0 >= 9.5 }.count, limitDownLike: changes.filter { $0 <= -9.5 }.count,
            equalWeightChange: mean,
            medianChange: sorted.isEmpty ? nil : sorted[sorted.count / 2],
            dispersion: dispersion,
            indexChange: indexSnapshot?.price_change_ratio_pct,
            totalTurnover: total,
            averageTurnover: changes.isEmpty ? nil : total / Double(max(members.count, 1)),
            top5TurnoverShare: total > 0 ? turnovers.prefix(5).reduce(0, +) / total : nil,
            topGainers: Array(byChange.prefix(8)),
            topLosers: Array(byChange.suffix(8).reversed()),
            topTurnover: Array(members.sorted { ($0.turnover ?? 0) > ($1.turnover ?? 0) }.prefix(8))
        )
    }
}

// MARK: - 板块 / 指数日 K 增量更新(全市场趋势与行业强度矩阵共用)

enum SectorSeriesUpdater {
    struct Outcome: Sendable {
        var series: [SectorSeries]
        /// 本次没拉到新数据(沿用缓存)的板块数。
        var failures: Int
    }

    /// 每个板块只补缓存最后一根 K 线之后的数据(往前多取 3 天覆盖上游修订);单个板块失败沿用缓存,全部失败才抛错。
    static func update(
        data: any AShareDataProvider,
        catalog: [IndexCatalogItem],
        cached: [SectorSeries],
        now: Date,
        concurrency: Int = 3,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> Outcome {
        let cachedByCode = Dictionary(cached.map { ($0.thscode, $0) }, uniquingKeysWith: { a, _ in a })
        let results = try await ConcurrentFetch.map(catalog, concurrency: concurrency, progress: progress) { item -> (SectorSeries, Bool) in
            let old = cachedByCode[item.thscode]?.bars ?? []
            let start = old.last.map { $0.date.addingTimeInterval(-3 * 86400) } ?? now.addingTimeInterval(-400 * 86400)
            do {
                let fresh = try await data.indexHistorical(thscode: item.thscode, start: start, end: now)
                return (SectorSeries(thscode: item.thscode, name: item.name, bars: SeriesMerge.merge(cached: old, fresh: fresh)), true)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return (SectorSeries(thscode: item.thscode, name: item.name, bars: old), false)
            }
        }
        let failures = results.filter { !$0.1 }.count
        if failures == results.count, !results.isEmpty {
            throw FuyaoError.http(429)
        }
        return Outcome(series: results.map(\.0).filter { !$0.bars.isEmpty }, failures: failures)
    }
}
