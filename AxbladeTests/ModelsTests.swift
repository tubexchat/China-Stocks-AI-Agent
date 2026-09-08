import XCTest
@testable import Axblade

final class ModelsTests: XCTestCase {
    func testChatMessageDefaultsToNonErrorWithGeneratedID() {
        let a = ChatMessage(role: .user, content: "你好")
        let b = ChatMessage(role: .user, content: "你好")

        XCTAssertEqual(a.role, .user)
        XCTAssertEqual(a.content, "你好")
        XCTAssertFalse(a.isError)
        XCTAssertNotEqual(a.id, b.id)
    }

    func testFreshConversationStartsEmptyWithDefaultTitle() {
        let conversation = Conversation.fresh()

        XCTAssertEqual(conversation.title, "新对话")
        XCTAssertTrue(conversation.messages.isEmpty)
    }

    func testTimestampsSnapToMillisecondsSoPersistenceIsLossless() {
        let raw = Date(timeIntervalSince1970: 1_786_000_000.002_349)
        let message = ChatMessage(role: .user, content: "x", createdAt: raw)

        XCTAssertEqual(message.createdAt, Date(timeIntervalSince1970: 1_786_000_000.002))
    }

    func testConversationRoundTripsThroughJSON() throws {
        var conversation = Conversation.fresh()
        conversation.messages = [
            ChatMessage(role: .user, content: "问题"),
            ChatMessage(role: .assistant, content: "回答", isError: true)
        ]

        let data = try JSONCoding.encoder().encode(conversation)
        let decoded = try JSONCoding.decoder().decode(Conversation.self, from: data)

        XCTAssertEqual(decoded, conversation)
    }

    func testUnknownModelAliasSnapsToDefaultOnDecode() throws {
        let json = #"{"modelAlias":"gpt-4o"}"#

        let settings = try JSONCoding.decoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.modelAlias, Backend.defaultModelAlias)
    }

    func testSelectedModelAliasRoundTripsThroughJSON() throws {
        var settings = AppSettings()
        settings.modelAlias = "kimi"

        let data = try JSONCoding.encoder().encode(settings)
        let decoded = try JSONCoding.decoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.modelAlias, "kimi")
    }

    func testSearchMatchesTitleAndMessageContentCaseInsensitively() {
        var swiftTalk = Conversation(title: "解释 Swift 的 actor")
        swiftTalk.messages = [ChatMessage(role: .user, content: "帮我讲讲 Sendable")]
        var shopping = Conversation(title: "周末装修采购清单")
        shopping.messages = [ChatMessage(role: .user, content: "帮我列个清单")]
        let list = [swiftTalk, shopping]

        XCTAssertEqual(list.filtered(by: "swift"), [swiftTalk])      // 命中标题,大小写不敏感
        XCTAssertEqual(list.filtered(by: "sendable"), [swiftTalk])   // 命中消息正文
        XCTAssertEqual(list.filtered(by: "清单"), [shopping])
        XCTAssertEqual(list.filtered(by: "帮我"), list)               // 两条都命中,保持原顺序
        XCTAssertEqual(list.filtered(by: "不存在的词"), [])
        XCTAssertEqual(list.filtered(by: "  "), list)                // 空白查询 = 不过滤
    }

    func testDefaultSettingsUseTheDefaultBackendModel() {
        let settings = AppSettings()

        XCTAssertEqual(settings.modelAlias, Backend.defaultModelAlias)
        XCTAssertTrue(settings.disabledSources.isEmpty)
        XCTAssertEqual(settings.language, .zh)
    }

    func testLanguageRoundTripsAndUnknownValueFallsBackToChinese() throws {
        var settings = AppSettings()
        settings.language = .en
        let data = try JSONCoding.encoder().encode(settings)
        XCTAssertEqual(try JSONCoding.decoder().decode(AppSettings.self, from: data).language, .en)

        let junk = #"{"language":"fr"}"#
        XCTAssertEqual(
            try JSONCoding.decoder().decode(AppSettings.self, from: Data(junk.utf8)).language,
            .zh
        )
        let missing = #"{}"#
        XCTAssertEqual(
            try JSONCoding.decoder().decode(AppSettings.self, from: Data(missing.utf8)).language,
            .zh
        )
    }
}
