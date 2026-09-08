import Foundation

// 同花顺金融数据 API(fuyao.aicubes.cn)的响应形状。
// 字段名与 JSON 一一对应,保留 snake_case,免得为 CodingKeys 维护两份名字。
// 数值字段一律可选:上游偶发缺字段时单条降级,而不是整页解析失败。

/// 统一响应信封:HTTP 恒为 200,业务结果看 `code`。
struct FuyaoEnvelope<Payload: Decodable>: Decodable {
    var code: Int
    var message: String?
    var request_id: String?
    var data: Payload?
}

/// 最常见的 `data` 形状:时间戳 + 列表。
struct FuyaoList<Item: Decodable>: Decodable {
    var timestamp: Int64?
    var item: [Item]

    private enum CodingKeys: String, CodingKey { case timestamp, item }

    init(timestamp: Int64? = nil, item: [Item]) {
        self.timestamp = timestamp
        self.item = item
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decodeIfPresent(Int64.self, forKey: .timestamp)
        item = try container.decodeIfPresent([Item].self, forKey: .item) ?? []
    }
}

struct FuyaoPagination: Decodable, Equatable, Sendable {
    var total: Int?
    var pages: Int?
    var size: Int?
    var page: Int?
}

/// 带分页的列表(涨停 / 跌停 / 炸板池)。
struct FuyaoPagedList<Item: Decodable>: Decodable {
    var timestamp: Int64?
    var pagination: FuyaoPagination?
    var item: [Item]

    private enum CodingKeys: String, CodingKey { case timestamp, pagination, item }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decodeIfPresent(Int64.self, forKey: .timestamp)
        pagination = try container.decodeIfPresent(FuyaoPagination.self, forKey: .pagination)
        item = try container.decodeIfPresent([Item].self, forKey: .item) ?? []
    }
}

// MARK: - 基础与行情

struct TradingDay: Decodable, Equatable, Sendable {
    var date_ms: Int64
    /// `yyyyMMdd`
    var date: String
}

struct TickerSearchItem: Decodable, Equatable, Sendable, Identifiable {
    var thscode: String
    var ticker: String?
    var name: String?
    var exchange: String?
    var asset_type: String?
    var currency: String?

    var id: String { thscode }
}

struct IndexCatalogItem: Decodable, Equatable, Sendable, Identifiable, Encodable {
    var thscode: String
    var name: String

    var id: String { thscode }
}

struct PriceSnapshotItem: Codable, Equatable, Sendable, Identifiable {
    var thscode: String
    var ticker: String?
    var last_price: Double?
    var price_change: Double?
    var price_change_ratio_pct: Double?
    var open_price: Double?
    var high_price: Double?
    var low_price: Double?
    var prev_price: Double?
    var volume: Double?
    var turnover: Double?

    var id: String { thscode }
}

struct SnapshotData: Decodable {
    var timestamp: Int64?
    var total: Int?
    var item: [PriceSnapshotItem]

    private enum CodingKeys: String, CodingKey { case timestamp, total, item }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decodeIfPresent(Int64.self, forKey: .timestamp)
        total = try container.decodeIfPresent(Int.self, forKey: .total)
        item = try container.decodeIfPresent([PriceSnapshotItem].self, forKey: .item) ?? []
    }
}

/// 一根日 K。个股与指数共用。
struct PriceBar: Codable, Equatable, Sendable {
    var date_ms: Int64
    var open_price: Double?
    var high_price: Double?
    var low_price: Double?
    var close_price: Double?
    var volume: Double?
    var turnover: Double?

    var close: Double { close_price ?? 0 }
    var date: Date { Date(timeIntervalSince1970: Double(date_ms) / 1000) }
}

// MARK: - 涨跌停与炸板

struct LimitUpItem: Decodable, Equatable, Sendable, Identifiable {
    var thscode: String
    var ticker: String?
    var name: String
    var is_st: Bool?
    var is_new: Bool?
    var last_price: Double?
    var price_change_ratio_pct: Double?
    /// `HH:mm`
    var limit_up_time: String?
    var limit_up_reason: String?
    var continue_day_text: String?
    var continue_day_cnt: Int?
    var seal_money: Double?
    var max_seal_money: Double?

    var id: String { thscode }
    var boards: Int { max(continue_day_cnt ?? 1, 1) }

