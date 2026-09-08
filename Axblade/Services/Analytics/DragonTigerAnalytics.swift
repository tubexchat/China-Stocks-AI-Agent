import Foundation

// MARK: - 资金流拓扑

/// 龙虎榜资金流拓扑:游资 / 机构 → 股票 → 概念 三层节点,边权为净买入金额(元)。
struct FlowGraph: Equatable, Sendable {
    enum NodeKind: String, Sendable { case player, stock, concept }

    struct Node: Equatable, Sendable, Identifiable {
        var id: String
        var kind: NodeKind
        var label: String
        /// 节点净流入(元):游资为其聚合净买入,股票为龙虎榜净买入,概念为成分股净买入之和。
        var net: Double
        /// 流经该节点的绝对金额,决定节点大小。
        var gross: Double
        /// 股票节点的附加信息。
        var change: Double?
        var reason: String?
    }

    struct Edge: Equatable, Sendable, Identifiable {
        var from: String
        var to: String
        /// 正 = 买入方向,负 = 卖出。
        var value: Double
        var id: String { from + "→" + to }
    }

    var date: String
    var nodes: [Node]
    var edges: [Edge]

    static let institutionID = "player:机构专用"

    func nodes(of kind: NodeKind) -> [Node] {
        nodes.filter { $0.kind == kind }.sorted { $0.gross > $1.gross }
    }

    func node(_ id: String) -> Node? { nodes.first { $0.id == id } }

    func neighbors(of id: String) -> Set<String> {
        var result = Set<String>()
        for edge in edges where edge.from == id || edge.to == id {
            result.insert(edge.from == id ? edge.to : edge.from)
        }
        return result
    }

    var promptText: String {
        let players = nodes(of: .player).prefix(12).map { "\($0.label) \(MoneyFormat.yuan($0.net))" }.joined(separator: ";")
        let stocks = nodes(of: .stock).prefix(15).map { "\($0.label) 净\(MoneyFormat.yuan($0.net))\($0.reason.map { "[\($0)]" } ?? "")" }.joined(separator: ";")
        let concepts = nodes(of: .concept).prefix(10).map { "\($0.label) \(MoneyFormat.yuan($0.net))" }.joined(separator: ";")
        let heaviest = edges.sorted { abs($0.value) > abs($1.value) }.prefix(12).compactMap { edge -> String? in
            guard let from = node(edge.from), let to = node(edge.to) else { return nil }
            return "\(from.label)→\(to.label) \(MoneyFormat.yuan(edge.value))"
        }.joined(separator: ";")
        return """
        【龙虎榜资金流拓扑 · \(date)】
        席位净买入(游资 / 机构):\(players)
        股票净买入:\(stocks)
        概念资金流:\(concepts)
        最大资金边:\(heaviest)
        """
    }
}

