import Foundation

/// 金融数据源。前三个是加密交易所(公共 REST),后四个是股票市场(统一走 Yahoo Finance)。
enum MarketSourceKind: String, Codable, CaseIterable, Sendable, Identifiable {
    var id: String { rawValue }

    case binance, okx, mexc
    case usStock, krStock, hkStock, aShare

    var displayName: String {
        switch self {
        case .binance: "Binance"
        case .okx: "OKX"
        case .mexc: "抹茶 MEXC"
        case .usStock: "美股"
        case .krStock: "韩股"
        case .hkStock: "港股"
        case .aShare: "A股"
        }
    }

    var isCrypto: Bool {
        switch self {
        case .binance, .okx, .mexc: true
        default: false
        }
    }
}

/// 量化工具(声明顺序即侧栏/卡片展示顺序)。
enum QuantTool: String, CaseIterable, Identifiable, Sendable {
    case gbdt, risk, factor, backtest

    var id: String { rawValue }

    var name: String {
        switch self {
        case .gbdt: "梯度提升树模型"
        case .risk: "风控模型"
        case .factor: "因子挖掘"
        case .backtest: "历史回测"
        }
    }

    var subtitle: String {
        switch self {
        case .gbdt: "原生 GBDT 预测次日涨跌,给出验证集命中率与特征重要性"
        case .risk: "历史 VaR、最大回撤、年化波动率、夏普比率"
        case .factor: "9 个价格类因子的 IC 检验与多空分层,按预测力排序"
        case .backtest: "双均线交叉策略 vs 买入持有,净值曲线与胜率"
        }
    }

    var icon: String {
        switch self {
        case .gbdt: "point.3.filled.connected.trianglepath.dotted"
        case .risk: "shield.lefthalf.filled"
        case .factor: "magnifyingglass"
        case .backtest: "clock.arrow.circlepath"
        }
    }
}

/// 一次行情快照:附加进对话的数据单元。
struct MarketSnapshot: Equatable, Sendable, Identifiable {
    var source: MarketSourceKind
    var symbol: String
    var name: String?
    var price: Double
    var changePercent: Double?
    var high: Double?
    var low: Double?
    var volume: Double?
    var currency: String?
    /// 最近 ≤30 根日线收盘,旧→新。
    var closes: [Double]
    var fetchedAt: Date

    var id: String { "\(source.rawValue):\(symbol):\(fetchedAt.timeIntervalSince1970)" }

    /// 输入卡上的 chip 文案,如 "BTCUSDT +2.31%"。
    var chipText: String {
        guard let changePercent else { return symbol }
        return "\(symbol) \(Self.formatPercent(changePercent))"
    }

    /// 并入用户消息、发给模型的紧凑数据块(默认中文,老调用不受影响)。
    var promptText: String {
        promptText(in: .zh)
    }

    /// 按当前界面语言生成数据块;标签随语言,数值格式不变。
    func promptText(in language: AppLanguage) -> String {
        let text = language.strings
        let title = name.map { "\(symbol)(\($0))" } ?? symbol
        let stamp = Self.stampFormatter.string(from: fetchedAt)
        let sourceName = text.sourceName(source)

        var lines: [String]
        var facts: [String]
        switch language {
        case .zh:
            lines = ["【行情数据 · \(sourceName) · \(title) · \(stamp)】"]
            facts = ["现价 \(Self.formatNumber(price))\(currency.map { " \($0)" } ?? "")"]
            if let changePercent { facts.append("24h 涨跌 \(Self.formatPercent(changePercent))") }
            if let high, let low { facts.append("高 \(Self.formatNumber(high)) / 低 \(Self.formatNumber(low))") }
            if let volume { facts.append("量 \(Self.formatNumber(volume))") }
            lines.append(facts.joined(separator: ";"))
            if !closes.isEmpty {
                let series = closes.map(Self.formatNumber).joined(separator: ", ")
                lines.append("近\(closes.count)日收盘(旧→新): \(series)")
            }
        case .en:
            lines = ["[Market data · \(sourceName) · \(title) · \(stamp)]"]
            facts = ["Price \(Self.formatNumber(price))\(currency.map { " \($0)" } ?? "")"]
            if let changePercent { facts.append("24h change \(Self.formatPercent(changePercent))") }
            if let high, let low { facts.append("High \(Self.formatNumber(high)) / Low \(Self.formatNumber(low))") }
            if let volume { facts.append("Volume \(Self.formatNumber(volume))") }
            lines.append(facts.joined(separator: "; "))
            if !closes.isEmpty {
                let series = closes.map(Self.formatNumber).joined(separator: ", ")
                lines.append("Last \(closes.count) daily closes (old → new): \(series)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// |v| ≥ 1 保留两位小数并去尾零;更小的值保留 4 位有效数字(加密小币价格)。
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

    static func formatPercent(_ value: Double) -> String {
        let body = formatNumber(abs(value))
        return value < 0 ? "-\(body)%" : "+\(body)%"
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
