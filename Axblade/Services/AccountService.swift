import Foundation

/// 账户接口的错误。非 2xx 一律带上后端的 `error.message`——
/// 后端文案已经是可读中文,客户端不再自己编 401/403/429 的话术。
enum AccountError: LocalizedError, Equatable {
    case notSignedIn
    case http(Int, String, String?)
    case decoding

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "尚未登录,请先在 设置 › 账户 登录"
        case .http(_, let message, _): message
        case .decoding: "账户接口返回的数据解析失败,请更新客户端"
        }
    }

    /// 后端错误码(如 `invalid_credentials` / `quota_exceeded` / `unauthorized`)。
    var code: String? {
        if case .http(_, _, let code) = self { return code }
        return nil
    }

    var statusCode: Int? {
        if case .http(let status, _, _) = self { return status }
        return nil
    }
}

/// 后端账户接口(spec 1.4)。无状态值类型,令牌从 `tokenProvider` 取,测试可注入。
struct AccountService: Sendable {
    var session: URLSession = .shared
    var baseURL: String = Backend.baseURL
    var tokenProvider: @Sendable () -> String? = { TokenStore.token() }

    /// 后端用它区分会话来源,`/v1/me/sessions` 里会显示。
    static let client = "mac"

    // MARK: - 注册 / 登录

    func signup(email: String, password: String, displayName: String) async throws -> String {
        try await token(from: post("auth/signup", body: [
            "email": email, "password": password,
            "display_name": displayName, "client": Self.client
        ], authorized: false))
    }

    func login(email: String, password: String) async throws -> String {
        try await token(from: post("auth/login", body: [
            "email": email, "password": password, "client": Self.client
        ], authorized: false))
    }

    /// 吊销当前令牌(204)。
    func logout() async throws {
        _ = try await post("auth/logout", body: [:])
    }

    /// 吊销该用户的全部令牌(204)。
    func logoutAll() async throws {
        _ = try await post("auth/logout_all", body: [:])
    }

    /// 改密成功后后端会吊销**其它**会话,当前令牌继续可用。
    /// 纯社交账户是「首次设置密码」:`current` 传空串,后端据此放行。
    func changePassword(current: String, new: String) async throws {
        _ = try await post("auth/password", body: [
            "current_password": current, "new_password": new
        ])
    }

    // MARK: - 社交登录(spec 1.4b)

    /// 申请 GitHub 设备码。**经我们自己的后端代理**:GitHub 的 client secret
    /// 只在服务端,客户端一个字节都不持有,也不直接跟 github.com 换令牌。
    func githubDeviceStart() async throws -> DeviceCode {
        try decode(
            DeviceCode.self,
            from: try await post("auth/github/device", body: ["client": Self.client], authorized: false)
        )
    }

    /// 轮询设备码。202 = 还没授权(`interval` 非 nil 时要换轮询间隔);200 = 换到令牌。
    /// 410 `device_code_expired` / 403 `access_denied` / 502 `provider_error`
    /// 统一走 `AccountError.http`,文案用后端的。
    func githubDevicePoll(deviceCode: String) async throws -> GitHubPoll {
        let (data, status) = try await response(
            method: "POST",
            path: "auth/github/device/poll",
            body: try JSONSerialization.data(withJSONObject: [
                "device_code": deviceCode, "client": Self.client
            ]),
            authorized: false
        )
        guard status != 202 else {
            return .pending(interval: try? decode(PendingPoll.self, from: data).interval)
        }
        let signedIn = try decode(SignedInResponse.self, from: data)
        return .signedIn(token: signedIn.token, user: signedIn.user)
    }

