import Foundation
@testable import Axblade

/// 从测试包里读 fuyao 真实响应夹具(2026-09-08 抓取)。
enum Fixtures {
    static func data(_ name: String) -> Data {
        let bundle = Bundle(for: FixtureAnchor.self)
        guard let url = bundle.url(forResource: name, withExtension: "json")
            ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        else { fatalError("缺少夹具 \(name).json") }
        return try! Data(contentsOf: url)
    }

    static func decode<T: Decodable>(_ name: String, as type: T.Type) -> T {
        try! FuyaoClient.unwrap(data(name), as: type)
    }

    static var limitUp: [LimitUpItem] { decode("limit-up-pool", as: FuyaoPagedList<LimitUpItem>.self).item }
    static var limitDown: [LimitDownItem] { decode("limit-down-pool", as: FuyaoPagedList<LimitDownItem>.self).item }
    static var limitBreak: [LimitBreakItem] { decode("limit-break-pool", as: FuyaoPagedList<LimitBreakItem>.self).item }
    static var ladder: LadderData { decode("limit-up-ladder", as: LadderData.self) }
    static var hot: [HotStockItem] { decode("hot-stock-list", as: FuyaoList<HotStockItem>.self).item }
    static var surge: [HotStockItem] { decode("skyrocket-list", as: FuyaoList<HotStockItem>.self).item }
    static var anomalies: [AnomalyItem] { decode("anomaly-list", as: FuyaoList<AnomalyItem>.self).item }
    static var dragonAll: DragonTigerData { decode("dragon-tiger-all", as: DragonTigerData.self) }
    static var dragonOrg: DragonTigerData { decode("dragon-tiger-org", as: DragonTigerData.self) }
    static var dragonHotMoney: DragonTigerData { decode("dragon-tiger-hot-money", as: DragonTigerData.self) }
    static var fullSnapshot: [PriceSnapshotItem] { decode("snapshot-full", as: SnapshotData.self).item }
    static var snapshot: [PriceSnapshotItem] { decode("snapshot", as: SnapshotData.self).item }
    static var industry: [IndexCatalogItem] { decode("index-catalog-industry", as: FuyaoList<IndexCatalogItem>.self).item }
    static var indexBars: [PriceBar] { decode("index-historical", as: FuyaoList<PriceBar>.self).item.sorted { $0.date_ms < $1.date_ms } }
    static var stockBars: [PriceBar] { decode("stock-historical", as: FuyaoList<PriceBar>.self).item.sorted { $0.date_ms < $1.date_ms } }
    static var tradingDays: [TradingDay] { decode("trading-days", as: FuyaoList<TradingDay>.self).item }
    static var search: [TickerSearchItem] { decode("ticker-search", as: FuyaoList<TickerSearchItem>.self).item }
    static var rankTrend: [HotRankPoint] { decode("hot-rank-trend", as: FuyaoList<HotRankPoint>.self).item }
    static var benchmark: [AuctionBenchmarkItem] { decode("auction-benchmark", as: AuctionBenchmarkData.self).item ?? [] }
    static var indexSnapshot: [PriceSnapshotItem] { decode("index-snapshot", as: SnapshotData.self).item }
}

private final class FixtureAnchor {}

