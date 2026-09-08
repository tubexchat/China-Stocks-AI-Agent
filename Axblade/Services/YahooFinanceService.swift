import Foundation

/// 四个股票市场(美/韩/港/A)共用的 Yahoo Finance v8 chart 服务。
/// 非官方接口:必须带浏览器 User-Agent,未知代码返回 404 + error JSON。
struct YahooFinanceService: MarketDataService {
    var market: MarketSourceKind
    var session: URLSession = .shared

    /// 含 `.` 的输入尊重用户后缀;否则按市场补:韩 `.KS`、港补零 4 位 `.HK`、A 股按前缀 `.SS`/`.SZ`。
    static func normalize(_ raw: String, market: MarketSourceKind) -> String {
        let symbol = raw.trimmingCharacters(in: .whitespaces).uppercased()
        guard !symbol.isEmpty, !symbol.contains(".") else { return symbol }
        let isDigits = symbol.allSatisfy(\.isNumber)

        switch market {
        case .usStock:
            return symbol
        case .krStock:
            return isDigits ? symbol + ".KS" : symbol
        case .hkStock:
            guard isDigits else { return symbol }
            let trimmed = symbol.drop { $0 == "0" }
            let padded = String(repeating: "0", count: max(0, 4 - trimmed.count)) + trimmed
            return padded + ".HK"
        case .aShare:
            guard isDigits else { return symbol }
            let suffix = symbol.hasPrefix("0") || symbol.hasPrefix("3") ? ".SZ" : ".SS"
            return symbol + suffix
        default:
            return symbol
        }
    }

    static func parse(symbol: String, market: MarketSourceKind, chartData: Data, fetchedAt: Date) throws -> MarketSnapshot {
        guard let root = try MarketHTTP.json(chartData) as? [String: Any],
              let chart = root["chart"] as? [String: Any]
        else { throw MarketDataError.decoding }
        guard let results = chart["result"] as? [[String: Any]],
              let result = results.first,
              let meta = result["meta"] as? [String: Any],
              let price = MarketHTTP.double(meta["regularMarketPrice"])
        else { throw MarketDataError.invalidSymbol(symbol) }   // result 为 null + error 对象

        let previousClose = MarketHTTP.double(meta["chartPreviousClose"])
        let change = previousClose.flatMap { prev in prev == 0 ? nil : (price - prev) / prev * 100 }

        let indicators = result["indicators"] as? [String: Any]
        let quote = (indicators?["quote"] as? [[String: Any]])?.first
        let closes = (quote?["close"] as? [Any] ?? []).compactMap(MarketHTTP.double)

        return MarketSnapshot(
            source: market,
            symbol: symbol,
            name: (meta["longName"] as? String) ?? (meta["shortName"] as? String),
            price: price,
            changePercent: change,
            high: MarketHTTP.double(meta["regularMarketDayHigh"]),
            low: MarketHTTP.double(meta["regularMarketDayLow"]),
            volume: MarketHTTP.double(meta["regularMarketVolume"]),
            currency: meta["currency"] as? String,
            closes: Array(closes),
            fetchedAt: fetchedAt
        )
    }

    func snapshot(rawSymbol: String) async throws -> MarketSnapshot {
        let symbol = Self.normalize(rawSymbol, market: market)
        let data = try await fetchChart(symbol: symbol, range: "1mo")
        var snapshot = try Self.parse(symbol: symbol, market: market, chartData: data, fetchedAt: Date())
        snapshot.closes = Array(snapshot.closes.suffix(30))   // 附件场景只带最近 30 根
        return snapshot
    }

    func dailyCloses(rawSymbol: String, days: Int) async throws -> [Double] {
        let symbol = Self.normalize(rawSymbol, market: market)
        let range = days <= 30 ? "1mo" : (days <= 180 ? "6mo" : "1y")
        let data = try await fetchChart(symbol: symbol, range: range)
        var snapshot = try Self.parse(symbol: symbol, market: market, chartData: data, fetchedAt: Date())
        snapshot.closes = Array(snapshot.closes.suffix(days))
        return snapshot.closes
    }

    private func fetchChart(symbol: String, range: String) async throws -> Data {
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        var request = URLRequest(
            url: URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?range=\(range)&interval=1d")!
        )
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        return try await MarketHTTP.fetch(request, session: session)
    }
}