    /// 原生 Sign in with Apple:把 Apple 给的 identity token 交给后端验签(aud = bundle id)。
    /// Apple 只在**首次**授权时给姓名,之后是 nil——那时不能发空 full_name 覆盖掉后端已有的名字。
    /// `nonce` 是明文随机数,后端比对令牌里的 `nonce` 声明 == sha256(nonce) 来挡重放。
    func appleSignIn(
        identityToken: String, fullName: String?, nonce: String = ""
    ) async throws -> (token: String, user: MeUser) {
        var body = ["identity_token": identityToken, "client": Self.client]
        if let fullName, !fullName.trimmingCharacters(in: .whitespaces).isEmpty {
            body["full_name"] = fullName
        }
        if !nonce.isEmpty { body["nonce"] = nonce }
        let signedIn = try decode(
            SignedInResponse.self,
            from: try await post("auth/apple", body: body, authorized: false)
        )
        return (signedIn.token, signedIn.user)
    }

    // MARK: - 账户信息

    func me() async throws -> MeResponse {
        try decode(MeResponse.self, from: try await get("me"))
    }

    func usage(days: Int) async throws -> [UsageDay] {
        struct Envelope: Decodable { var days: [UsageDay] }
        return try decode(Envelope.self, from: try await get("me/usage?days=\(days)")).days
    }

    func sessions() async throws -> [SessionRow] {
        struct Envelope: Decodable { var sessions: [SessionRow] }
        return try decode(Envelope.self, from: try await get("me/sessions")).sessions
    }

    /// 注销账号(App Store 5.1.1(v) 要求 app 内可发起)。
    /// 密码错误后端只回 401 `invalid_credentials` 且**保留会话**,
    /// 所以调用方不能把这条 401 当成「令牌失效」去自动登出。
    /// 纯社交账户没有密码(`has_password == false`):传 nil / 空串,只发 `{}`,
    /// 后端不校验密码,拦截靠客户端的二次确认。
    func deleteAccount(password: String?) async throws {
        var body: [String: String] = [:]
        if let password, !password.isEmpty { body["password"] = password }
        _ = try await send(
            method: "DELETE",
            path: "me",
            body: try JSONSerialization.data(withJSONObject: body),
            authorized: true
        )
    }

    func revokeSession(id: Int) async throws {
        _ = try await send(method: "DELETE", path: "me/sessions/\(id)", body: nil, authorized: true)
    }

    // MARK: - HTTP

    private func get(_ path: String) async throws -> Data {
        try await send(method: "GET", path: path, body: nil, authorized: true)
    }

    @discardableResult
    private func post(_ path: String, body: [String: String], authorized: Bool = true) async throws -> Data {
        try await send(
            method: "POST",
            path: path,
            body: try JSONSerialization.data(withJSONObject: body),
            authorized: authorized
        )
    }

    private func send(method: String, path: String, body: Data?, authorized: Bool) async throws -> Data {
        try await response(method: method, path: path, body: body, authorized: authorized).data
    }

    /// 状态码要留给调用方的路径(设备码轮询要区分 202 与 200)走这条;
    /// 非 2xx 仍然在这里统一抛错,免得每个调用方各判一次。
    private func response(
        method: String, path: String, body: Data?, authorized: Bool
    ) async throws -> (data: Data, status: Int) {
        guard let url = URL(string: "\(baseURL)/\(path)") else { throw AccountError.decoding }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        if authorized {
            // 未登录时直接短路,一个字节都不往外发。
            guard let token = tokenProvider() else { throw AccountError.notSignedIn }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AccountError.decoding }
        guard (200..<300).contains(http.statusCode) else { throw Self.error(status: http.statusCode, body: data) }
        return (data, http.statusCode)
    }

    /// 错误体形状固定为 `{"error":{"message","code"}}`;解不出来就退回原始文本。
    private static func error(status: Int, body: Data) -> AccountError {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let error = object["error"] as? [String: Any],
              let message = error["message"] as? String
        else {
            let text = String(data: body, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .http(status, (text?.isEmpty == false ? text! : "HTTP \(status)"), nil)
        }
        return .http(status, message, error["code"] as? String)
    }

    private func token(from data: Data) throws -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = object["token"] as? String, !token.isEmpty
        else { throw AccountError.decoding }
        return token
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard let value = try? JSONCoding.decoder().decode(type, from: data) else {
            throw AccountError.decoding
        }
        return value
    }
}