/// 内存数据源:默认全部返回夹具;记录每个方法被调用的次数;可让某个方法抛错。
final class StubDataProvider: AShareDataProvider, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var calls: [String] = []
    var failing: Set<String> = []
    /// 为 true 时任何方法都返回空(模拟没打开过任何模块、也没有数据)。
    var empty = false

    init(empty: Bool = false) {
        self.empty = empty
    }

    func count(_ name: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return calls.filter { $0 == name }.count
    }

    private func record(_ name: String) throws {
        lock.lock(); calls.append(name); lock.unlock()
        if failing.contains(name) { throw FuyaoError.api(code: 5003, message: "stub failure") }
    }

    func tradingDays() async throws -> [TradingDay] { try record("tradingDays"); return empty ? [] : Fixtures.tradingDays }
    func searchTickers(_ query: String) async throws -> [TickerSearchItem] {
        try record("searchTickers")
        if empty { return [] }
        return query.contains("600519") || query.contains("茅台") ? Fixtures.search : []
    }
    func snapshot(thscodes: [String]) async throws -> [PriceSnapshotItem] {
        try record("snapshot")
        return empty ? [] : Fixtures.snapshot.filter { thscodes.contains($0.thscode) }
    }
    func fullMarketSnapshot() async throws -> [PriceSnapshotItem] { try record("fullMarketSnapshot"); return empty ? [] : Fixtures.fullSnapshot }
    func historical(thscode: String, start: Date, end: Date, adjust: String) async throws -> [PriceBar] { try record("historical"); return empty ? [] : Fixtures.stockBars }
    func indexCatalog(tag: String) async throws -> [IndexCatalogItem] { try record("indexCatalog"); return empty ? [] : Fixtures.industry }
    func indexSnapshot(thscodes: [String]) async throws -> [PriceSnapshotItem] { try record("indexSnapshot"); return empty ? [] : Fixtures.indexSnapshot }
    func indexHistorical(thscode: String, start: Date, end: Date) async throws -> [PriceBar] {
        try record("indexHistorical")
        return empty ? [] : Fixtures.indexBars.filter { $0.date >= start.addingTimeInterval(-86400) }
    }
    func constituents(thscode: String) async throws -> [TickerSearchItem] { try record("constituents"); return [] }
    func limitUpPool(dateMs: Int64?) async throws -> [LimitUpItem] { try record("limitUpPool"); return empty ? [] : Fixtures.limitUp }
    func limitDownPool(dateMs: Int64?) async throws -> [LimitDownItem] { try record("limitDownPool"); return empty ? [] : Fixtures.limitDown }
    func limitBreakPool(dateMs: Int64?) async throws -> [LimitBreakItem] { try record("limitBreakPool"); return empty ? [] : Fixtures.limitBreak }
    func limitUpLadder() async throws -> LadderData { try record("limitUpLadder"); return empty ? LadderData(item: []) : Fixtures.ladder }
    func hotStocks(period: HotListPeriod) async throws -> [HotStockItem] { try record("hotStocks"); return empty ? [] : Fixtures.hot }
    func skyrocketList(period: HotListPeriod) async throws -> [HotStockItem] { try record("skyrocketList"); return empty ? [] : Fixtures.surge }
    func hotStockHistory(date: String) async throws -> [HotStockHistoryItem] { try record("hotStockHistory"); return [] }
    func hotRankTrend(thscode: String, start: String, end: String) async throws -> [HotRankPoint] { try record("hotRankTrend"); return empty ? [] : Fixtures.rankTrend }
    func anomalies(tags: [String]) async throws -> [AnomalyItem] { try record("anomaliesList"); return empty ? [] : Fixtures.anomalies }
    func anomalies(thscodes: [String]) async throws -> [AnomalyItem] {
        try record("anomaliesStock")
        return empty ? [] : Fixtures.anomalies.filter { thscodes.contains($0.thscode) }
    }
    func dragonTiger(board: DragonTigerBoard, date: String?) async throws -> DragonTigerData {
        try record("dragonTiger")
        if empty { return DragonTigerData(trade_date: date) }
        var data: DragonTigerData
        switch board {
        case .all: data = Fixtures.dragonAll
        case .org: data = Fixtures.dragonOrg
        case .hot_money: data = Fixtures.dragonHotMoney
        }
        if let date { data.trade_date = date }
        return data
    }
    func auctionBenchmark(date: String?) async throws -> [AuctionBenchmarkItem] { try record("auctionBenchmark"); return empty ? [] : Fixtures.benchmark }
    func marketDumpLink(kind: MarketDumpKind) async throws -> MarketDumpLink {
        try record("marketDumpLink")
        return MarketDumpLink(presigned_url: "https://example.com/dump.parquet", presigned_url_expires_at: nil, expires_in_seconds: 300)
    }
}
