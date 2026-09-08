import Foundation

// MARK: - Binance

struct BinanceMarketService: MarketDataService {
    var session: URLSession = .shared

    /// Binance 封锁中国/美国 IP(451),所有请求经官方后端行情代理出海。
    /// 代理只放行 ticker/24hr 与 klines,鉴权用登录后签发的令牌(未登录时后端会 401)。
    static func proxiedRequest(_ pathAndQuery: String, token: String? = TokenStore.token()) -> URLRequest {
        var request = URLRequest(url: URL(string: "\(Backend.baseURL)/market/binance/\(pathAndQuery)")!)
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }

    /// 大写、去分隔符;纯 base(如 `btc`)补 USDT。
    static func normalize(_ raw: String) -> String {
        let symbol = raw.uppercased()
            .components(separatedBy: CharacterSet(charactersIn: "-/ "))
            .joined()
        guard !symbol.isEmpty else { return symbol }
        let hasQuote = MarketHTTP.knownQuotes.contains { symbol.hasSuffix($0) && symbol.count > $0.count }
        return hasQuote ? symbol : symbol + "USDT"
    }

    static func parse(symbol: String, tickerData: Data, klinesData: Data, fetchedAt: Date) throws -> MarketSnapshot {
        guard let ticker = try MarketHTTP.json(tickerData) as? [String: Any] else {
            throw MarketDataError.decoding
        }
        if ticker["lastPrice"] == nil, ticker["code"] != nil {
            // -1121 = Invalid symbol;其余(如地区封锁的 451 响应)把服务端消息带给用户。
            if MarketHTTP.double(ticker["code"]) == -1121 {
                throw MarketDataError.invalidSymbol(symbol)
            }
            throw MarketDataError.network((ticker["msg"] as? String) ?? "接口返回异常")
        }
        guard let price = MarketHTTP.double(ticker["lastPrice"]) else { throw MarketDataError.decoding }

        let klines = (try? MarketHTTP.json(klinesData)) as? [[Any]] ?? []
        return MarketSnapshot(
            source: .binance,
            symbol: symbol,
            name: nil,
            price: price,
            changePercent: MarketHTTP.double(ticker["priceChangePercent"]),   // 已是百分数
            high: MarketHTTP.double(ticker["highPrice"]),
            low: MarketHTTP.double(ticker["lowPrice"]),
            volume: MarketHTTP.double(ticker["volume"]),
            currency: nil,
            closes: klines.compactMap { $0.count > 4 ? MarketHTTP.double($0[4]) : nil },
            fetchedAt: fetchedAt
        )
    }

    func snapshot(rawSymbol: String) async throws -> MarketSnapshot {
        let symbol = Self.normalize(rawSymbol)
        async let ticker = MarketHTTP.fetch(Self.proxiedRequest("api/v3/ticker/24hr?symbol=\(symbol)"), session: session)
        async let klines = MarketHTTP.fetch(Self.proxiedRequest("api/v3/klines?symbol=\(symbol)&interval=1d&limit=30"), session: session)
        return try await Self.parse(symbol: symbol, tickerData: ticker, klinesData: klines, fetchedAt: Date())
    }

    func dailyCloses(rawSymbol: String, days: Int) async throws -> [Double] {
        let symbol = Self.normalize(rawSymbol)
        let limit = min(max(days, 1), 1000)
        let request = Self.proxiedRequest("api/v3/klines?symbol=\(symbol)&interval=1d&limit=\(limit)")
        let data = try await MarketHTTP.fetch(request, session: session)
        guard let klines = try MarketHTTP.json(data) as? [[Any]] else { throw MarketDataError.decoding }
        return klines.compactMap { $0.count > 4 ? MarketHTTP.double($0[4]) : nil }
    }
}

// MARK: - MEXC(接口形状 Binance 兼容,唯独 priceChangePercent 是小数)

struct MEXCMarketService: MarketDataService {
    var session: URLSession = .shared

    static func normalize(_ raw: String) -> String {
        BinanceMarketService.normalize(raw)
    }

    static func parse(symbol: String, tickerData: Data, klinesData: Data, fetchedAt: Date) throws -> MarketSnapshot {
        var snapshot = try BinanceMarketService.parse(
            symbol: symbol, tickerData: tickerData, klinesData: klinesData, fetchedAt: fetchedAt
        )
        snapshot.source = .mexc
        // 实测:MEXC 的 priceChangePercent 给 -0.0149(小数),Binance 给 -1.468(百分数)。
        snapshot.changePercent = snapshot.changePercent.map { $0 * 100 }
        return snapshot
    }

