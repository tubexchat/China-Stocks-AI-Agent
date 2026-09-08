import Foundation

/// 一条消息的角色。
enum Role: String, Codable, Sendable {
    case system
    case user
    case assistant
}

/// 会话中的单条消息。
struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var role: Role
    var content: String
    var createdAt: Date
    var isError: Bool
    /// 智能体自动附带的实时数据块(发给模型,界面只显示摘要标签)。
    var context: String?
    /// 数据块的来源标签,如「600519.SH 贵州茅台」「涨停情绪」。
    var contextLabels: [String]

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        createdAt: Date = Date(),
        isError: Bool = false,
        context: String? = nil,
        contextLabels: [String] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt.snappedToMilliseconds
        self.isError = isError
        self.context = context
        self.contextLabels = contextLabels
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, content, createdAt, isError, context, contextLabels
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(Role.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        createdAt = try container.decode(Date.self, forKey: .createdAt).snappedToMilliseconds
        isError = try container.decodeIfPresent(Bool.self, forKey: .isError) ?? false
        context = try container.decodeIfPresent(String.self, forKey: .context)
        contextLabels = try container.decodeIfPresent([String].self, forKey: .contextLabels) ?? []
    }

    /// 发给模型的正文:用户文字在前,数据块在后。
    var outboundContent: String {
        guard let context, !context.isEmpty else { return content }
        return content.isEmpty ? context : content + "\n\n" + context
    }
}

/// 一次完整对话。
struct Conversation: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        messages: [ChatMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt.snappedToMilliseconds
        self.updatedAt = updatedAt.snappedToMilliseconds
    }

    static func fresh(title: String = "新对话") -> Conversation {
        Conversation(title: title)
    }
}

extension Array where Element == Conversation {
    /// 侧栏搜索:标题或任意消息正文命中即保留,大小写不敏感,空白查询不过滤。
    func filtered(by query: String) -> [Conversation] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return self }
        return filter { conversation in
            conversation.title.lowercased().contains(query)
                || conversation.messages.contains { $0.content.lowercased().contains(query) }
        }
    }
}

/// 应用级设置。
/// 解码一律 `decodeIfPresent`:老版本落盘的 settings.json
/// 缺新字段、多老字段都不能整体解码失败——老字段直接忽略,野值落回默认。
struct AppSettings: Codable, Equatable, Sendable {
    /// 当前选择的后端模型别名,只会是 `Backend.models` 之一。
    var modelAlias: String
    /// 界面语言;解码遇到未知值落回中文。
    var language: AppLanguage
    /// 发消息前是否自动附带实时数据(智能体模式)。
    var agentAutoContext: Bool
    /// 全市场趋势研究的板块口径:`industry` / `cn_concept`。
    var sectorTag: String
    /// 龙虎榜观察的回看交易日数。
    var watchDays: Int

    private enum CodingKeys: String, CodingKey {
        case modelAlias, language, agentAutoContext, sectorTag, watchDays
    }

    init(
        modelAlias: String = Backend.defaultModelAlias,
        language: AppLanguage = .zh,
        agentAutoContext: Bool = true,
        sectorTag: String = "industry",
        watchDays: Int = 5
    ) {
        self.modelAlias = modelAlias
        self.language = language
        self.agentAutoContext = agentAutoContext
        self.sectorTag = sectorTag
        self.watchDays = watchDays
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let alias = try container.decodeIfPresent(String.self, forKey: .modelAlias)
            ?? Backend.defaultModelAlias
        modelAlias = Backend.model(alias: alias).alias
        let rawLanguage = try container.decodeIfPresent(String.self, forKey: .language)
        language = rawLanguage.flatMap(AppLanguage.init(rawValue:)) ?? .zh
        agentAutoContext = try container.decodeIfPresent(Bool.self, forKey: .agentAutoContext) ?? true
        let tag = try container.decodeIfPresent(String.self, forKey: .sectorTag) ?? "industry"
        sectorTag = ["industry", "cn_concept"].contains(tag) ? tag : "industry"
        let days = try container.decodeIfPresent(Int.self, forKey: .watchDays) ?? 5
        watchDays = [1, 3, 5, 10].contains(days) ? days : 5
    }
}
