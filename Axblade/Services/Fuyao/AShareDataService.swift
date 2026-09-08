import Foundation

enum HotListPeriod: String, CaseIterable, Sendable, Identifiable {
    case day, hour
    var id: String { rawValue }
}

enum MarketDumpKind: String, CaseIterable, Sendable, Identifiable {
    /// 10 年全量日 K
    case dailyK = "daily-k"
    /// 最近 10 个交易日日 K
    case dailyK10d = "daily-k-10d"
    /// 复权因子事件流
    case adjustmentFactors = "adjustment-factors"
    var id: String { rawValue }
}

/// A 股数据源抽象。视图模型只依赖这个协议,测试注入内存实现。
protocol AShareDataProvider: Sendable {
    func tradingDays() async throws -> [TradingDay]
    func searchTickers(_ query: String) async throws -> [TickerSearchItem]
    func snapshot(thscodes: [String]) async throws -> [PriceSnapshotItem]
    /// 全市场快照(一次拉全量,上游 5000+ 条)。
    func fullMarketSnapshot() async throws -> [PriceSnapshotItem]
    func historical(thscode: String, start: Date, end: Date, adjust: String) async throws -> [PriceBar]
    func indexCatalog(tag: String) async throws -> [IndexCatalogItem]
    func indexSnapshot(thscodes: [String]) async throws -> [PriceSnapshotItem]
    func indexHistorical(thscode: String, start: Date, end: Date) async throws -> [PriceBar]
    func constituents(thscode: String) async throws -> [TickerSearchItem]

    func limitUpPool(dateMs: Int64?) async throws -> [LimitUpItem]
    func limitDownPool(dateMs: Int64?) async throws -> [LimitDownItem]
    func limitBreakPool(dateMs: Int64?) async throws -> [LimitBreakItem]
    func limitUpLadder() async throws -> LadderData

    func hotStocks(period: HotListPeriod) async throws -> [HotStockItem]
    func skyrocketList(period: HotListPeriod) async throws -> [HotStockItem]
    func hotStockHistory(date: String) async throws -> [HotStockHistoryItem]
    func hotRankTrend(thscode: String, start: String, end: String) async throws -> [HotRankPoint]
    func anomalies(tags: [String]) async throws -> [AnomalyItem]
    func anomalies(thscodes: [String]) async throws -> [AnomalyItem]

    func dragonTiger(board: DragonTigerBoard, date: String?) async throws -> DragonTigerData
    func auctionBenchmark(date: String?) async throws -> [AuctionBenchmarkItem]
    func marketDumpLink(kind: MarketDumpKind) async throws -> MarketDumpLink
}

/// fuyao REST 实现。
struct FuyaoDataService: AShareDataProvider {
    var client = FuyaoClient()

    private static let pageSize = 200

    func tradingDays() async throws -> [TradingDay] {
        try await client.get("/api/a-share/calendar/trading-days", as: FuyaoList<TradingDay>.self).item
    }

    func searchTickers(_ query: String) async throws -> [TickerSearchItem] {
        try await client.get("/api/meta/tickers/search", query: ["q": query], as: FuyaoList<TickerSearchItem>.self).item
    }

    func snapshot(thscodes: [String]) async throws -> [PriceSnapshotItem] {
        guard !thscodes.isEmpty else { return [] }
        var result: [PriceSnapshotItem] = []
        // 一次别传太长的 query;100 个一批。
        for chunk in stride(from: 0, to: thscodes.count, by: 100) {
            let slice = Array(thscodes[chunk..<min(chunk + 100, thscodes.count)])
            let data = try await client.get(
                "/api/a-share/prices/snapshot",
                query: ["thscodes": slice.joined(separator: ",")],
                as: SnapshotData.self
            )
            result += data.item
        }
        return result
    }

    func fullMarketSnapshot() async throws -> [PriceSnapshotItem] {
        var items: [PriceSnapshotItem] = []
        var offset = 0
        let limit = 6000
        while true {
            let page = try await client.get(
                "/api/a-share/prices/snapshot",
                query: ["limit": String(limit), "offset": String(offset)],
                as: SnapshotData.self
            )
            items += page.item
            offset += page.item.count
            guard let total = page.total, offset < total, !page.item.isEmpty else { break }
        }
        return items
    }

    func historical(thscode: String, start: Date, end: Date, adjust: String) async throws -> [PriceBar] {
        try await client.get(
            "/api/a-share/prices/historical",
            query: [
                "thscode": thscode, "interval": "1d", "adjust": adjust,
                "start": String(ShanghaiDate.ms(start)), "end": String(ShanghaiDate.ms(end))
            ],
            as: FuyaoList<PriceBar>.self
        ).item.sorted { $0.date_ms < $1.date_ms }
    }

    func indexCatalog(tag: String) async throws -> [IndexCatalogItem] {
        try await client.get("/api/a-share-index/catalog/ths-index-list", query: ["tag": tag], as: FuyaoList<IndexCatalogItem>.self).item
    }

    func indexSnapshot(thscodes: [String]) async throws -> [PriceSnapshotItem] {
        guard !thscodes.isEmpty else { return [] }
        return try await client.get(
            "/api/a-share-index/prices/snapshot",
            query: ["thscodes": thscodes.joined(separator: ",")],
            as: SnapshotData.self
        ).item
    }

    func indexHistorical(thscode: String, start: Date, end: Date) async throws -> [PriceBar] {
        try await client.get(
            "/api/a-share-index/prices/historical",
            query: [
                "thscode": thscode, "interval": "1d",
                "start": String(ShanghaiDate.ms(start)), "end": String(ShanghaiDate.ms(end))
            ],
            as: FuyaoList<PriceBar>.self
        ).item.sorted { $0.date_ms < $1.date_ms }
    }

