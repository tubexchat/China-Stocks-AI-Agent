import Foundation

/// 五个盘面模块(声明顺序即侧栏 / 卡片展示顺序)。
enum AgentModule: String, CaseIterable, Identifiable, Sendable, Codable {
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

/// 全应用统一的数字格式。
enum NumberFormat {
    /// |v| ≥ 1 保留两位小数并去尾零;更小的值保留 4 位有效数字。
    static func number(_ value: Double) -> String {
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

    /// 带正负号的百分数,固定最多两位小数(0.509875 → +0.51%)。
    static func percent(_ value: Double) -> String {
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
}
