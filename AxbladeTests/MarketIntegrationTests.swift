import XCTest
@testable import Axblade

/// 按 URL 子串路由的 HTTP mock:一次可脚本化多个端点。
/// 同一 pattern 注册多条时按顺序消耗(轮询场景:pending → token);
/// 只剩最后一条时不再消耗,重复请求稳定返回它。
final class MockHTTPProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var routes: [(pattern: String, status: Int, body: String)] = []
    nonisolated(unsafe) private static var requestedURLs: [String] = []
    nonisolated(unsafe) private static var authorizationHeaders: [String?] = []
    nonisolated(unsafe) private static var requestMethods: [String] = []
    nonisolated(unsafe) private static var requestBodies: [Data] = []
    nonisolated(unsafe) private static var responder: (@Sendable (URLRequest) -> (status: Int, body: String))?
    private static let lock = NSLock()

    static func install(_ newRoutes: [(pattern: String, status: Int, body: String)]) {
        lock.lock(); defer { lock.unlock() }
        routes = newRoutes
        responder = nil
        reset()
    }

    /// 一段流程里同一个路径要按调用次序给不同答复(设备码轮询:pending → signedIn),
    /// 且 `/auth/github/device` 是 `/auth/github/device/poll` 的前缀,
    /// `contains` 匹配的路由表分不开——这种场景直接注入一个应答函数。
    static func install(responder newResponder: @escaping @Sendable (URLRequest) -> (status: Int, body: String)) {
        lock.lock(); defer { lock.unlock() }
        routes = []
        responder = newResponder
        reset()
    }

    /// 调用方已持锁。
    private static func reset() {
        requestedURLs = []
        authorizationHeaders = []
        requestMethods = []
        requestBodies = []
    }

    static var lastRequestedURLs: [String] {
        lock.lock(); defer { lock.unlock() }
        return requestedURLs
    }

    static var lastAuthorizationHeaders: [String?] {
        lock.lock(); defer { lock.unlock() }
        return authorizationHeaders
    }

    static var lastRequestMethods: [String] {
        lock.lock(); defer { lock.unlock() }
        return requestMethods
    }

    /// 发出去的请求体。URLSession 会把 httpBody 转成 stream,这里两种都读。
    static var lastRequestBodies: [Data] {
        lock.lock(); defer { lock.unlock() }
        return requestBodies
    }

    /// 最后一次请求体解成 JSON 对象,断言字段用。
    static func lastRequestJSON() -> [String: Any]? {
        guard let data = lastRequestBodies.last else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func recordAuthorization(_ value: String?) {
        lock.lock(); defer { lock.unlock() }
        authorizationHeaders.append(value)
    }

    static func recordRequest(method: String, body: Data) {
        lock.lock(); defer { lock.unlock() }
        requestMethods.append(method)
        requestBodies.append(body)
    }

    /// 记录这次请求,并在装了应答函数时把它取出来(应答函数本身在锁外调用)。
    static func responder(recording url: String) -> (@Sendable (URLRequest) -> (status: Int, body: String))? {
        lock.lock(); defer { lock.unlock() }
        guard let responder else { return nil }
        requestedURLs.append(url)
        return responder
    }

    static func route(for url: String) -> (pattern: String, status: Int, body: String)? {
        lock.lock(); defer { lock.unlock() }
        requestedURLs.append(url)
        guard let index = routes.firstIndex(where: { url.contains($0.pattern) }) else { return nil }
        let matched = routes[index]
        let hasLaterMatch = routes[(index + 1)...].contains { url.contains($0.pattern) }
        if hasLaterMatch { routes.remove(at: index) }
        return matched
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockHTTPProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url?.absoluteString ?? ""
        Self.recordAuthorization(request.value(forHTTPHeaderField: "Authorization"))
        var outbound = request
        outbound.httpBody = Self.body(of: request)
        Self.recordRequest(method: request.httpMethod ?? "GET", body: outbound.httpBody ?? Data())

        let answer: (status: Int, body: String)
        if let responder = Self.responder(recording: url) {
            answer = responder(outbound)
        } else if let route = Self.route(for: url) {
            answer = (route.status, route.body)
        } else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: answer.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(answer.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

final class MarketIntegrationTests: XCTestCase {
    func testBinanceFullPipeline() async throws {
        MockHTTPProtocol.install([
            ("ticker/24hr", 200, #"{"symbol":"BTCUSDT","priceChangePercent":"-1.468","lastPrice":"64038.0","highPrice":"65379.13","lowPrice":"63806.27","volume":"13675.87"}"#),
            ("klines", 200, #"[[0,"0","0","0","64901.59","0",0,"0"],[0,"0","0","0","63970.01","0",0,"0"]]"#)
        ])
        let service = BinanceMarketService(session: MockHTTPProtocol.session())

        let snapshot = try await service.snapshot(rawSymbol: "btc")

        XCTAssertEqual(snapshot.symbol, "BTCUSDT")   // 归一化生效
        XCTAssertEqual(snapshot.price, 64038.0)
        XCTAssertEqual(snapshot.closes, [64901.59, 63970.01])
    }

    /// Binance 封锁中美 IP,必须全部经官方后端行情代理出海。
    /// 令牌由 `TokenStore` 提供(见 `ChatRequestTokenTests`),这里只管路由。
    func testBinanceRoutesThroughBackendProxy() async throws {
        MockHTTPProtocol.install([
            ("ticker/24hr", 200, #"{"symbol":"BTCUSDT","lastPrice":"64038.0"}"#),
            ("klines", 200, "[]")
        ])
        let service = BinanceMarketService(session: MockHTTPProtocol.session())

        _ = try await service.snapshot(rawSymbol: "btc")
        _ = try await service.dailyCloses(rawSymbol: "btc", days: 90)

        let urls = MockHTTPProtocol.lastRequestedURLs
        XCTAssertEqual(urls.count, 3)
        for url in urls {
            XCTAssertTrue(
                url.hasPrefix("\(Backend.baseURL)/market/binance/api/v3/"),
                "未走后端代理:\(url)"
            )
        }
    }

    /// 后端代理的 401/403/429 会带 {"error":{"message"}} body,
    /// 必须把这句话原样交给用户,而不是让解析层报「接口格式可能变了」。
    func testProxyErrorEnvelopeSurfacesTheBackendMessage() async {
        MockHTTPProtocol.install([
            ("ticker/24hr", 401, #"{"error":{"message":"访问令牌缺失或无效:请登录后重试","code":"unauthorized"}}"#)
        ])
        let service = BinanceMarketService(session: MockHTTPProtocol.session())

        do {
            _ = try await service.snapshot(rawSymbol: "btc")
            XCTFail("应当抛错")
        } catch let error as MarketDataError {
            XCTAssertEqual(error, .network("访问令牌缺失或无效:请登录后重试"))
        } catch {
            XCTFail("错误类型不对:\(error)")
        }
    }

    /// Yahoo 那种「404 但 body 里有可判读 JSON」的老行为不能被上面的改动带跑。
    func testNonEnvelopeErrorBodyStillReachesTheParser() async {
        MockHTTPProtocol.install([
            ("finance/chart/XXXX", 404, #"{"chart":{"result":null,"error":{"code":"Not Found","description":"No data found, symbol may be delisted"}}}"#)
        ])
        let service = YahooFinanceService(market: .usStock, session: MockHTTPProtocol.session())

        do {
            _ = try await service.snapshot(rawSymbol: "XXXX")
            XCTFail("应当抛错")
        } catch let error as MarketDataError {
            XCTAssertEqual(error, .invalidSymbol("XXXX"))
        } catch {
            XCTFail("错误类型不对:\(error)")
        }
    }

    func testYahooFullPipelineAppliesMarketSuffix() async throws {
        MockHTTPProtocol.install([
            ("finance/chart/600519.SS", 200, #"{"chart":{"result":[{"meta":{"currency":"CNY","symbol":"600519.SS","regularMarketPrice":1346.48,"longName":"Kweichow Moutai","chartPreviousClose":1340.0},"indicators":{"quote":[{"close":[1340.0,1346.48]}]}}],"error":null}}"#)
        ])
        let service = YahooFinanceService(market: .aShare, session: MockHTTPProtocol.session())

        let snapshot = try await service.snapshot(rawSymbol: "600519")

        XCTAssertEqual(snapshot.symbol, "600519.SS")
        XCTAssertEqual(snapshot.currency, "CNY")
        XCTAssertEqual(snapshot.name, "Kweichow Moutai")
    }

    func testYahoo404WithErrorBodyBecomesInvalidSymbol() async {
        MockHTTPProtocol.install([
            ("finance/chart", 404, #"{"chart":{"result":null,"error":{"code":"Not Found","description":"delisted"}}}"#)
        ])
        let service = YahooFinanceService(market: .usStock, session: MockHTTPProtocol.session())

        do {
            _ = try await service.snapshot(rawSymbol: "NOPE")
            XCTFail("未知代码应该抛错")
        } catch {
            XCTAssertEqual(error as? MarketDataError, .invalidSymbol("NOPE"))
        }
    }

    func testEmptyErrorBodySurfacesHTTPStatus() async {
        MockHTTPProtocol.install([("market/binance", 503, "")])
        let service = BinanceMarketService(session: MockHTTPProtocol.session())

        do {
            _ = try await service.snapshot(rawSymbol: "BTC")
            XCTFail("503 应该抛错")
        } catch {
            XCTAssertEqual(error as? MarketDataError, .http(503))
        }
    }

    // MARK: - dailyCloses

    func testBinanceDailyClosesRequestsFullLimit() async throws {
        MockHTTPProtocol.install([
            ("klines", 200, #"[[0,"0","0","0","100.0"],[0,"0","0","0","101.0"],[0,"0","0","0","102.0"]]"#)
        ])
        let service = BinanceMarketService(session: MockHTTPProtocol.session())

        let closes = try await service.dailyCloses(rawSymbol: "btc", days: 365)

        XCTAssertEqual(closes, [100.0, 101.0, 102.0])
        XCTAssertTrue(MockHTTPProtocol.lastRequestedURLs.contains { $0.contains("limit=365") })
    }

    func testOKXDailyClosesCapsAt300AndReverses() async throws {
        MockHTTPProtocol.install([
            ("candles", 200, #"{"code":"0","data":[["0","0","0","0","102.0"],["0","0","0","0","101.0"]]}"#)
        ])
        let service = OKXMarketService(session: MockHTTPProtocol.session())

        let closes = try await service.dailyCloses(rawSymbol: "BTC-USDT", days: 365)

        XCTAssertEqual(closes, [101.0, 102.0])   // 新→旧被反转
        XCTAssertTrue(MockHTTPProtocol.lastRequestedURLs.contains { $0.contains("limit=300") })
    }

    func testYahooDailyClosesPicksRangeAndTrims() async throws {
        let series = (1...400).map { "\($0).0" }.joined(separator: ",")
        let body = #"{"chart":{"result":[{"meta":{"regularMarketPrice":400.0,"chartPreviousClose":399.0},"indicators":{"quote":[{"close":[\#(series)]}]}}],"error":null}}"#
        MockHTTPProtocol.install([("finance/chart", 200, body)])
        let service = YahooFinanceService(market: .usStock, session: MockHTTPProtocol.session())

        let result = try await service.dailyCloses(rawSymbol: "AAPL", days: 365)

        XCTAssertEqual(result.count, 365)          // 只取尾部 365
        XCTAssertEqual(result.last, 400.0)
        XCTAssertTrue(MockHTTPProtocol.lastRequestedURLs.contains { $0.contains("range=1y") })
    }

    func testGarbageBodyBecomesDecodingError() async {
        MockHTTPProtocol.install([("okx.com", 200, "<html>oops</html>")])
        let service = OKXMarketService(session: MockHTTPProtocol.session())

        do {
            _ = try await service.snapshot(rawSymbol: "BTC")
            XCTFail("坏 JSON 应该抛错")
        } catch {
            XCTAssertEqual(error as? MarketDataError, .decoding)
        }
    }
}
