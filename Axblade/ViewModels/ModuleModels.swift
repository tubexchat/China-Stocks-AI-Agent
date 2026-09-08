import Foundation
import AppKit

/// 交易日历:各模块共用,只拉一次。
@MainActor
final class TradingCalendar: ObservableObject {
    /// `yyyy-MM-dd` 升序。
    @Published private(set) var days: [String] = []
    private let data: any AShareDataProvider
    private var loading: Task<[String], Never>?

    init(data: any AShareDataProvider) {
        self.data = data
    }

    func load() async -> [String] {
        if !days.isEmpty { return days }
        if let loading { return await loading.value }
        let task = Task { [data] () -> [String] in
            let list = (try? await data.tradingDays()) ?? []
            return list.map { ShanghaiDate.normalizeDay($0.date) }.sorted()
        }
        loading = task
        let result = await task.value
        days = result
        loading = nil
        return result
    }

    /// 不晚于 `date` 的最近交易日。
    func latest(onOrBefore date: String) -> String? {
        days.last { $0 <= date }
    }

    func previous(_ date: String) -> String? { days.last { $0 < date } }
    func next(_ date: String) -> String? { days.first { $0 > date } }

    /// 以 `date` 结尾的最近 `count` 个交易日(升序)。
    func window(endingAt date: String, count: Int) -> [String] {
        Array(days.filter { $0 <= date }.suffix(count))
    }
}

/// 五个模块共用的加载状态骨架。
@MainActor
class ModuleModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var progressText: String?
    let data: any AShareDataProvider
    let calendar: TradingCalendar
    /// 错误 → 当前语言文案;由 AppViewModel 注入。
    var describe: (Error) -> String = { ($0 as? LocalizedError)?.errorDescription ?? $0.localizedDescription }
    private(set) var task: Task<Void, Never>?

    init(data: any AShareDataProvider, calendar: TradingCalendar) {
        self.data = data
        self.calendar = calendar
    }

    /// 串行化加载:新请求取消旧请求。
    func run(_ body: @escaping @MainActor () async throws -> Void) {
        task?.cancel()
        errorText = nil
        isLoading = true
        task = Task { @MainActor [weak self] in
            do {
                try await body()
            } catch is CancellationError {
            } catch {
                self?.errorText = self?.describe(error)
            }
            self?.isLoading = false
            self?.progressText = nil
        }
    }

    func cancel() {
        task?.cancel()
        isLoading = false
    }
}

// MARK: - 1. 涨停情绪市场脉冲

@MainActor
final class LimitUpPulseModel: ModuleModel {
    @Published private(set) var report: LimitUpPulseReport?
    @Published private(set) var limitUp: [LimitUpItem] = []
    @Published private(set) var limitDown: [LimitDownItem] = []
    @Published private(set) var limitBreak: [LimitBreakItem] = []
    @Published private(set) var ladder: LadderData?
    /// 当前查看的交易日 `yyyy-MM-dd`;nil = 今天。
    @Published private(set) var date: String?

    var displayDate: String { date ?? ShanghaiDate.string(Date()) }

    func load(date newDate: String? = nil) {
        if let newDate { date = newDate }
        let target = date
        run { [self] in
            let dateMs = target.flatMap(ShanghaiDate.date).map(ShanghaiDate.startOfDayMs)
            async let up = data.limitUpPool(dateMs: dateMs)
            async let down = data.limitDownPool(dateMs: dateMs)
            async let broken = data.limitBreakPool(dateMs: dateMs)
            async let ladderData = ladder == nil ? data.limitUpLadder() : ladder!
            let (u, d, b, l) = try await (up, down, broken, ladderData)
            try Task.checkCancellation()
            limitUp = u
            limitDown = d
            limitBreak = b
            ladder = l
            report = LimitUpPulseAnalyzer.run(date: displayDate, limitUp: u, limitDown: d, limitBreak: b, ladder: l)
        }
    }

    func stepDay(_ delta: Int) {
        Task { @MainActor in
            _ = await calendar.load()
            let current = calendar.latest(onOrBefore: displayDate) ?? displayDate
            let target = delta < 0 ? calendar.previous(current) : calendar.next(current)
            guard let target else { return }
            load(date: target)
        }
    }
}

// MARK: - 2. 龙虎榜资金流拓扑

@MainActor
final class DragonTigerTopologyModel: ModuleModel {
    @Published private(set) var graph: FlowGraph?
    @Published private(set) var all: DragonTigerData?
    @Published private(set) var hotMoney: DragonTigerData?
    @Published var selectedNodeID: String?
    @Published private(set) var date: String?

