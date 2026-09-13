import Foundation

/// 应用级设置。
/// 解码一律 `decodeIfPresent`:老版本落盘的 settings.json 缺新字段、多老字段都不能整体解码失败——
/// 老字段直接忽略,野值落回默认。
struct AppSettings: Codable, Equatable, Sendable {
    /// 界面语言;解码遇到未知值落回中文。
    var language: AppLanguage
    /// 全市场趋势研究的板块口径:`industry` / `cn_concept`。
    var sectorTag: String
    /// 龙虎榜观察的回看交易日数。
    var watchDays: Int
    /// 上次打开的模块;启动时直接回到它。
    var lastModule: AgentModule?
    /// 现金流质量稽核台的观察池(thscode,最多 20 只)。
    var cashFlowPool: [String]

    static let sectorTags = ["industry", "cn_concept"]
    static let watchDayOptions = [1, 3, 5, 10]
    static let cashFlowPoolLimit = 20
    /// 默认观察池:12 只非金融大盘股(银行 / 券商没有「营业成本」「购建固定资产」等口径,不放进默认池)。
    static let defaultCashFlowPool = [
        "600519.SH", "000858.SZ", "300033.SZ", "000333.SZ", "600900.SH", "300750.SZ",
        "002415.SZ", "600276.SH", "000651.SZ", "601888.SH", "600809.SH", "002594.SZ"
    ]

    private enum CodingKeys: String, CodingKey {
        case language, sectorTag, watchDays, lastModule, cashFlowPool
    }

    init(
        language: AppLanguage = .zh, sectorTag: String = "industry", watchDays: Int = 5,
        lastModule: AgentModule? = nil, cashFlowPool: [String] = AppSettings.defaultCashFlowPool
    ) {
        self.language = language
        self.sectorTag = sectorTag
        self.watchDays = watchDays
        self.lastModule = lastModule
        self.cashFlowPool = Self.sanitizePool(cashFlowPool)
    }

    /// 归一化代码、去重、截到 20 只;空池落回默认池。
    static func sanitizePool(_ codes: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in codes {
            let code = AShareSymbol.normalize(raw)
            guard code.contains("."), code.count == 9, seen.insert(code).inserted else { continue }
            result.append(code)
            if result.count == cashFlowPoolLimit { break }
        }
        return result.isEmpty ? defaultCashFlowPool : result
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawLanguage = try container.decodeIfPresent(String.self, forKey: .language)
        language = rawLanguage.flatMap(AppLanguage.init(rawValue:)) ?? .zh
        let tag = try container.decodeIfPresent(String.self, forKey: .sectorTag) ?? "industry"
        sectorTag = Self.sectorTags.contains(tag) ? tag : "industry"
        let days = try container.decodeIfPresent(Int.self, forKey: .watchDays) ?? 5
        watchDays = Self.watchDayOptions.contains(days) ? days : 5
        lastModule = try container.decodeIfPresent(String.self, forKey: .lastModule).flatMap(AgentModule.init(rawValue:))
        cashFlowPool = Self.sanitizePool(try container.decodeIfPresent([String].self, forKey: .cashFlowPool) ?? Self.defaultCashFlowPool)
    }
}
