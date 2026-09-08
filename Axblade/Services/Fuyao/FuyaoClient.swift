import Foundation

/// 同花顺金融数据 API(fuyao)的调用错误。
enum FuyaoError: LocalizedError, Equatable {
    /// 钥匙串与内置默认值都没有 API Key。
    case missingKey
    /// 业务错误:`code != 0`。
    case api(code: Int, message: String)
    /// 非 200 的 HTTP 状态(理论上不会有,fuyao 恒 200)。
    case http(Int)
    case decoding(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingKey: "缺少同花顺数据 API Key,请在 设置 › 数据源 填写"
        case .api(let code, let message): "数据接口错误 \(code):\(message)"
        case .http(let status): "数据服务返回 HTTP \(status)"
        case .decoding(let detail): "数据解析失败:\(detail)"
        case .network(let message): "网络请求失败:\(message)"
        }
    }

    /// 频率超限(业务码 4001 或 HTTP 429)/ 上游超时 / 数据源不可用 / 5xx 可以重试。
    var isRetryable: Bool {
        switch self {
        case .api(let code, _): [4001, 5002, 5003].contains(code)
        case .http(let status): status == 429 || status >= 500
        case .network: true
        default: false
        }
    }

    var isRateLimited: Bool {
        switch self {
        case .api(4001, _), .http(429): true
        default: false
        }
    }
}

/// API Key 的唯一出入口:钥匙串优先,没有就用内置默认值。
enum FuyaoKeyStore {
    static let keychainAccount = "fuyao.apikey"
    /// 内置默认 Key(用户提供)。设置页填写后以钥匙串为准。
    static let builtInKey = "sk-fuyao-ARXe9h5JxIHS6Y3trn1kWiOXwJitd4F4"

    static func key() -> String? {
        if let stored = KeychainStore.secret(account: keychainAccount), !stored.isEmpty { return stored }
        return builtInKey.isEmpty ? nil : builtInKey
    }

    /// 传空串即恢复内置默认值。
    @discardableResult
    static func set(_ key: String?) -> Bool {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            KeychainStore.deleteSecret(account: keychainAccount)
            return true
        }
        return KeychainStore.setSecret(trimmed, account: keychainAccount) == errSecSuccess
    }

    static var isUsingBuiltIn: Bool {
        KeychainStore.secret(account: keychainAccount).map(\.isEmpty) ?? true
    }
}

