import Foundation

/// 一段消息正文:要么是散文,要么是一个代码块。
enum MarkdownSegment: Equatable, Sendable {
    case text(String)
    case code(language: String?, content: String)
}

/// 按 ``` 围栏把消息正文切成段。行内 Markdown 交给 `AttributedString`,
/// 这里只负责把代码块摘出来单独渲染。
enum MarkdownSegmenter {
    static func segments(from markdown: String) -> [MarkdownSegment] {
        var segments: [MarkdownSegment] = []
        var buffer: [String] = []
        var language: String?
        var insideFence = false

        func flush() {
            let content = buffer.joined(separator: "\n")
            buffer.removeAll()
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            segments.append(insideFence ? .code(language: language, content: content) : .text(trimmed))
        }

        for line in markdown.components(separatedBy: .newlines) {
            let fenceInfo = line.trimmingCharacters(in: .whitespaces)
            guard fenceInfo.hasPrefix("```") else {
                buffer.append(line)
                continue
            }

            flush()
            if insideFence {
                insideFence = false
                language = nil
            } else {
                insideFence = true
                let tag = fenceInfo.dropFirst(3).trimmingCharacters(in: .whitespaces)
                language = tag.isEmpty ? nil : tag
            }
        }
        flush()

        return segments
    }
}
