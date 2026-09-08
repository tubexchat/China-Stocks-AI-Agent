import XCTest
@testable import Axblade

/// 用 `URLProtocol` 顶掉真实网络,喂一段写死的 SSE 响应,
/// 这样能把「HTTP → 逐行解析 → 文本增量」整条链路跑通而不打真网。
final class MockSSEProtocol: URLProtocol, @unchecked Sendable {
    struct Script: Sendable {
        var status = 200
        var lines: [String] = []
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var script = Script()

    static func install(status: Int = 200, lines: [String]) {
        lock.lock(); defer { lock.unlock() }
        script = Script(status: status, lines: lines)
    }

    private static func currentScript() -> Script {
        lock.lock(); defer { lock.unlock() }
        return script
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockSSEProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let script = Self.currentScript()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: script.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for line in script.lines {
            client?.urlProtocol(self, didLoad: Data((line + "\n").utf8))
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class StreamingIntegrationTests: XCTestCase {
    private let prompt = [ChatMessage(role: .user, content: "hi")]

    private func collect(_ stream: AsyncThrowingStream<String, Error>) async throws -> [String] {
        var deltas: [String] = []
        for try await delta in stream { deltas.append(delta) }
        return deltas
    }

    func testOpenAIStreamYieldsEveryContentDelta() async throws {
        MockSSEProtocol.install(lines: [
            ": keep-alive",
            #"data: {"choices":[{"delta":{"role":"assistant"}}]}"#,
            #"data: {"choices":[{"delta":{"content":"你"}}]}"#,
            "",
            #"data: {"choices":[{"delta":{"content":"好"}}]}"#,
            "data: [DONE]"
        ])
        let service = OpenAIChatService(session: MockSSEProtocol.session())

        let deltas = try await collect(
            service.streamReply(messages: prompt, model: "deepseek")
        )

        XCTAssertEqual(deltas, ["你", "好"])
    }

    func testStreamStopsAtDoneSentinel() async throws {
        MockSSEProtocol.install(lines: [
            #"data: {"choices":[{"delta":{"content":"前"}}]}"#,
            "data: [DONE]",
            #"data: {"choices":[{"delta":{"content":"不该出现"}}]}"#
        ])
        let service = OpenAIChatService(session: MockSSEProtocol.session())

        let deltas = try await collect(
            service.streamReply(messages: prompt, model: "deepseek")
        )

        XCTAssertEqual(deltas, ["前"])
    }

    func testHTTPFailureCarriesStatusAndBody() async {
        MockSSEProtocol.install(status: 401, lines: [#"{"error":{"message":"invalid key"}}"#])
        let service = OpenAIChatService(session: MockSSEProtocol.session())

        do {
            _ = try await collect(
                service.streamReply(messages: prompt, model: "deepseek")
            )
            XCTFail("401 应该抛错")
        } catch let error as ChatServiceError {
            guard case .http(let status, let body) = error else { return XCTFail("错误类型不对:\(error)") }
            XCTAssertEqual(status, 401)
            XCTAssertTrue(body.contains("invalid key"), body)
        } catch {
            XCTFail("错误类型不对:\(error)")
        }
    }

    func testMidStreamErrorEventStopsTheStream() async {
        MockSSEProtocol.install(lines: [
            #"data: {"choices":[{"delta":{"content":"半"}}]}"#,
            #"data: {"type":"error","error":{"type":"overloaded_error","message":"服务繁忙"}}"#
        ])
        let service = OpenAIChatService(session: MockSSEProtocol.session())

        do {
            _ = try await collect(
                service.streamReply(messages: prompt, model: "deepseek")
            )
            XCTFail("流内错误应该抛错")
        } catch {
            XCTAssertEqual(error as? ChatServiceError, .stream("服务繁忙"))
        }
    }
}