    var displayDate: String { all?.trade_date ?? date ?? "" }

    func load(date newDate: String? = nil) {
        if let newDate { date = newDate }
        let target = date
        run { [self] in
            async let allBoard = data.dragonTiger(board: .all, date: target)
            async let hotBoard = data.dragonTiger(board: .hot_money, date: target)
            let (a, h) = try await (allBoard, hotBoard)
            try Task.checkCancellation()
            all = a
            hotMoney = h
            date = a.trade_date ?? target
            selectedNodeID = nil
            graph = FlowGraphBuilder.build(date: a.trade_date ?? target ?? "", all: a, hotMoney: h)
        }
    }

    func stepDay(_ delta: Int) {
        Task { @MainActor in
            _ = await calendar.load()
            let current = displayDate.isEmpty ? ShanghaiDate.string(Date()) : displayDate
            let target = delta < 0 ? calendar.previous(current) : calendar.next(current)
            guard let target, target <= ShanghaiDate.string(Date()) else { return }
            load(date: target)
        }
    }
}

// MARK: - 3. 市场热度与飙升雷达

@MainActor
final class HeatRadarModel: ModuleModel {
    @Published var period: HotListPeriod = .day
    @Published private(set) var report: HeatRadarReport?
    @Published var selectedCode: String?
    @Published private(set) var rankTrend: [HotRankPoint] = []
    @Published private(set) var isLoadingTrend = false

    func load() {
        let period = period
        run { [self] in
            async let hot = data.hotStocks(period: period)
            async let surge = data.skyrocketList(period: period)
            async let anomalies = data.anomalies(tags: [])
            let (h, s) = try await (hot, surge)
            let a = (try? await anomalies) ?? []
            try Task.checkCancellation()
            report = HeatRadarAnalyzer.run(period: period, hot: h, surge: s, anomalies: a)
        }
    }

    func select(_ code: String?) {
        selectedCode = code
        rankTrend = []
        guard let code else { return }
        isLoadingTrend = true
        Task { @MainActor [self] in
            let end = Date()
            let start = end.addingTimeInterval(-30 * 86400)
            rankTrend = (try? await data.hotRankTrend(thscode: code, start: ShanghaiDate.string(start), end: ShanghaiDate.string(end))) ?? []
            isLoadingTrend = false
        }
    }
}

// MARK: - 4. 本地全市场趋势研究

@MainActor
final class MarketTrendModel: ModuleModel {
    @Published private(set) var report: MarketTrendReport?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var cacheBytes: Int64 = 0
    @Published var sectorTag = "industry"
    /// 个股研究
    @Published var stockSymbol = ""
    @Published private(set) var stockBars: [PriceBar] = []
    @Published private(set) var stockName: String?
    @Published private(set) var stockMetrics: TrendMetrics?
    @Published private(set) var stockRisk: RiskReport?
    @Published private(set) var stockBacktest: BacktestResult?
    @Published private(set) var stockForecast: Forecast?
    @Published private(set) var stockFactors: FactorReport?
    @Published private(set) var isLoadingStock = false
    @Published var stockError: String?
    @Published private(set) var dumpStatus: String?

    let store: MarketResearchStore

    init(data: any AShareDataProvider, calendar: TradingCalendar, store: MarketResearchStore) {
        self.store = store
        super.init(data: data, calendar: calendar)
        cacheBytes = store.diskUsage()
    }

    /// 启动时用本地缓存先出一版报告(不联网)。
    func loadFromCache() {
        let sectors = store.loadSeries(tag: sectorTag)
        let indices = store.loadSeries(tag: "indices")
        guard !sectors.isEmpty || !indices.isEmpty else { return }
        let snapshot = store.loadSnapshot()
        let breadth = snapshot.map { MarketBreadth.compute(date: $0.date, items: $0.items) }
        report = MarketTrendAnalyzer.run(
            breadth: breadth, breadthHistory: store.loadBreadthHistory(),
            indices: indices, sectors: sectors, sectorTag: sectorTag
        )
        cacheBytes = store.diskUsage()
    }

