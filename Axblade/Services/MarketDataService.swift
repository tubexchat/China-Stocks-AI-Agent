import Foundation

enum MarketDataError: LocalizedError, Equatable {
    case invalidSymbol(String)
    case http(Int)
    case decoding
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidSymbol(let symbol):
            "找不到代码 \(symbol),请检查拼写或换个市场"
        case .http(let status):
            "行情服务返回 HTTP \(status)"
        case .decoding:
            "行情数据解析失败,接口格式可能变了"
        case .network(let message):
            "网络请求失败:\(message)"
        }
    }
}

/// 把一个用户输入的代码变成一份行情快照。实现者自管代码归一化与端点细节。
protocol MarketDataService: Sendable {
    func snapshot(rawSymbol: String) async throws -> MarketSnapshot
    /// 最近 `days` 根日线收盘,旧→新。量化工具用;各源按能力截断。
    func dailyCloses(rawSymbol: String, days: Int) async throws -> [Double]
}

extension MarketDataService {
    /// 默认回落到快照自带的 ≤30 根收盘。
    func dailyCloses(rawSymbol: String, days: Int) async throws -> [Double] {
        try await snapshot(rawSymbol: rawSymbol).closes
    }
}

enum MarketServiceRegistry {
    /// 7 个数据源全量映射。session 可注入以便测试。
    static func services(session: URLSession = .shared) -> [MarketSourceKind: any MarketDataService] {
        [
            .binance: BinanceMarketService(session: session),
            .okx: OKXMarketService(session: session),
            .mexc: MEXCMarketService(session: session),
            .usStock: YahooFinanceService(market: .usStock, session: session),
            .krStock: YahooFinanceService(market: .krStock, session: session),
            .hkStock: YahooFinanceService(market: .hkStock, session: session),
            .aShare: YahooFinanceService(market: .aShare, session: session)
        ]
    }
}

// MARK: - 实现共用的小工具

enum MarketHTTP {
    /// 已知报价币后缀,用于把 `BTCUSDT`/`btc` 这类输入归一化。
    static let knownQuotes = ["USDT", "USDC", "FDUSD", "BTC", "ETH", "USD"]

    static func fetch(_ request: URLRequest, session: URLSession) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw MarketDataError.network(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // 官方后端(行情代理)的 401/403/429 会带 {"error":{"message"}};
            // 那句话是给用户看的,原样抛出去,别让解析层报「接口格式可能变了」。
            if let message = L10nStrings.backendMessage(in: String(data: data, encoding: .utf8) ?? "") {
                throw MarketDataError.network(message)
            }
            // Yahoo 对未知代码返回 404 但 body 里有可判读的 JSON;
            // 有 body 就交给解析层报 invalidSymbol,空 body 才按 HTTP 状态报错。
            if data.isEmpty { throw MarketDataError.http(http.statusCode) }
        }
        return data
    }

    static func double(_ any: Any?) -> Double? {
        if let value = any as? Double { return value }
        if let text = any as? String { return Double(text) }
        if let value = any as? Int { return Double(value) }
        return nil
    }

    static func json(_ data: Data) throws -> Any {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            throw MarketDataError.decoding
        }
        return object
    }
}
