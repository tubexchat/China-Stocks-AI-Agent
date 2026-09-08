import Foundation

/// 智能体的「工具调用」层:发消息前按意图自动拉取 A 股实时数据,拼成上下文喂给模型。
/// 官方后端不透传 function calling,所以路由在客户端做,确定性、可测试。
struct AgentIntent: OptionSet, Sendable, Hashable {
    let rawValue: Int
    static let limitUp = AgentIntent(rawValue: 1 << 0)
    static let dragonTiger = AgentIntent(rawValue: 1 << 1)
    static let heat = AgentIntent(rawValue: 1 << 2)
    static let market = AgentIntent(rawValue: 1 << 3)
    static let auction = AgentIntent(rawValue: 1 << 4)
}

enum AgentIntentRouter {
    private static let rules: [(AgentIntent, [String])] = [
        (.limitUp, ["涨停", "连板", "炸板", "跌停", "情绪", "封板", "首板", "高度板", "龙头", "limit up", "limit-up", "sentiment"]),
        (.dragonTiger, ["龙虎榜", "游资", "机构", "席位", "章盟主", "养家", "净买入", "dragon", "tiger", "hot money"]),
        (.heat, ["热度", "人气", "飙升", "热榜", "热股", "异动", "关键词", "hot list", "popular", "surge", "anomal"]),
        (.market, ["大盘", "市场", "板块", "行业", "指数", "趋势", "宽度", "赚钱效应", "上证", "创业板", "沪深", "market", "sector", "index", "trend", "breadth"]),
        (.auction, ["竞价", "开盘", "风向标", "auction"])
    ]

    static func route(_ text: String) -> AgentIntent {
        let lowered = text.lowercased()
        var result: AgentIntent = []
        for (intent, keywords) in rules where keywords.contains(where: { lowered.contains($0.lowercased()) }) {
            result.insert(intent)
        }
        return result
    }

    /// 寒暄 / 泛指词,不当股票名去搜。
    private static let smallTalk: Set<String> = [
        "你好", "您好", "谢谢", "在吗", "继续", "好的", "不对", "为什么", "什么", "市场", "大盘", "机会", "再说一遍", "总结", "解释", "详细", "展开"
    ]

    /// 没有代码时,从短问句里猜一个可能的股票名(≤ 8 个汉字,去掉常见问句词)。
    /// 命中任何盘面意图的问句不猜名字——那是在问市场,不是在问某只股票。
    static func nameCandidate(in text: String) -> String? {
        guard route(text).isEmpty else { return nil }
        let stripped = text.replacingOccurrences(
            of: #"[?？,，。!！:：\s]|分析|看看|怎么样|怎么看|如何|一下|帮我|请|的|股票|走势|能不能|可以|买|卖|吗|今天|最近|行情"#,
            with: "", options: .regularExpression
        )
        let chinese = stripped.filter { $0.unicodeScalars.allSatisfy { $0.value >= 0x4E00 && $0.value <= 0x9FFF } }
        guard chinese.count >= 2, chinese.count <= 8, chinese == stripped, !smallTalk.contains(chinese) else { return nil }
        return chinese
    }
}

/// 拼好的上下文:每一项是一个数据块,连同来源说明。
struct AgentContext: Equatable, Sendable {
    var blocks: [String]
    var labels: [String]

    var isEmpty: Bool { blocks.isEmpty }
    var text: String { blocks.joined(separator: "\n\n") }
}

struct AgentContextBuilder: Sendable {
    var data: any AShareDataProvider
    /// 各模块已经算好的报告(打开过模块页就有),直接复用,不重复拉取。
    var cachedReports: @Sendable () async -> [AgentIntent: String] = { [:] }
    var now: @Sendable () -> Date = { Date() }

    /// 单只个股的数据块:快照 + 名称 + 近 30 日收盘 + 当日异动原因。
    func stockBlock(code: String, language: AppLanguage) async -> (String, String)? {
        let thscode = AShareSymbol.normalize(code)
        guard let snapshot = try? await data.snapshot(thscodes: [thscode]).first else { return nil }
        let name = (try? await data.searchTickers(thscode))?.first?.name
        let end = now()
        let bars = (try? await data.historical(thscode: thscode, start: end.addingTimeInterval(-60 * 86400), end: end, adjust: "forward")) ?? []
        var market = MarketSnapshot(from: snapshot, name: name, closes: bars.suffix(30).map(\.close), fetchedAt: end)
        market.symbol = thscode
        var block = market.promptText(in: language)
        if let anomaly = (try? await data.anomalies(thscodes: [thscode]))?.first {
            block += "\n异动标签:\(anomaly.tag_name);原因:\(anomaly.analysis_content.prefix(600))"
        }
        return (block, name.map { "\(thscode) \($0)" } ?? thscode)
    }

