import Foundation

/// 一行 SSE 解析出来的东西。
enum SSEEvent: Equatable, Sendable {
    case data(String)
    case done
}

/// 逐行的 SSE 解析器。只认字节流的形状,不知道 HTTP,也不知道任何一家厂商的字段。
struct SSEParser: Sendable {
    /// 喂入一行(不带换行符)。非 `data:` 行(空行、`:` 注释、`event:`/`id:` 等)返回 nil。
    mutating func consume(line: String) -> SSEEvent? {
        let line = line.hasSuffix("\r") ? String(line.dropLast()) : line
        guard line.hasPrefix("data:") else { return nil }

        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return .done }
        guard !payload.isEmpty else { return nil }
        return .data(payload)
    }

    // MARK: - 各家增量字段的提取

    /// OpenAI 兼容:`choices[0].delta.content`
    static func openAIDelta(fromDataPayload json: String) -> String? {
        guard let object = jsonObject(json),
              let choices = object["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let content = delta["content"] as? String,
              !content.isEmpty
        else { return nil }
        return content
    }

    /// 流中途下发的错误(`error.message`),用来把失败原因带给用户。
    static func streamErrorMessage(fromDataPayload json: String) -> String? {
        guard let object = jsonObject(json),
              let error = object["error"] as? [String: Any],
              let message = error["message"] as? String,
              !message.isEmpty
        else { return nil }
        return message
    }

    private static func jsonObject(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
