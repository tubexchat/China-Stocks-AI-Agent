import Foundation

/// 把会话与设置以 JSON 落盘。读失败一律降级为默认值,不让坏文件卡死启动。
final class ConversationStore: Sendable {
    private let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    /// 默认位置:~/Library/Application Support/Axblade/
    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Axblade", isDirectory: true)
    }

    private var conversationsURL: URL { directory.appendingPathComponent("conversations.json") }
    private var settingsURL: URL { directory.appendingPathComponent("settings.json") }
    private var accountURL: URL { directory.appendingPathComponent("account.json") }

    func loadConversations() -> [Conversation] {
        decode([Conversation].self, from: conversationsURL) ?? []
    }

    func saveConversations(_ conversations: [Conversation]) throws {
        try write(conversations, to: conversationsURL)
    }

    func loadSettings() -> AppSettings {
        decode(AppSettings.self, from: settingsURL) ?? AppSettings()
    }

    func saveSettings(_ settings: AppSettings) throws {
        try write(settings, to: settingsURL)
    }

    func loadAccount() -> UserAccount? {
        decode(UserAccount.self, from: accountURL)
    }

    /// 传 nil 即登出:直接删文件。
    func saveAccount(_ account: UserAccount?) throws {
        guard let account else {
            try? FileManager.default.removeItem(at: accountURL)
            return
        }
        try write(account, to: accountURL)
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONCoding.decoder().decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONCoding.encoder().encode(value).write(to: url, options: .atomic)
    }
}