    func build(for text: String, language: AppLanguage) async -> AgentContext {
        var blocks: [String] = []
        var labels: [String] = []

        var codes = AShareSymbol.codes(in: text)
        if codes.isEmpty, let name = AgentIntentRouter.nameCandidate(in: text),
           let hit = (try? await data.searchTickers(name))?.first(where: { $0.asset_type == "a-share" || $0.asset_type == nil }) {
            codes = [hit.thscode]
        }
        for code in codes.prefix(3) {
            if let (block, label) = await stockBlock(code: code, language: language) {
                blocks.append(block)
                labels.append(label)
            }
        }

        let intents = AgentIntentRouter.route(text)
        let cached = await cachedReports()
        let order: [(AgentIntent, String)] = [
            (.limitUp, "涨停情绪"), (.dragonTiger, "龙虎榜"), (.heat, "热度雷达"), (.market, "全市场趋势"), (.auction, "竞价风向标")
        ]
        for (intent, label) in order where intents.contains(intent) {
            if let report = cached[intent] {
                blocks.append(report)
                labels.append(label)
                continue
            }
            if let block = await liveBlock(for: intent) {
                blocks.append(block)
                labels.append(label)
            }
        }
        return AgentContext(blocks: blocks, labels: labels)
    }

    /// 没打开过模块页时的轻量兜底:直接拉当日数据算一份摘要。
    private func liveBlock(for intent: AgentIntent) async -> String? {
        switch intent {
        case .limitUp:
            async let up = data.limitUpPool(dateMs: nil)
            async let down = data.limitDownPool(dateMs: nil)
            async let broken = data.limitBreakPool(dateMs: nil)
            async let ladder = data.limitUpLadder()
            guard let limitUp = try? await up else { return nil }
            let report = LimitUpPulseAnalyzer.run(
                date: ShanghaiDate.string(now()), limitUp: limitUp,
                limitDown: (try? await down) ?? [], limitBreak: (try? await broken) ?? [],
                ladder: try? await ladder
            )
            return report.promptText
        case .dragonTiger:
            guard let all = try? await data.dragonTiger(board: .all, date: nil),
                  let hot = try? await data.dragonTiger(board: .hot_money, date: nil) else { return nil }
            return FlowGraphBuilder.build(date: all.trade_date ?? "", all: all, hotMoney: hot).promptText
        case .heat:
            guard let hot = try? await data.hotStocks(period: .day) else { return nil }
            let surge = (try? await data.skyrocketList(period: .day)) ?? []
            let anomalies = (try? await data.anomalies(tags: [])) ?? []
            return HeatRadarAnalyzer.run(period: .day, hot: hot, surge: surge, anomalies: anomalies, fetchedAt: now()).promptText
        case .market:
            let codes = MarketTrendAnalyzer.majorIndices.map(\.0)
            guard let snapshot = try? await data.indexSnapshot(thscodes: codes) else { return nil }
            let names = Dictionary(uniqueKeysWithValues: MarketTrendAnalyzer.majorIndices)
            let lines = snapshot.map { item in
                "\(names[item.thscode] ?? item.thscode) \(MarketSnapshot.formatNumber(item.last_price ?? 0)) \(MarketSnapshot.formatPercent(item.price_change_ratio_pct ?? 0)) 成交\(MoneyFormat.yuan(item.turnover ?? 0))"
            }
            return "【主要指数实时 · \(ShanghaiDate.string(now()))】\n" + lines.joined(separator: ";")
        case .auction:
            guard let items = try? await data.auctionBenchmark(date: nil), !items.isEmpty else { return nil }
            let lines = items.map { "\($0.name) 竞价\(MarketSnapshot.formatPercent($0.auction_pct ?? 0)) \(($0.tags ?? []).joined(separator: "/"))" }
            return "【短线风向标竞价基准 · \(ShanghaiDate.string(now()))】\n" + lines.joined(separator: ";")
        default:
            return nil
        }
    }

    /// 模型的人设与规则。
    static func systemPrompt(language: AppLanguage) -> String {
        switch language {
        case .zh:
            """
            你是「A股智能体」,一名专注中国 A 股的盘面分析师与量化研究助手。
            规则:
            1. 用户消息里以【…】开头的数据块是客户端刚从同花顺金融数据接口拉取的实时/当日数据,回答必须以这些数据为依据,引用其中的具体数字;数据块没有的信息不要编造。
            2. 涨跌表述遵循 A 股习惯:红涨绿跌;金额用「亿 / 万」;涨跌幅带正负号。
            3. 先给结论,再给依据,最后给风险与需要跟踪的信号;用 Markdown 标题、列表、表格组织,简洁不啰嗦。
            4. 涉及个股或板块时给出「情绪 / 资金 / 趋势」三个维度的判断,并明确这只是研究参考,不构成投资建议。
            5. 中文回答。
            """
        case .en:
            """
            You are "A-Share Agent", a market analyst and quant research assistant focused on China A-shares.
            Rules:
            1. Blocks starting with 【…】 in the user's message are live/same-day data the client just pulled from the Tonghuashun (10jqka) financial data API; ground your answer in them and cite concrete numbers. Never invent data that is not in the blocks.
            2. Follow A-share conventions: red = up, green = down; amounts in 亿/万 CNY; signed percentages.
            3. Conclusion first, evidence second, then risks and signals to watch; use Markdown headings, lists and tables; be concise.
            4. For stocks or sectors, judge along three axes — sentiment, money flow, trend — and state clearly that this is research only, not investment advice.
            5. Answer in English unless the user writes Chinese.
            """
        }
    }
}