    /// 增量刷新:板块 / 指数只补最后一根缓存 K 线之后的数据;快照全量。
    func refresh(fullRebuild: Bool = false) {
        let tag = sectorTag
        run { [self] in
            let now = Date()
            let today = ShanghaiDate.string(now)

            progressText = "全市场快照…"
            let items = try await data.fullMarketSnapshot()
            try Task.checkCancellation()
            let breadth = MarketBreadth.compute(date: today, items: items)
            try store.saveSnapshot(date: today, items: items)
            try store.appendBreadth(breadth)

            // 指数
            let cachedIndices = fullRebuild ? [] : store.loadSeries(tag: "indices")
            let indices = try await update(
                catalog: MarketTrendAnalyzer.majorIndices.map { IndexCatalogItem(thscode: $0.0, name: $0.1) },
                cached: cachedIndices, now: now, label: "指数"
            )
            try store.saveSeries(indices, tag: "indices")

            // 板块
            progressText = "板块清单…"
            let catalog = try await data.indexCatalog(tag: tag)
            let cachedSectors = fullRebuild ? [] : store.loadSeries(tag: tag)
            let sectors = try await update(catalog: catalog, cached: cachedSectors, now: now, label: tag == "industry" ? "行业" : "概念")
            try store.saveSeries(sectors, tag: tag)

            report = MarketTrendAnalyzer.run(
                generatedAt: now, breadth: breadth, breadthHistory: store.loadBreadthHistory(),
                indices: indices, sectors: sectors, sectorTag: tag
            )
            lastUpdated = now
            cacheBytes = store.diskUsage()
        }
    }

    private func update(catalog: [IndexCatalogItem], cached: [SectorSeries], now: Date, label: String) async throws -> [SectorSeries] {
        let cachedByCode = Dictionary(cached.map { ($0.thscode, $0) }, uniquingKeysWith: { a, _ in a })
        let data = self.data
        // 并发压低到 3:上游对突发请求回 HTTP 429,客户端会退避重试,但别一上来就撞。
        let results = try await ConcurrentFetch.map(catalog, concurrency: 3, progress: { [weak self] done, total in
            Task { @MainActor in self?.progressText = "\(label) K 线 \(done)/\(total)" }
        }) { item -> (SectorSeries, Bool) in
            let old = cachedByCode[item.thscode]?.bars ?? []
            // 缓存最后一根往前多取 3 天,覆盖上游修订。
            let start = old.last.map { $0.date.addingTimeInterval(-3 * 86400) } ?? now.addingTimeInterval(-400 * 86400)
            do {
                let fresh = try await data.indexHistorical(thscode: item.thscode, start: start, end: now)
                return (SectorSeries(thscode: item.thscode, name: item.name, bars: SeriesMerge.merge(cached: old, fresh: fresh)), true)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // 单个板块重试后仍失败:留着缓存里的旧 K 线,不让整次刷新报废。
                return (SectorSeries(thscode: item.thscode, name: item.name, bars: old), false)
            }
        }
        let failures = results.filter { !$0.1 }.count
        if failures == results.count, !results.isEmpty {
            throw FuyaoError.http(429)
        }
        if failures > 0 {
            progressText = "\(label):\(failures) 个板块本次未更新(限流),沿用缓存"
        }
        return results.map(\.0).filter { !$0.bars.isEmpty }
    }

    func clearCache() {
        store.clear()
        report = nil
        cacheBytes = 0
    }

    // MARK: 个股研究

    func researchStock() {
        let raw = stockSymbol.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty, !isLoadingStock else { return }
        isLoadingStock = true
        stockError = nil
        Task { @MainActor [self] in
            do {
                let code = AShareSymbol.normalize(raw)
                let end = Date()
                async let bars = data.historical(thscode: code, start: end.addingTimeInterval(-400 * 86400), end: end, adjust: "forward")
                async let name = data.searchTickers(code)
                let fetched = try await bars
                stockName = (try? await name)?.first?.name
                stockBars = fetched
                let closes = fetched.map(\.close).filter { $0 > 0 }
                stockMetrics = TrendMetrics.compute(closes: closes)
                let label = stockName.map { "\(code) \($0)" } ?? code
                var risk = try? RiskAnalyzer.run(closes: closes)
                risk?.symbol = label; risk?.sourceName = "A股"
                var backtest = try? Backtester.run(closes: closes, fast: 5, slow: 20)
                backtest?.symbol = label; backtest?.sourceName = "A股"
                var forecast = try? GBDTForecaster.run(closes: closes)
                forecast?.symbol = label; forecast?.sourceName = "A股"
                var factors = try? FactorMiner.run(closes: closes)
                factors?.symbol = label; factors?.sourceName = "A股"
                stockRisk = risk
                stockBacktest = backtest
                stockForecast = forecast
                stockFactors = factors
                if stockBars.isEmpty { stockError = describe(FuyaoError.api(code: 3002, message: "没有拿到 K 线")) }
            } catch {
                stockError = describe(error)
            }
            isLoadingStock = false
        }
    }