enum FlowGraphBuilder {
    /// `all` 榜给股票层与机构边,`hot_money` 榜给游资边;概念取每只股票前 3 个。
    static func build(date: String, all: DragonTigerData, hotMoney: DragonTigerData, maxConcepts: Int = 14) -> FlowGraph {
        var nodes: [String: FlowGraph.Node] = [:]
        var edges: [String: FlowGraph.Edge] = [:]

        func addEdge(_ from: String, _ to: String, _ value: Double) {
            guard value != 0 else { return }
            let key = from + "→" + to
            if var existing = edges[key] {
                existing.value += value
                edges[key] = existing
            } else {
                edges[key] = FlowGraph.Edge(from: from, to: to, value: value)
            }
        }

        // 股票层:同一股票当日榜 + 3 日榜并存时只留当日榜。
        var stocks: [String: DragonTigerStock] = [:]
        for stock in all.stock_items {
            if let existing = stocks[stock.thscode], (existing.range_days ?? 1) <= (stock.range_days ?? 1) { continue }
            stocks[stock.thscode] = stock
        }
        for (_, stock) in stocks {
            let id = "stock:" + stock.thscode
            let net = stock.net_value ?? 0
            nodes[id] = FlowGraph.Node(
                id: id, kind: .stock, label: stock.name, net: net,
                gross: (stock.buy_value ?? 0) + (stock.sell_value ?? 0),
                change: stock.change, reason: stock.limit_reason
            )
            if let org = stock.org_net_value, org != 0 {
                addEdge(FlowGraph.institutionID, id, org)
            }
        }

        // 游资层
        for group in hotMoney.hot_money_items {
            let playerID = "player:" + group.name
            for row in group.rows {
                let stockID = "stock:" + row.thscode
                if nodes[stockID] == nil {
                    nodes[stockID] = FlowGraph.Node(
                        id: stockID, kind: .stock, label: row.name, net: row.net_value ?? 0,
                        gross: (row.buy_value ?? 0) + (row.sell_value ?? 0),
                        change: row.change, reason: row.limit_reason
                    )
                    if let org = row.org_net_value, org != 0 { addEdge(FlowGraph.institutionID, stockID, org) }
                }
                addEdge(playerID, stockID, row.hot_money_item_net_value ?? 0)
            }
        }

        // 席位节点的净额 = 其边之和
        var playerNet: [String: (net: Double, gross: Double)] = [:]
        for edge in edges.values where edge.from.hasPrefix("player:") {
            var entry = playerNet[edge.from] ?? (0, 0)
            entry.net += edge.value
            entry.gross += abs(edge.value)
            playerNet[edge.from] = entry
        }
        for (id, entry) in playerNet {
            nodes[id] = FlowGraph.Node(id: id, kind: .player, label: String(id.dropFirst("player:".count)), net: entry.net, gross: entry.gross)
        }

        // 概念层:股票净买入按概念汇总,取覆盖股票最多 / 金额最大的前 N 个
        var conceptStocks: [String: [DragonTigerStock]] = [:]
        for stock in stocks.values {
            for concept in stock.concepts.prefix(3) { conceptStocks[concept, default: []].append(stock) }
        }
        for row in hotMoney.hot_money_items.flatMap(\.rows) where stocks[row.thscode] == nil {
            for concept in row.concepts.prefix(3) { conceptStocks[concept, default: []].append(row) }
        }
        let ranked = conceptStocks
            .map { (name: $0.key, stocks: $0.value, gross: $0.value.reduce(0) { $0 + abs($1.net_value ?? 0) }) }
            .filter { $0.stocks.count >= 2 }
            .sorted { ($0.stocks.count, $0.gross) > ($1.stocks.count, $1.gross) }
            .prefix(maxConcepts)
        for concept in ranked {
            let id = "concept:" + concept.name
            let net = concept.stocks.reduce(0) { $0 + ($1.net_value ?? 0) }
            nodes[id] = FlowGraph.Node(id: id, kind: .concept, label: concept.name, net: net, gross: concept.gross)
            for stock in concept.stocks { addEdge("stock:" + stock.thscode, id, stock.net_value ?? 0) }
        }

        return FlowGraph(
            date: date,
            nodes: nodes.values.sorted { $0.gross > $1.gross },
            edges: edges.values.sorted { abs($0.value) > abs($1.value) }
        )
    }
}

// MARK: - 机构与游资观察(多日聚合)

struct DragonTigerWatchReport: Equatable, Sendable {
    struct StockRecord: Equatable, Sendable, Identifiable {
        var thscode: String
        var name: String
        var days: [String]
        var netTotal: Double
        var orgNetTotal: Double
        var hotMoneyNetTotal: Double
        var orgBuyCount: Int
        var orgSellCount: Int
        var latestChange: Double?
        var reason: String?
        var concepts: [String]
        var players: [String]
        var id: String { thscode }
        var appearances: Int { days.count }
    }

    struct PlayerRecord: Equatable, Sendable, Identifiable {
        var name: String
        var netTotal: Double
        var buyTotal: Double
        var sellTotal: Double
        var appearances: Int
        var days: [String]
        var stocks: [String]
        var conceptCounts: [(String, Int)]
        var id: String { name }

        static func == (lhs: PlayerRecord, rhs: PlayerRecord) -> Bool {
            lhs.name == rhs.name && lhs.netTotal == rhs.netTotal && lhs.appearances == rhs.appearances
        }
    }

    struct DailyRow: Equatable, Sendable, Identifiable {
        var date: String
        var player: String
        var thscode: String
        var stock: String
        var net: Double
        var change: Double?
        var id: String { date + player + thscode }
    }

    var dates: [String]
    var stocks: [StockRecord]
    var players: [PlayerRecord]
    var rows: [DailyRow]
    var orgNetTotal: Double
    var hotMoneyNetTotal: Double

    var orgBuys: [StockRecord] { stocks.filter { $0.orgNetTotal > 0 }.sorted { $0.orgNetTotal > $1.orgNetTotal } }
    var orgSells: [StockRecord] { stocks.filter { $0.orgNetTotal < 0 }.sorted { $0.orgNetTotal < $1.orgNetTotal } }
    var repeated: [StockRecord] { stocks.filter { $0.appearances >= 2 }.sorted { ($0.appearances, $0.netTotal) > ($1.appearances, $1.netTotal) } }

