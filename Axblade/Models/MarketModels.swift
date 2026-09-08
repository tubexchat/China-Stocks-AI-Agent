import Foundation

/// 智能体的五个功能模块(声明顺序即侧栏 / 卡片展示顺序)。
enum AgentModule: String, CaseIterable, Identifiable, Sendable {
    case limitUpPulse, dragonTigerTopology, heatRadar, marketTrend, dragonTigerWatch

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .limitUpPulse: "waveform.path.ecg"
        case .dragonTigerTopology: "point.3.connected.trianglepath.dotted"
        case .heatRadar: "dot.radiowaves.left.and.right"
        case .marketTrend: "chart.xyaxis.line"
        case .dragonTigerWatch: "eye.trianglebadge.exclamationmark"
        }
    }
}

/// 个股研究里的本地量化工具(全部原生计算)。
enum QuantTool: String, CaseIterable, Identifiable, Sendable {
    case gbdt, risk, factor, backtest

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .gbdt: "point.3.filled.connected.trianglepath.dotted"
        case .risk: "shield.lefthalf.filled"
        case .factor: "magnifyingglass"
        case .backtest: "clock.arrow.circlepath"
        }
    }
}

/// 一次 A 股行情快照:附加进对话的数据单元。
struct MarketSnapshot: Equatable, Sendable, Identifiable {
    var symbol: String
    var name: String?
    var price: Double
    var changePercent: Double?
    var high: Double?
    var low: Double?
    var volume: Double?
    var turnover: Double?
    var currency: String? = "CNY"
    /// 最近 ≤30 根日线收盘,旧→新。
    var closes: [Double]
    var fetchedAt: Date
    /// 非行情附件(模块报告):有值时 promptText 直接用它。
    var reportText: String?

    var id: String { "\(symbol):\(fetchedAt.timeIntervalSince1970)" }

    init(
        symbol: String, name: String? = nil, price: Double, changePercent: Double? = nil,
        high: Double? = nil, low: Double? = nil, volume: Double? = nil, turnover: Double? = nil,
        currency: String? = "CNY", closes: [Double] = [], fetchedAt: Date = Date(), reportText: String? = nil
    ) {
        self.symbol = symbol
        self.name = name
        self.price = price
        self.changePercent = changePercent
        self.high = high
        self.low = low
        self.volume = volume
        self.turnover = turnover
        self.currency = currency
        self.closes = closes
        self.fetchedAt = fetchedAt
        self.reportText = reportText
    }

    init(from item: PriceSnapshotItem, name: String?, closes: [Double], fetchedAt: Date = Date()) {
        self.init(
            symbol: item.thscode, name: name, price: item.last_price ?? 0,
            changePercent: item.price_change_ratio_pct, high: item.high_price, low: item.low_price,
            volume: item.volume, turnover: item.turnover, currency: "CNY", closes: closes, fetchedAt: fetchedAt
        )
    }

    /// 输入卡上的 chip 文案,如 "贵州茅台 +2.31%"。
    var chipText: String {
        let title = name ?? symbol
        guard reportText == nil, let changePercent else { return title }
        return "\(title) \(Self.formatPercent(changePercent))"
    }

    /// 并入用户消息、发给模型的紧凑数据块(默认中文)。
    var promptText: String {
        promptText(in: .zh)
    }

    func promptText(in language: AppLanguage) -> String {
        if let reportText { return reportText }
        let title = name.map { "\(symbol)(\($0))" } ?? symbol
        let stamp = Self.stampFormatter.string(from: fetchedAt)

        var lines: [String]
        var facts: [String]
        switch language {
        case .zh:
            lines = ["【A股行情 · \(title) · \(stamp)】"]
            facts = ["现价 \(Self.formatNumber(price))\(currency.map { " \($0)" } ?? "")"]
            if let changePercent { facts.append("涨跌 \(Self.formatPercent(changePercent))") }
            if let high, let low { facts.append("高 \(Self.formatNumber(high)) / 低 \(Self.formatNumber(low))") }
            if let turnover { facts.append("成交额 \(MoneyFormat.yuan(turnover))") }
            else if let volume { facts.append("量 \(Self.formatNumber(volume))") }
            lines.append(facts.joined(separator: ";"))
            if !closes.isEmpty {
                let series = closes.map(Self.formatNumber).joined(separator: ", ")
                lines.append("近\(closes.count)日收盘(旧→新): \(series)")
            }
        case .en:
            lines = ["[A-share quote · \(title) · \(stamp)]"]
            facts = ["Price \(Self.formatNumber(price))\(currency.map { " \($0)" } ?? "")"]
            if let changePercent { facts.append("Change \(Self.formatPercent(changePercent))") }
            if let high, let low { facts.append("High \(Self.formatNumber(high)) / Low \(Self.formatNumber(low))") }
            if let turnover { facts.append("Turnover \(Self.formatNumber(turnover))") }
            else if let volume { facts.append("Volume \(Self.formatNumber(volume))") }
            lines.append(facts.joined(separator: "; "))
            if !closes.isEmpty {
                let series = closes.map(Self.formatNumber).joined(separator: ", ")
                lines.append("Last \(closes.count) daily closes (old → new): \(series)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// |v| ≥ 1 保留两位小数并去尾零;更小的值保留 4 位有效数字。
    static func formatNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        if abs(value) >= 1 {
            formatter.maximumFractionDigits = 2
        } else {
            formatter.maximumSignificantDigits = 4
        }
        return formatter.string(from: value as NSNumber) ?? String(value)
    }

    /// 百分数固定最多两位小数(0.509875 → 0.51%),不走有效数字规则。
    static func formatPercent(_ value: Double) -> String {
        let body = percentFormatter.string(from: abs(value) as NSNumber) ?? String(abs(value))
        return value < 0 ? "-\(body)%" : "+\(body)%"
    }

    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