/// 底层 HTTP:拼 query、带 `X-api-key`、拆信封、按 code 报错、限流重试。
struct FuyaoClient: Sendable {
    var session: URLSession = .shared
    var baseURL = "https://fuyao.aicubes.cn"
    var keyProvider: @Sendable () -> String? = { FuyaoKeyStore.key() }
    /// 可重试错误的最大尝试次数(含首发)。
    var attempts = 4
    /// 重试之间的等待;测试注入即时返回。
    var sleeper: @Sendable (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    func makeRequest(path: String, query: [String: String]) throws -> URLRequest {
        guard let key = keyProvider(), !key.isEmpty else { throw FuyaoError.missingKey }
        guard var components = URLComponents(string: baseURL + path) else { throw FuyaoError.network("无效地址") }
        if !query.isEmpty {
            components.queryItems = query.keys.sorted().map { URLQueryItem(name: $0, value: query[$0]) }
        }
        guard let url = components.url else { throw FuyaoError.network("无效地址") }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(key, forHTTPHeaderField: "X-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 60
        return request
    }

    /// 拆信封;`code != 0` 抛 `FuyaoError.api`。
    static func unwrap<Payload: Decodable>(_ data: Data, as type: Payload.Type) throws -> Payload {
        let envelope: FuyaoEnvelope<Payload>
        do {
            envelope = try decoder.decode(FuyaoEnvelope<Payload>.self, from: data)
        } catch {
            throw FuyaoError.decoding(Self.describe(error))
        }
        guard envelope.code == 0 else {
            throw FuyaoError.api(code: envelope.code, message: envelope.message ?? "")
        }
        guard let payload = envelope.data else {
            throw FuyaoError.decoding("data 为空")
        }
        return payload
    }

    func get<Payload: Decodable>(_ path: String, query: [String: String] = [:], as type: Payload.Type) async throws -> Payload {
        let request = try makeRequest(path: path, query: query)
        var attempt = 0
        while true {
            attempt += 1
            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw FuyaoError.http(http.statusCode)
                }
                return try Self.unwrap(data, as: type)
            } catch let error as FuyaoError where error.isRetryable && attempt < attempts {
                // 限流退避更久:1.5s / 3s / 4.5s;其它错误 0.8s 起步。
                try await sleeper(Double(attempt) * (error.isRateLimited ? 1.5 : 0.8))
            } catch let error as FuyaoError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch {
                if attempt < attempts {
                    try await sleeper(Double(attempt) * 0.8)
                    continue
                }
                throw FuyaoError.network(error.localizedDescription)
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else { return error.localizedDescription }
        switch decoding {
        case .keyNotFound(let key, let context):
            return "缺少字段 \(key.stringValue)(\(context.codingPath.map(\.stringValue).joined(separator: ".")))"
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            return context.debugDescription + " @ " + context.codingPath.map(\.stringValue).joined(separator: ".")
        @unknown default:
            return error.localizedDescription
        }
    }
}

/// A 股代码归一化:`600519` → `600519.SH`,`000001` → `000001.SZ`,`430001` → `430001.BJ`。
enum AShareSymbol {
    static func normalize(_ raw: String) -> String {
        var symbol = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        symbol = symbol.replacingOccurrences(of: ".SS", with: ".SH")
        if symbol.hasPrefix("SH") || symbol.hasPrefix("SZ") || symbol.hasPrefix("BJ"),
           symbol.count == 8, symbol.dropFirst(2).allSatisfy(\.isNumber) {
            return String(symbol.dropFirst(2)) + "." + String(symbol.prefix(2))
        }
        guard !symbol.contains("."), symbol.count == 6, symbol.allSatisfy(\.isNumber) else { return symbol }
        switch symbol.first {
        case "6", "9", "5": return symbol + ".SH"
        case "0", "3", "1", "2": return symbol + ".SZ"
        case "4", "8": return symbol + ".BJ"
        default: return symbol
        }
    }

    /// 从自由文本里抽出所有 6 位 A 股代码(可带交易所后缀),去重保序。
    static func codes(in text: String) -> [String] {
        let pattern = #"(?<![0-9])(?:SH|SZ|BJ|sh|sz|bj)?([0-9]{6})(?:\.(?:SH|SZ|BJ|SS|sh|sz|bj|ss))?(?![0-9])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var seen = Set<String>()
        var result: [String] = []
        for match in regex.matches(in: text, range: range) {
            guard let whole = Range(match.range, in: text) else { continue }
            let code = normalize(String(text[whole]))
            guard code.contains("."), seen.insert(code).inserted else { continue }
            result.append(code)
        }
        return result
    }

    /// 所属板块:主板 / 创业板 / 科创板 / 北交所。
    static func board(of thscode: String) -> String {
        let ticker = thscode.prefix(6)
        if ticker.hasPrefix("688") || ticker.hasPrefix("689") { return "科创板" }
        if ticker.hasPrefix("300") || ticker.hasPrefix("301") { return "创业板" }
        if thscode.hasSuffix(".BJ") || ticker.hasPrefix("4") || ticker.hasPrefix("8") { return "北交所" }
        return "主板"
    }
}

/// 日期工具:fuyao 一律按 Asia/Shanghai。
enum ShanghaiDate {
    static let timeZone = TimeZone(identifier: "Asia/Shanghai")!

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func string(_ date: Date) -> String { dayFormatter.string(from: date) }

    static func date(_ text: String) -> Date? {
        let compact = text.replacingOccurrences(of: "-", with: "")
        guard compact.count == 8 else { return nil }
        let formatted = "\(compact.prefix(4))-\(compact.dropFirst(4).prefix(2))-\(compact.suffix(2))"
        return dayFormatter.date(from: formatted)
    }

    /// 某天在上海时区的零点毫秒戳。
    static func startOfDayMs(_ date: Date) -> Int64 {
        Int64(calendar.startOfDay(for: date).timeIntervalSince1970 * 1000)
    }

    static func ms(_ date: Date) -> Int64 { Int64(date.timeIntervalSince1970 * 1000) }

    /// `yyyy-MM-dd` / `yyyyMMdd` 统一成 `yyyy-MM-dd`。
    static func normalizeDay(_ text: String) -> String {
        date(text).map(string) ?? text
    }
}