    func snapshot(rawSymbol: String) async throws -> MarketSnapshot {
        let symbol = Self.normalize(rawSymbol)
        let base = "https://api.mexc.com/api/v3"
        async let ticker = MarketHTTP.fetch(URLRequest(url: URL(string: "\(base)/ticker/24hr?symbol=\(symbol)")!), session: session)
        async let klines = MarketHTTP.fetch(URLRequest(url: URL(string: "\(base)/klines?symbol=\(symbol)&interval=1d&limit=30")!), session: session)
        return try await Self.parse(symbol: symbol, tickerData: ticker, klinesData: klines, fetchedAt: Date())
    }

    func dailyCloses(rawSymbol: String, days: Int) async throws -> [Double] {
        let symbol = Self.normalize(rawSymbol)
        let limit = min(max(days, 1), 1000)
        let url = URL(string: "https://api.mexc.com/api/v3/klines?symbol=\(symbol)&interval=1d&limit=\(limit)")!
        let data = try await MarketHTTP.fetch(URLRequest(url: url), session: session)
        guard let klines = try MarketHTTP.json(data) as? [[Any]] else { throw MarketDataError.decoding }
        return klines.compactMap { $0.count > 4 ? MarketHTTP.double($0[4]) : nil }
    }
}

// MARK: - OKX

struct OKXMarketService: MarketDataService {
    var session: URLSession = .shared

    /// OKX 要 `BASE-QUOTE`。`BTCUSDT` → `BTC-USDT`,纯 base 补 `-USDT`。
    static func normalize(_ raw: String) -> String {
        var symbol = raw.uppercased()
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespaces)
        guard !symbol.contains("-") else { return symbol }
        for quote in MarketHTTP.knownQuotes where symbol.hasSuffix(quote) && symbol.count > quote.count {
            symbol.insert("-", at: symbol.index(symbol.endIndex, offsetBy: -quote.count))
            return symbol
        }
        return symbol + "-USDT"
    }

    static func parse(symbol: String, tickerData: Data, klinesData: Data, fetchedAt: Date) throws -> MarketSnapshot {
        guard let envelope = try MarketHTTP.json(tickerData) as? [String: Any],
              let list = envelope["data"] as? [[String: Any]]
        else { throw MarketDataError.decoding }
        guard let ticker = list.first, let price = MarketHTTP.double(ticker["last"]) else {
            throw MarketDataError.invalidSymbol(symbol)   // code 51001,data 为空
        }

        let open24h = MarketHTTP.double(ticker["open24h"])
        let change = open24h.flatMap { open in open == 0 ? nil : (price - open) / open * 100 }

        // candles 是新→旧,反转成旧→新。
        let candleEnvelope = (try? MarketHTTP.json(klinesData)) as? [String: Any]
        let candles = candleEnvelope?["data"] as? [[Any]] ?? []
        let closes = candles.compactMap { $0.count > 4 ? MarketHTTP.double($0[4]) : nil }.reversed()

        return MarketSnapshot(
            source: .okx,
            symbol: symbol,
            name: nil,
            price: price,
            changePercent: change,
            high: MarketHTTP.double(ticker["high24h"]),
            low: MarketHTTP.double(ticker["low24h"]),
            volume: MarketHTTP.double(ticker["vol24h"]),
            currency: nil,
            closes: Array(closes),
            fetchedAt: fetchedAt
        )
    }

    func snapshot(rawSymbol: String) async throws -> MarketSnapshot {
        let symbol = Self.normalize(rawSymbol)
        let base = "https://www.okx.com/api/v5/market"
        async let ticker = MarketHTTP.fetch(URLRequest(url: URL(string: "\(base)/ticker?instId=\(symbol)")!), session: session)
        async let candles = MarketHTTP.fetch(URLRequest(url: URL(string: "\(base)/candles?instId=\(symbol)&bar=1D&limit=30")!), session: session)
        return try await Self.parse(symbol: symbol, tickerData: ticker, klinesData: candles, fetchedAt: Date())
    }

    func dailyCloses(rawSymbol: String, days: Int) async throws -> [Double] {
        let symbol = Self.normalize(rawSymbol)
        let limit = min(max(days, 1), 300)   // OKX 单页上限
        let url = URL(string: "https://www.okx.com/api/v5/market/candles?instId=\(symbol)&bar=1D&limit=\(limit)")!
        let data = try await MarketHTTP.fetch(URLRequest(url: url), session: session)
        guard let envelope = try MarketHTTP.json(data) as? [String: Any],
              let candles = envelope["data"] as? [[Any]]
        else { throw MarketDataError.decoding }
        // 新→旧,反转成旧→新
        return candles.compactMap { $0.count > 4 ? MarketHTTP.double($0[4]) : nil }.reversed()
    }
}
