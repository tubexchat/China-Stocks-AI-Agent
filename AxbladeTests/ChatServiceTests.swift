import XCTest
@testable import Axblade

final class BackendTests: XCTestCase {
    func testOnlyTwoFixedModelsWithFullModelNames() {
        XCTAssertEqual(Backend.models.map(\.alias), ["deepseek", "kimi"])
        XCTAssertEqual(
            Backend.models.map(\.displayName),
            ["DeepSeek-V4-Flash-0731", "Kimi-K2.7-Code"]
        )
    }

    func testKnownAliasResolvesAndUnknownFallsBackToDefault() {
        XCTAssertEqual(Backend.model(alias: "kimi").displayName, "Kimi-K2.7-Code")
        XCTAssertEqual(Backend.model(alias: "gpt-4o").alias, Backend.defaultModelAlias)
        XCTAssertEqual(Backend.model(alias: "").alias, Backend.defaultModelAlias)
    }

    func testBaseURLIsTheOfficialBackendOverHTTPS() {
        XCTAssertEqual(Backend.baseURL, "https://api.chillskill.xyz/v1")
        XCTAssertTrue(Backend.baseURL.hasPrefix("https://"))
    }
}

final class OpenAIChatServiceTests: XCTestCase {
    private func body(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testRequestTargetsBackendChatCompletionsEndpoint() throws {
        let request = try OpenAIChatService.buildRequest(
            messages: [ChatMessage(role: .user, content: "hi")],
            model: "deepseek"
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.chillskill.xyz/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
    }

    /// 客户端不再内置任何令牌:未登录时干脆不带 Authorization 头。
    func testRequestCarriesNoBuiltInTokenWhenSignedOut() throws {
        let request = try OpenAIChatService.buildRequest(
            messages: [ChatMessage(role: .user, content: "hi")],
            model: "deepseek",
            token: nil
        )

        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testBodyRequestsStreamingWithFullMessageHistory() throws {
        let request = try OpenAIChatService.buildRequest(
            messages: [
                ChatMessage(role: .system, content: "你是助手"),
                ChatMessage(role: .user, content: "hi")
            ],
            model: "kimi"
        )

        let body = try body(request)
        XCTAssertEqual(body["model"] as? String, "kimi")
        XCTAssertEqual(body["stream"] as? Bool, true)
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages, [
            ["role": "system", "content": "你是助手"],
            ["role": "user", "content": "hi"]
        ])
    }
}

final class ChatServiceErrorTests: XCTestCase {
    func testEveryErrorHasChineseDescription() {
        let errors: [ChatServiceError] = [
            .invalidURL, .http(401, "unauthorized"), .stream("服务繁忙")
        ]

        for error in errors {
            let description = error.errorDescription ?? ""
            XCTAssertFalse(description.isEmpty, "\(error) 缺少中文描述")
        }
        XCTAssertTrue(ChatServiceError.http(401, "unauthorized").errorDescription?.contains("401") == true)
    }
}
