import XCTest
@testable import Axblade

final class SSEParserTests: XCTestCase {
    func testDataLineYieldsEvent() {
        var parser = SSEParser()

        XCTAssertEqual(parser.consume(line: "data: hello"), .data("hello"))
    }

    func testDoneSentinel() {
        var parser = SSEParser()

        XCTAssertEqual(parser.consume(line: "data: [DONE]"), .done)
    }

    func testIgnoresCommentsAndBlankAndEventLines() {
        var parser = SSEParser()

        XCTAssertNil(parser.consume(line: ""))
        XCTAssertNil(parser.consume(line: ": keep-alive"))
        XCTAssertNil(parser.consume(line: "event: message_start"))
        XCTAssertNil(parser.consume(line: "id: 42"))
    }

    func testDataLineWithoutSpaceAfterColonStillParses() {
        var parser = SSEParser()

        XCTAssertEqual(parser.consume(line: "data:{\"a\":1}"), .data("{\"a\":1}"))
    }

    func testTrailingCarriageReturnIsStripped() {
        var parser = SSEParser()

        XCTAssertEqual(parser.consume(line: "data: hello\r"), .data("hello"))
    }

    func testOpenAIDeltaExtraction() {
        let json = #"{"choices":[{"delta":{"content":"你好"}}]}"#

        XCTAssertEqual(SSEParser.openAIDelta(fromDataPayload: json), "你好")
        XCTAssertNil(SSEParser.openAIDelta(fromDataPayload: #"{"choices":[{"delta":{}}]}"#))
        XCTAssertNil(SSEParser.openAIDelta(fromDataPayload: "not json"))
    }

    func testTypedErrorEventSurfacesMessage() {
        let json = #"{"type":"error","error":{"type":"overloaded_error","message":"服务繁忙"}}"#

        XCTAssertEqual(SSEParser.streamErrorMessage(fromDataPayload: json), "服务繁忙")
        XCTAssertNil(SSEParser.streamErrorMessage(fromDataPayload: #"{"type":"message_stop"}"#))
    }

    func testOpenAIErrorPayloadSurfacesMessage() {
        let json = #"{"error":{"message":"额度不足","type":"insufficient_quota"}}"#

        XCTAssertEqual(SSEParser.streamErrorMessage(fromDataPayload: json), "额度不足")
    }
}
