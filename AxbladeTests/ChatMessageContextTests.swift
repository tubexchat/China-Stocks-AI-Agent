import XCTest
@testable import Axblade

/// 用户消息上的智能体数据块:落盘、回读、发给模型的拼接。
final class ChatMessageContextTests: XCTestCase {
    func testOutboundContentAppendsContextAfterText() {
        let message = ChatMessage(role: .user, content: "看看茅台", context: "【A股行情】现价 1309", contextLabels: ["600519.SH 贵州茅台"])
        XCTAssertEqual(message.outboundContent, "看看茅台\n\n【A股行情】现价 1309")
        XCTAssertEqual(ChatMessage(role: .user, content: "", context: "【块】").outboundContent, "【块】")
        XCTAssertEqual(ChatMessage(role: .user, content: "只有文字").outboundContent, "只有文字")
    }

    func testContextRoundTripsThroughJSON() throws {
        let message = ChatMessage(role: .user, content: "看看茅台", context: "【块】", contextLabels: ["a", "b"])
        let data = try JSONCoding.encoder().encode(message)
        let decoded = try JSONCoding.decoder().decode(ChatMessage.self, from: data)
        XCTAssertEqual(decoded, message)
    }

    func testLegacyMessageWithoutContextFieldsStillDecodes() throws {
        let legacy = Data("""
        {"id":"11111111-2222-3333-4444-555555555555","role":"assistant","content":"hi","createdAt":"2026-08-11T04:00:00.000Z","isError":false}
        """.utf8)
        let message = try JSONCoding.decoder().decode(ChatMessage.self, from: legacy)
        XCTAssertNil(message.context)
        XCTAssertTrue(message.contextLabels.isEmpty)
        XCTAssertEqual(message.outboundContent, "hi")
    }
}
