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

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        createdAt: Date = Date(),
        isError: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt.snappedToMilliseconds
        self.isError = isError
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
/// 解码一律 `decodeIfPresent`:旧版本(多 provider 时代)落盘的 settings.json
/// 缺新字段、多老字段都不能整体解码失败——老字段直接忽略,野模型名落回默认。
struct AppSettings: Codable, Equatable, Sendable {
    /// 当前选择的后端模型别名,只会是 `Backend.models` 之一。
    var modelAlias: String
    /// 界面语言;解码遇到未知值落回中文。
    var language: AppLanguage
    /// 数据源默认全部启用,只记禁用集合——将来新增源对老用户自动可见。
    var disabledSources: Set<MarketSourceKind>

    private enum CodingKeys: String, CodingKey {
        case modelAlias, language, disabledSources
    }

    init(
        modelAlias: String = Backend.defaultModelAlias,
        language: AppLanguage = .zh,
        disabledSources: Set<MarketSourceKind> = []
    ) {
        self.modelAlias = modelAlias
        self.language = language
        self.disabledSources = disabledSources
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let alias = try container.decodeIfPresent(String.self, forKey: .modelAlias)
            ?? Backend.defaultModelAlias
        modelAlias = Backend.model(alias: alias).alias
        let rawLanguage = try container.decodeIfPresent(String.self, forKey: .language)
        language = rawLanguage.flatMap(AppLanguage.init(rawValue:)) ?? .zh
        disabledSources = try container.decodeIfPresent(Set<MarketSourceKind>.self, forKey: .disabledSources) ?? []
    }
}