    var promptText: String {
        let range = dates.isEmpty ? "—" : "\(dates.first!) ~ \(dates.last!)"
        let buys = orgBuys.prefix(10).map { "\($0.name) \(MoneyFormat.yuan($0.orgNetTotal))(\($0.orgBuyCount)买/\($0.orgSellCount)卖,上榜\($0.appearances)次)" }.joined(separator: ";")
        let sells = orgSells.prefix(8).map { "\($0.name) \(MoneyFormat.yuan($0.orgNetTotal))" }.joined(separator: ";")
        let active = players.prefix(12).map { "\($0.name) 净\(MoneyFormat.yuan($0.netTotal)) 出手\($0.appearances)次 偏好\($0.conceptCounts.prefix(2).map(\.0).joined(separator: "/"))" }.joined(separator: ";")
        let repeats = repeated.prefix(8).map { "\($0.name) \($0.appearances)次 净\(MoneyFormat.yuan($0.netTotal))" }.joined(separator: ";")
        return """
        【龙虎榜机构与游资观察 · \(range) · \(dates.count) 个交易日】
        机构合计净买入 \(MoneyFormat.yuan(orgNetTotal));游资合计净买入 \(MoneyFormat.yuan(hotMoneyNetTotal))
        机构净买入前列:\(buys)
        机构净卖出前列:\(sells)
        活跃游资:\(active)
        反复上榜:\(repeats)
        """
    }
}

enum DragonTigerWatchAnalyzer {
    /// `days` 按日期升序,每天带 all 榜 + 游资榜。
    static func run(days: [(date: String, all: DragonTigerData, hotMoney: DragonTigerData)]) -> DragonTigerWatchReport {
        var stocks: [String: DragonTigerWatchReport.StockRecord] = [:]
        var players: [String: (net: Double, buy: Double, sell: Double, days: Set<String>, stocks: Set<String>, concepts: [String: Int], appearances: Int)] = [:]
        var rows: [DragonTigerWatchReport.DailyRow] = []
        var orgTotal = 0.0
        var hotMoneyTotal = 0.0

        for day in days {
            var seen = Set<String>()
            for stock in day.all.stock_items where (stock.range_days ?? 1) == 1 || !day.all.stock_items.contains(where: { $0.thscode == stock.thscode && ($0.range_days ?? 1) == 1 }) {
                guard seen.insert(stock.thscode).inserted else { continue }
                var record = stocks[stock.thscode] ?? .init(
                    thscode: stock.thscode, name: stock.name, days: [], netTotal: 0, orgNetTotal: 0,
                    hotMoneyNetTotal: 0, orgBuyCount: 0, orgSellCount: 0, latestChange: nil,
                    reason: nil, concepts: stock.concepts, players: []
                )
                record.days.append(day.date)
                record.netTotal += stock.net_value ?? 0
                record.orgNetTotal += stock.org_net_value ?? 0
                record.hotMoneyNetTotal += stock.hot_money_net_value ?? 0
                record.orgBuyCount += stock.org_buy_num ?? 0
                record.orgSellCount += stock.org_sell_num ?? 0
                record.latestChange = stock.change ?? record.latestChange
                record.reason = stock.limit_reason ?? record.reason
                stocks[stock.thscode] = record
                orgTotal += stock.org_net_value ?? 0
            }
            for group in day.hotMoney.hot_money_items {
                var entry = players[group.name] ?? (0, 0, 0, [], [], [:], 0)
                entry.days.insert(day.date)
                for row in group.rows {
                    let net = row.hot_money_item_net_value ?? 0
                    entry.net += net
                    if net >= 0 { entry.buy += net } else { entry.sell += -net }
                    entry.stocks.insert(row.name)
                    entry.appearances += 1
                    for concept in row.concepts.prefix(3) { entry.concepts[concept, default: 0] += 1 }
                    hotMoneyTotal += net
                    rows.append(.init(date: day.date, player: group.name, thscode: row.thscode, stock: row.name, net: net, change: row.change))
                    if var record = stocks[row.thscode] {
                        if !record.players.contains(group.name) { record.players.append(group.name) }
                        stocks[row.thscode] = record
                    }
                }
                players[group.name] = entry
            }
        }

        let playerRecords = players.map { name, entry in
            DragonTigerWatchReport.PlayerRecord(
                name: name, netTotal: entry.net, buyTotal: entry.buy, sellTotal: entry.sell,
                appearances: entry.appearances, days: entry.days.sorted(), stocks: entry.stocks.sorted(),
                conceptCounts: entry.concepts.sorted { ($0.value, $0.key) > ($1.value, $1.key) }.map { ($0.key, $0.value) }
            )
        }
        .sorted { ($0.appearances, abs($0.netTotal)) > ($1.appearances, abs($1.netTotal)) }

        return DragonTigerWatchReport(
            dates: days.map(\.date),
            stocks: stocks.values.sorted { abs($0.netTotal) > abs($1.netTotal) },
            players: playerRecords,
            rows: rows.sorted { ($0.date, abs($0.net)) > ($1.date, abs($1.net)) },
            orgNetTotal: orgTotal,
            hotMoneyNetTotal: hotMoneyTotal
        )
    }
}
