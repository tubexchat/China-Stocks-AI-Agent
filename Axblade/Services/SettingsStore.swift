import Foundation

/// 设置以 JSON 落盘。读失败一律降级为默认值,不让坏文件卡死启动。
final class SettingsStore: Sendable {
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

    private var settingsURL: URL { directory.appendingPathComponent("settings.json") }

    func loadSettings() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsURL) else { return AppSettings() }
        return (try? JSONDecoder().decode(AppSettings.self, from: data)) ?? AppSettings()
    }

    func saveSettings(_ settings: AppSettings) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: settingsURL, options: .atomic)
    }
}
