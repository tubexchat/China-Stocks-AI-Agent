import XCTest
@testable import Axblade

final class ConversationStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AxbladeTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testLoadingFromEmptyDirectoryReturnsNoConversations() {
        let store = ConversationStore(directory: directory)

        XCTAssertTrue(store.loadConversations().isEmpty)
    }

    func testLoadingFromEmptyDirectoryReturnsDefaultSettings() {
        let store = ConversationStore(directory: directory)

        XCTAssertEqual(store.loadSettings(), AppSettings())
    }

    func testConversationsRoundTripThroughDisk() throws {
        let store = ConversationStore(directory: directory)
        var conversation = Conversation.fresh()
        conversation.title = "关于 Swift"
        conversation.messages = [ChatMessage(role: .user, content: "并发怎么用?")]

        try store.saveConversations([conversation])

        XCTAssertEqual(ConversationStore(directory: directory).loadConversations(), [conversation])
    }

    func testSettingsRoundTripThroughDisk() throws {
        let store = ConversationStore(directory: directory)
        var settings = AppSettings()
        settings.modelAlias = "kimi"
        settings.agentAutoContext = false
        settings.watchDays = 3

        try store.saveSettings(settings)

        XCTAssertEqual(ConversationStore(directory: directory).loadSettings(), settings)
    }

    func testCorruptConversationsFileLoadsAsEmptyInsteadOfCrashing() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("conversations.json"))

        XCTAssertTrue(ConversationStore(directory: directory).loadConversations().isEmpty)
    }

    func testCorruptSettingsFileLoadsAsDefaultsInsteadOfCrashing() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{[".utf8).write(to: directory.appendingPathComponent("settings.json"))

        XCTAssertEqual(ConversationStore(directory: directory).loadSettings(), AppSettings())
    }

    func testAccountRoundTripsThroughDisk() throws {
        let store = ConversationStore(directory: directory)
        let account = UserAccount(email: "nick@example.com", displayName: "Nick", plan: "free")

        try store.saveAccount(account)

        XCTAssertEqual(ConversationStore(directory: directory).loadAccount(), account)
    }

    func testSavingNilAccountDeletesTheFile() throws {
        let store = ConversationStore(directory: directory)
        try store.saveAccount(UserAccount(email: "n@example.com", displayName: "N", plan: "free"))

        try store.saveAccount(nil)

        XCTAssertNil(ConversationStore(directory: directory).loadAccount())
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("account.json").path))
    }

    func testSavingCreatesMissingDirectory() throws {
        let nested = directory.appendingPathComponent("deep/inner", isDirectory: true)
        let store = ConversationStore(directory: nested)

        try store.saveConversations([Conversation.fresh()])

        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.appendingPathComponent("conversations.json").path))
    }
}
