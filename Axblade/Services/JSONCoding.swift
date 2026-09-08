import Foundation

extension Date {
    /// 对齐到毫秒网格。
    ///
    /// 落盘用的 ISO8601 只带三位小数,而 `Date` 内部是 `Double`;不对齐的话
    /// 「写出去再读回来」就不等于内存里的值,持久化没法做等值断言。
    /// 模型的时间戳一律在初始化时经过这里,毫秒对于聊天记录也完全够用。
    var snappedToMilliseconds: Date {
        Date(timeIntervalSince1970: (timeIntervalSince1970 * 1000).rounded() / 1000)
    }
}

/// 全应用共用的 JSON 编解码配置。
enum JSONCoding {
    /// 不含小数秒的 ISO8601;小数部分由下面自己拼,
    /// 因为 `Date.ISO8601FormatStyle(includingFractionalSeconds: true)` 在毫秒边界上
    /// 会把 `.002` 写成 `.001`,连自身都不幂等。
    private static let secondsStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

    static func string(from date: Date) -> String {
        let milliseconds = (date.timeIntervalSince1970 * 1000).rounded()
        let seconds = (milliseconds / 1000).rounded(.down)
        let fraction = Int(milliseconds - seconds * 1000)
        let base = secondsStyle.format(Date(timeIntervalSince1970: seconds))
        return base.dropLast() + String(format: ".%03dZ", fraction)
    }

    static func date(from text: String) -> Date? {
        guard let dot = text.firstIndex(of: "."), let zulu = text.lastIndex(of: "Z"), dot < zulu else {
            return try? secondsStyle.parse(text)
        }
        guard let base = try? secondsStyle.parse(text[text.startIndex..<dot] + "Z"),
              let fraction = Double(text[text.index(after: dot)..<zulu])
        else { return nil }
        return Date(timeIntervalSince1970: base.timeIntervalSince1970 + fraction / 1000).snappedToMilliseconds
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(string(from: date))
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = date(from: text) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "无法解析日期:\(text)")
                )
            }
            return date
        }
        return decoder
    }
}