    /// 涨停原因按 `+` 拆成题材标签。
    var themes: [String] {
        (limit_up_reason ?? "")
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

struct LimitDownItem: Decodable, Equatable, Sendable, Identifiable {
    var thscode: String
    var ticker: String?
    var name: String
    var last_price: Double?
    var price_change_ratio_pct: Double?
    var first_limit_time: String?
    var last_limit_time: String?
    var turnover_ratio_pct: Double?

    var id: String { thscode }
}

struct LimitBreakItem: Decodable, Equatable, Sendable, Identifiable {
    var thscode: String
    var ticker: String?
    var name: String
    var last_price: Double?
    var price_change_ratio_pct: Double?
    var open_times: Int?
    var turnover_ratio_pct: Double?
    var turnover: Double?

    var id: String { thscode }
}

struct LadderStock: Decodable, Equatable, Sendable, Identifiable {
    var thscode: String
    var ticker: String?
    var name: String
    var board_num: Int
    /// 次日是否继续封板;最近一天没有参考,为 nil。
    var seal_nextday: Bool?
    var sign_level: Int?

    var id: String { thscode }
}

struct LadderBoards: Decodable, Equatable, Sendable {
    var two_board: [LadderStock] = []
    var three_board: [LadderStock] = []
    var four_board: [LadderStock] = []
    var five_board: [LadderStock] = []
    var six_board: [LadderStock] = []
    var seven_over: [LadderStock] = []

    private enum CodingKeys: String, CodingKey {
        case two_board, three_board, four_board, five_board, six_board, seven_over
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        two_board = try container.decodeIfPresent([LadderStock].self, forKey: .two_board) ?? []
        three_board = try container.decodeIfPresent([LadderStock].self, forKey: .three_board) ?? []
        four_board = try container.decodeIfPresent([LadderStock].self, forKey: .four_board) ?? []
        five_board = try container.decodeIfPresent([LadderStock].self, forKey: .five_board) ?? []
        six_board = try container.decodeIfPresent([LadderStock].self, forKey: .six_board) ?? []
        seven_over = try container.decodeIfPresent([LadderStock].self, forKey: .seven_over) ?? []
    }

    /// 按板位升序:2 板 → 7 板+。
    var tiers: [(boards: Int, stocks: [LadderStock])] {
        [(2, two_board), (3, three_board), (4, four_board), (5, five_board), (6, six_board), (7, seven_over)]
    }

    var all: [LadderStock] { tiers.flatMap(\.stocks) }
}

struct LadderDay: Decodable, Equatable, Sendable, Identifiable {
    /// 上游实际返回 `yyyy-MM-dd`(文档写的是 `yyyyMMdd`),两种都按原样保留。
    var date: String
    var boards: LadderBoards

    var id: String { date }
}

struct LadderWindow: Decodable, Equatable, Sendable {
    var length: Int?
    var date_list: [String]?
}

struct LadderData: Decodable, Equatable, Sendable {
    var timestamp: Int64?
    var window: LadderWindow?
    var item: [LadderDay]

    private enum CodingKeys: String, CodingKey { case timestamp, window, item }

    init(timestamp: Int64? = nil, window: LadderWindow? = nil, item: [LadderDay]) {
        self.timestamp = timestamp
        self.window = window
        self.item = item
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decodeIfPresent(Int64.self, forKey: .timestamp)
        window = try container.decodeIfPresent(LadderWindow.self, forKey: .window)
        item = try container.decodeIfPresent([LadderDay].self, forKey: .item) ?? []
    }
}

// MARK: - 热榜

struct HotStockItem: Decodable, Equatable, Sendable, Identifiable {
    var thscode: String
    var ticker: String?
    var name: String
    var rank: Int
    /// 上游原始字符串,可能是 "1941909" 或 "558171.0"。
    var heat: String?
    var rank_change: Int?
    /// `up` / `down` / `flat` / `unknown`
    var rank_trend: String?

    var id: String { thscode }
    var heatValue: Double { Double(heat ?? "") ?? 0 }
}

struct HotStockHistoryItem: Decodable, Equatable, Sendable, Identifiable {
    var thscode: String
    var ticker: String?
    var name: String
    var rank: Int

    var id: String { thscode }
}

struct HotRankPoint: Decodable, Equatable, Sendable, Identifiable {
    var thscode: String
    var ticker: String?
    var date: String
    var date_ms: Int64?
    var rank: Int

    var id: String { date }
}

struct AnomalyItem: Decodable, Equatable, Sendable, Identifiable {
    var stock_name: String
    var analysis_content: String
    var keyword_list: [String]
    var thscode: String
    var tag_name: String

    private enum CodingKeys: String, CodingKey {
        case stock_name, analysis_content, keyword_list, thscode, tag_name
    }

    init(stock_name: String, analysis_content: String, keyword_list: [String], thscode: String, tag_name: String) {
        self.stock_name = stock_name
        self.analysis_content = analysis_content
        self.keyword_list = keyword_list
        self.thscode = thscode
        self.tag_name = tag_name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stock_name = try container.decodeIfPresent(String.self, forKey: .stock_name) ?? ""
        analysis_content = try container.decodeIfPresent(String.self, forKey: .analysis_content) ?? ""
        keyword_list = try container.decodeIfPresent([String].self, forKey: .keyword_list) ?? []
        thscode = try container.decode(String.self, forKey: .thscode)
        tag_name = try container.decodeIfPresent(String.self, forKey: .tag_name) ?? ""
    }

    var id: String { thscode + "#" + tag_name }
}

// MARK: - 龙虎榜

struct DragonTigerConcept: Decodable, Equatable, Sendable, Hashable {
    var name: String
}

struct DragonTigerStock: Decodable, Equatable, Sendable, Identifiable {
    var thscode: String
    var ticker: String?
    var name: String
    var concept_list: [DragonTigerConcept]?
    /// 当日涨跌幅,小数(0.1 = +10%)。
    var change: Double?
    /// 龙虎榜净买入,元。
    var net_value: Double?
    var net_rate: Double?
    var hot_rank: Int?
    var buy_value: Double?
    var sell_value: Double?
    var limit_reason: String?
    /// 1 = 当日榜,3 = 3 日榜。
    var range_days: Int?
    var org_net_value: Double?
    var org_net_rate: Double?
    var org_buy_num: Int?
    var org_sell_num: Int?
    var amount: Double?
    var hot_money_net_value: Double?
    var hot_money_net_rate: Double?
    /// 游资榜里:该游资在该股上的净买入。
    var hot_money_item_net_value: Double?
    var hot_money_item_net_rate: Double?

    var id: String { "\(thscode)#\(range_days ?? 1)" }
    var concepts: [String] { (concept_list ?? []).map(\.name) }
}

struct HotMoneyGroup: Decodable, Equatable, Sendable, Identifiable {
    var name: String
    /// 聚合净买入,元。
    var buying: Double?
    var rows: [DragonTigerStock]

    private enum CodingKeys: String, CodingKey { case name, buying, rows }

    init(name: String, buying: Double?, rows: [DragonTigerStock]) {
        self.name = name
        self.buying = buying
        self.rows = rows
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        buying = try container.decodeIfPresent(Double.self, forKey: .buying)
        rows = try container.decodeIfPresent([DragonTigerStock].self, forKey: .rows) ?? []
    }

    var id: String { name }
}

enum DragonTigerBoard: String, CaseIterable, Sendable, Identifiable {
    case all, org, hot_money = "hot_money"
    var id: String { rawValue }
}

struct DragonTigerData: Decodable, Equatable, Sendable {
    var timestamp: Int64?
    var board_type: String?
    var trade_date: String?
    var count: Int?
    var stock_count: Int?
    var stock_items: [DragonTigerStock]
    var hot_money_items: [HotMoneyGroup]

    private enum CodingKeys: String, CodingKey {
        case timestamp, board_type, trade_date, count, stock_count, stock_items, hot_money_items
    }

    init(
        timestamp: Int64? = nil, board_type: String? = nil, trade_date: String? = nil,
        count: Int? = nil, stock_count: Int? = nil,
        stock_items: [DragonTigerStock] = [], hot_money_items: [HotMoneyGroup] = []
    ) {
        self.timestamp = timestamp
        self.board_type = board_type
        self.trade_date = trade_date
        self.count = count
        self.stock_count = stock_count
        self.stock_items = stock_items
        self.hot_money_items = hot_money_items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decodeIfPresent(Int64.self, forKey: .timestamp)
        board_type = try container.decodeIfPresent(String.self, forKey: .board_type)
        trade_date = try container.decodeIfPresent(String.self, forKey: .trade_date)
        count = try container.decodeIfPresent(Int.self, forKey: .count)
        stock_count = try container.decodeIfPresent(Int.self, forKey: .stock_count)
        stock_items = try container.decodeIfPresent([DragonTigerStock].self, forKey: .stock_items) ?? []
        hot_money_items = try container.decodeIfPresent([HotMoneyGroup].self, forKey: .hot_money_items) ?? []
    }
}

// MARK: - 集合竞价 / 数据导出

struct AuctionBenchmarkItem: Decodable, Equatable, Sendable, Identifiable {
    var thscode: String
    var ticker: String?
    var name: String
    var auction_pct: Double?
    var tags: [String]?

    var id: String { thscode }
}

struct AuctionBenchmarkData: Decodable {
    var timestamp: Int64?
    var date: String?
    var item: [AuctionBenchmarkItem]?
}

struct MarketDumpLink: Decodable, Equatable, Sendable {
    var presigned_url: String
    var presigned_url_expires_at: String?
    var expires_in_seconds: Int?
}