    func constituents(thscode: String) async throws -> [TickerSearchItem] {
        try await client.get("/api/a-share-index/constituents/ths-stock-list", query: ["thscode": thscode], as: FuyaoList<TickerSearchItem>.self).item
    }

    // MARK: 涨跌停

    private func allPages<Item: Decodable>(_ path: String, dateMs: Int64?, sort: String, as: Item.Type) async throws -> [Item] {
        var items: [Item] = []
        var page = 1
        while true {
            var query = ["page": String(page), "size": String(Self.pageSize), "sort_field": sort, "sort_dir": "desc"]
            if let dateMs { query["date_ms"] = String(dateMs) }
            let data = try await client.get(path, query: query, as: FuyaoPagedList<Item>.self)
            items += data.item
            let pages = data.pagination?.pages ?? 1
            guard page < pages, !data.item.isEmpty else { break }
            page += 1
        }
        return items
    }

    func limitUpPool(dateMs: Int64?) async throws -> [LimitUpItem] {
        try await allPages("/api/a-share/special-data/limit-up-pool", dateMs: dateMs, sort: "continue_day_cnt", as: LimitUpItem.self)
    }

    func limitDownPool(dateMs: Int64?) async throws -> [LimitDownItem] {
        try await allPages("/api/a-share/special-data/limit-down-pool", dateMs: dateMs, sort: "last_limit_time", as: LimitDownItem.self)
    }

    func limitBreakPool(dateMs: Int64?) async throws -> [LimitBreakItem] {
        try await allPages("/api/a-share/special-data/limit-break-pool", dateMs: dateMs, sort: "open_times", as: LimitBreakItem.self)
    }

    func limitUpLadder() async throws -> LadderData {
        try await client.get("/api/a-share/special-data/limit-up-ladder", as: LadderData.self)
    }

    // MARK: 热榜

    func hotStocks(period: HotListPeriod) async throws -> [HotStockItem] {
        try await client.get("/api/a-share/special-data/hot-stock-list", query: ["period": period.rawValue], as: FuyaoList<HotStockItem>.self).item
    }

    func skyrocketList(period: HotListPeriod) async throws -> [HotStockItem] {
        try await client.get("/api/a-share/special-data/skyrocket-list", query: ["period": period.rawValue], as: FuyaoList<HotStockItem>.self).item
    }

    func hotStockHistory(date: String) async throws -> [HotStockHistoryItem] {
        try await client.get("/api/a-share/special-data/hot-stock-list-history", query: ["date": date], as: FuyaoList<HotStockHistoryItem>.self).item
    }

    func hotRankTrend(thscode: String, start: String, end: String) async throws -> [HotRankPoint] {
        try await client.get(
            "/api/a-share/special-data/hot-stock-rank-trend",
            query: ["thscode": thscode, "start_date": start, "end_date": end],
            as: FuyaoList<HotRankPoint>.self
        ).item
    }

    func anomalies(tags: [String]) async throws -> [AnomalyItem] {
        var query: [String: String] = [:]
        if !tags.isEmpty { query["tag_codes"] = tags.joined(separator: ",") }
        return try await client.get("/api/a-share/special-data/anomaly-analysis-list", query: query, as: FuyaoList<AnomalyItem>.self).item
    }

    func anomalies(thscodes: [String]) async throws -> [AnomalyItem] {
        guard !thscodes.isEmpty else { return [] }
        return try await client.get(
            "/api/a-share/special-data/anomaly-analysis-stock",
            query: ["thscodes": thscodes.prefix(50).joined(separator: ",")],
            as: FuyaoList<AnomalyItem>.self
        ).item
    }

    // MARK: 龙虎榜 / 竞价 / 导出

    func dragonTiger(board: DragonTigerBoard, date: String?) async throws -> DragonTigerData {
        var query = ["board_type": board.rawValue]
        if let date { query["date"] = date }
        return try await client.get("/api/a-share/special-data/dragon-tiger-list", query: query, as: DragonTigerData.self)
    }

    func auctionBenchmark(date: String?) async throws -> [AuctionBenchmarkItem] {
        var query: [String: String] = [:]
        if let date { query["date"] = date }
        return try await client.get("/api/a-share/auction/short-term-benchmark", query: query, as: AuctionBenchmarkData.self).item ?? []
    }

    func marketDumpLink(kind: MarketDumpKind) async throws -> MarketDumpLink {
        try await client.get("/api/dump/market-dumps/\(kind.rawValue)/download-url", as: MarketDumpLink.self)
    }
}

/// 抓取时并发跑 N 个任务、保序返回;任一失败整体抛出。
enum ConcurrentFetch {
    static func map<Input: Sendable, Output: Sendable>(
        _ inputs: [Input],
        concurrency: Int = 6,
        progress: (@Sendable (Int, Int) -> Void)? = nil,
        _ transform: @escaping @Sendable (Input) async throws -> Output
    ) async throws -> [Output] {
        var results = [Output?](repeating: nil, count: inputs.count)
        var next = 0
        var done = 0
        try await withThrowingTaskGroup(of: (Int, Output).self) { group in
            func enqueue() {
                guard next < inputs.count else { return }
                let index = next
                let input = inputs[index]
                next += 1
                group.addTask { (index, try await transform(input)) }
            }
            for _ in 0..<min(concurrency, inputs.count) { enqueue() }
            while let (index, output) = try await group.next() {
                results[index] = output
                done += 1
                progress?(done, inputs.count)
                enqueue()
            }
        }
        return results.compactMap { $0 }
    }
}