    /// 个股研究汇总(复制报告用)。
    var stockPromptText: String? {
        guard let metrics = stockMetrics else { return nil }
        let code = AShareSymbol.normalize(stockSymbol)
        let title = stockName.map { "\(code)(\($0))" } ?? code
        var lines = ["【个股趋势研究 · \(title) · \(stockBars.count) 根日线(前复权)】"]
        lines.append("最新 \(NumberFormat.number(metrics.last));1日 \(RiskReport.percent(metrics.ret1));5日 \(RiskReport.percent(metrics.ret5));20日 \(RiskReport.percent(metrics.ret20));60日 \(RiskReport.percent(metrics.ret60))")
        lines.append("MA5 \(metrics.ma5.map(NumberFormat.number) ?? "—") / MA20 \(metrics.ma20.map(NumberFormat.number) ?? "—") / MA60 \(metrics.ma60.map(NumberFormat.number) ?? "—");\(metrics.bullishAlignment ? "多头排列" : (metrics.bearishAlignment ? "空头排列" : "均线交织"));MA20 斜率 \(RiskReport.percent(metrics.ma20Slope));60 日区间位置 \(RiskReport.percent(metrics.rangePosition));趋势分 \(metrics.score)")
        if let risk = stockRisk { lines.append(risk.promptText) }
        if let backtest = stockBacktest { lines.append(backtest.promptText) }
        if let forecast = stockForecast { lines.append(forecast.promptText) }
        if let factors = stockFactors { lines.append(factors.promptText) }
        return lines.joined(separator: "\n")
    }

    // MARK: 全市场 Parquet 数据包

    func downloadDump(kind: MarketDumpKind) {
        dumpStatus = "获取下载链接…"
        Task { @MainActor [self] in
            do {
                let link = try await data.marketDumpLink(kind: kind)
                guard let url = URL(string: link.presigned_url) else { throw FuyaoError.decoding("下载链接无效") }
                let panel = NSSavePanel()
                panel.nameFieldStringValue = url.lastPathComponent.isEmpty ? "\(kind.rawValue).parquet" : url.lastPathComponent
                panel.canCreateDirectories = true
                guard panel.runModal() == .OK, let destination = panel.url else {
                    dumpStatus = nil
                    return
                }
                dumpStatus = "下载中…"
                let (temp, response) = try await URLSession.shared.download(from: url)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw FuyaoError.http(http.statusCode)
                }
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: temp, to: destination)
                let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? 0
                dumpStatus = "已保存 \(destination.lastPathComponent)(\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))"
            } catch {
                dumpStatus = describe(error)
            }
        }
    }
}

// MARK: - 5. 龙虎榜机构与游资观察

@MainActor
final class DragonTigerWatchModel: ModuleModel {
    @Published var days = 5
    @Published private(set) var report: DragonTigerWatchReport?
    @Published var selectedPlayer: String?
    @Published var selectedStock: String?
    /// 过去的榜单不会变,按日期缓存。
    private var cache: [String: (all: DragonTigerData, hotMoney: DragonTigerData)] = [:]

    func load() {
        let count = days
        run { [self] in
            _ = await calendar.load()
            // 龙虎榜 T 日盘后才有;默认取上游给的「最近可用交易日」再往前数。
            let latest = try await data.dragonTiger(board: .all, date: nil)
            guard let latestDate = latest.trade_date else { throw FuyaoError.decoding("缺少 trade_date") }
            let latestHot = try await data.dragonTiger(board: .hot_money, date: nil)
            cache[latestDate] = (latest, latestHot)
            let window = calendar.days.isEmpty ? [latestDate] : calendar.window(endingAt: latestDate, count: count)
            var collected: [(date: String, all: DragonTigerData, hotMoney: DragonTigerData)] = []
            for (index, date) in window.enumerated() {
                try Task.checkCancellation()
                progressText = "龙虎榜 \(index + 1)/\(window.count)"
                if let hit = cache[date] {
                    collected.append((date, hit.all, hit.hotMoney))
                    continue
                }
                async let a = data.dragonTiger(board: .all, date: date)
                async let h = data.dragonTiger(board: .hot_money, date: date)
                guard let all = try? await a, let hot = try? await h else { continue }
                cache[date] = (all, hot)
                collected.append((date, all, hot))
            }
            report = DragonTigerWatchAnalyzer.run(days: collected.sorted { $0.date < $1.date })
        }
    }
}
