import XCTest
import Foundation
@testable import Axblade

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
