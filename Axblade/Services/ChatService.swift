import Foundation

enum ChatServiceError: LocalizedError, Equatable {
    case invalidURL
    case http(Int, String)
    case stream(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "后端地址无效,请更新客户端"
        case .http(let status, let body):
            "服务返回 HTTP \(status):\(Self.trim(body))"
        case .stream(let message):
            "生成中断:\(message)"
        }
    }

    private static func trim(_ body: String) -> String {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "无响应内容" }
        return text.count > 300 ? String(text.prefix(300)) + "…" : text
    }
}

/// 把一次对话变成一串文本增量。实现者只负责构造请求 + 说明怎么从 SSE 里取增量。
protocol ChatService: Sendable {
    func streamReply(
        messages: [ChatMessage],
        model: String
    ) -> AsyncThrowingStream<String, Error>
}

/// OpenAI 兼容协议,固定打官方后端(`Backend`)。
/// 鉴权用登录后签发的令牌(钥匙串),客户端不涉及任何模型 APIKEY。
struct OpenAIChatService: ChatService {
    var session: URLSession = .shared

    /// `token` 只为测试留了口子,生产调用一律走 `TokenStore`。
    static func buildRequest(
        messages: [ChatMessage],
        model: String,
        token: String? = TokenStore.token()
    ) throws -> URLRequest {
        let url = try SSEHTTP.endpoint(baseURL: Backend.baseURL, path: "chat/completions")
        var request = SSEHTTP.baseRequest(url: url)
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "stream": true,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        ])
        return request
    }

    func streamReply(
        messages: [ChatMessage],
        model: String
    ) -> AsyncThrowingStream<String, Error> {
        SSEHTTP.stream(session: session) {
            try Self.buildRequest(messages: messages, model: model)
        } extract: {
            SSEParser.openAIDelta(fromDataPayload: $0)
        }
    }
}

// MARK: - HTTP + SSE 循环

enum SSEHTTP {
    static func endpoint(baseURL: String, path: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed),
              url.scheme != nil, url.host != nil
        else { throw ChatServiceError.invalidURL }
        return url.appendingPathComponent(path)
    }

    static func baseRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 120
        return request
    }

    /// 发请求,把响应按行喂给 `SSEParser`,把抽出来的文本增量往外吐。
    static func stream(
        session: URLSession,
        makeRequest: @escaping @Sendable () throws -> URLRequest,
        extract: @escaping @Sendable (String) -> String?
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: try makeRequest())

                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        var body = ""
                        for try await line in bytes.lines where body.count < 2000 {
                            body += line + "\n"
                        }
                        throw ChatServiceError.http(http.statusCode, body)
                    }

                    var parser = SSEParser()
                    for try await line in bytes.lines {
                        guard let event = parser.consume(line: line) else { continue }
                        switch event {
                        case .done:
                            continuation.finish()
                            return
                        case .data(let payload):
                            if let message = SSEParser.streamErrorMessage(fromDataPayload: payload) {
                                throw ChatServiceError.stream(message)
                            }
                            if let delta = extract(payload) {
                                continuation.yield(delta)
                            }
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as URLError where error.code == .cancelled {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
