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

    static let sectorTags = ["industry", "cn_concept"]
    static let watchDayOptions = [1, 3, 5, 10]

    private enum CodingKeys: String, CodingKey {
        case language, sectorTag, watchDays, lastModule
    }

    init(language: AppLanguage = .zh, sectorTag: String = "industry", watchDays: Int = 5, lastModule: AgentModule? = nil) {
        self.language = language
        self.sectorTag = sectorTag
        self.watchDays = watchDays
        self.lastModule = lastModule
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
    }
}
