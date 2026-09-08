import XCTest
@testable import Axblade

/// 后端账户接口(spec 1.4 / 1.5)的请求构造与响应解码。
/// 全程走 `MockHTTPProtocol`,不碰真网、不碰真钥匙串。
final class AccountServiceTests: XCTestCase {
    private func service(token: String? = "axb_token") -> AccountService {
        AccountService(
            session: MockHTTPProtocol.session(),
            baseURL: Backend.baseURL,
            tokenProvider: { token }
        )
    }

    /// spec 1.5 的示例响应,逐字段验证解码。
    private static let meJSON = """
    {
      "user": {"id": 12, "email": "a@b.c", "display_name": "A", "plan": "free",
               "created_at": "2026-08-18T03:00:00Z", "kind": "user"},
      "plan": {"name": "free", "chat_requests_per_day": 50, "market_requests_per_day": 500},
      "quota": {
        "chat":   {"limit": 50,  "used": 3, "remaining": 47,  "reset_at": "2026-08-19T00:00:00Z"},
        "market": {"limit": 500, "used": 0, "remaining": 500, "reset_at": "2026-08-19T00:00:00Z"}
      },
      "permissions": {
        "models": [{"alias": "deepseek", "display_name": "DeepSeek-V4-Flash-0731"}],
        "market_sources": [{"id": "binance", "label": "Binance Spot", "paths": ["ticker/24hr", "klines"]}]
      },
      "session": {"id": 3, "client": "mac", "created_at": "2026-08-18T03:00:00Z"}
    }
    """

    // MARK: - 登录 / 注册

    func testLoginPostsCredentialsWithMacClientAndReturnsToken() async throws {
        MockHTTPProtocol.install([("auth/login", 200, #"{"token":"axb_new","user":{"id":1,"email":"a@b.c","display_name":"A","plan":"free","created_at":"x","kind":"user"}}"#)])

        let token = try await service(token: nil).login(email: "a@b.c", password: "pw12345678")

        XCTAssertEqual(token, "axb_new")
        XCTAssertEqual(MockHTTPProtocol.lastRequestedURLs, ["\(Backend.baseURL)/auth/login"])
        XCTAssertEqual(MockHTTPProtocol.lastRequestMethods, ["POST"])
        let body = try XCTUnwrap(MockHTTPProtocol.lastRequestJSON())
        XCTAssertEqual(body["email"] as? String, "a@b.c")
        XCTAssertEqual(body["password"] as? String, "pw12345678")
        XCTAssertEqual(body["client"] as? String, "mac")
    }

    func testSignupPostsDisplayNameAndReturnsToken() async throws {
        MockHTTPProtocol.install([("auth/signup", 201, #"{"token":"axb_signup","user":{"id":2,"email":"n@b.c","display_name":"N","plan":"free","created_at":"x","kind":"user"}}"#)])

        let token = try await service(token: nil).signup(email: "n@b.c", password: "pw12345678", displayName: "N")

        XCTAssertEqual(token, "axb_signup")
        XCTAssertEqual(MockHTTPProtocol.lastRequestedURLs, ["\(Backend.baseURL)/auth/signup"])
        let body = try XCTUnwrap(MockHTTPProtocol.lastRequestJSON())
        XCTAssertEqual(body["display_name"] as? String, "N")
        XCTAssertEqual(body["client"] as? String, "mac")
    }

    /// 401 的后端文案原样带给用户,客户端不再自己编错误话术。
    func testLoginFailureCarriesServerMessageAndCode() async {
        MockHTTPProtocol.install([
            ("auth/login", 401, #"{"error":{"message":"邮箱或密码错误","code":"invalid_credentials"}}"#)
        ])

        do {
            _ = try await service(token: nil).login(email: "a@b.c", password: "wrong")
            XCTFail("应当抛错")
        } catch let error as AccountError {
            XCTAssertEqual(error, .http(401, "邮箱或密码错误", "invalid_credentials"))
        } catch {
            XCTFail("错误类型不对:\(error)")
        }
    }

    // MARK: - /v1/me

    func testMeDecodesQuotaPermissionsAndSession() async throws {
        MockHTTPProtocol.install([("/me", 200, Self.meJSON)])

        let me = try await service().me()

        XCTAssertEqual(MockHTTPProtocol.lastRequestedURLs, ["\(Backend.baseURL)/me"])
        XCTAssertEqual(MockHTTPProtocol.lastAuthorizationHeaders, ["Bearer axb_token"])
        XCTAssertEqual(me.user.email, "a@b.c")
        XCTAssertEqual(me.user.kind, "user")
        XCTAssertEqual(me.plan.chat_requests_per_day, 50)
        XCTAssertEqual(me.quota["chat"]?.limit, 50)
        XCTAssertEqual(me.quota["chat"]?.used, 3)
        XCTAssertEqual(me.quota["market"]?.remaining, 500)
        XCTAssertEqual(me.permissions.models.first?.alias, "deepseek")
        XCTAssertEqual(me.permissions.models.first?.display_name, "DeepSeek-V4-Flash-0731")
        XCTAssertEqual(me.permissions.market_sources.first?.paths, ["ticker/24hr", "klines"])
        XCTAssertEqual(me.session?.client, "mac")
    }

    /// legacy 主体:email/limit/session 都是 null,不能崩。
    func testMeDecodesLegacyPrincipalWithNulls() async throws {
        MockHTTPProtocol.install([("/me", 200, """
        {"user":{"id":0,"email":null,"display_name":"legacy","plan":"legacy","created_at":"x","kind":"legacy"},
         "plan":{"name":"legacy","chat_requests_per_day":null,"market_requests_per_day":null},
         "quota":{"chat":{"limit":null,"used":7,"remaining":null,"reset_at":"2026-08-19T00:00:00Z"}},
         "permissions":{"models":[],"market_sources":[]},
         "session":null}
        """)])

        let me = try await service().me()

        XCTAssertNil(me.user.email)
        XCTAssertNil(me.plan.chat_requests_per_day)
        XCTAssertNil(me.quota["chat"]?.limit)
        XCTAssertEqual(me.quota["chat"]?.used, 7)
        XCTAssertNil(me.session)
    }

    func testMeWithoutTokenThrowsAndSendsNoRequest() async {
        MockHTTPProtocol.install([("/me", 200, Self.meJSON)])

        do {
            _ = try await service(token: nil).me()
            XCTFail("未登录不该拿到 me")
        } catch let error as AccountError {
            XCTAssertEqual(error, .notSignedIn)
        } catch {
            XCTFail("错误类型不对:\(error)")
        }
        XCTAssertTrue(MockHTTPProtocol.lastRequestedURLs.isEmpty, "未登录不应发出任何请求")
    }

    func testMeDecodingFailureBecomesDecodingError() async {
        MockHTTPProtocol.install([("/me", 200, #"{"unexpected":true}"#)])

        do {
            _ = try await service().me()
            XCTFail("应当抛错")
        } catch let error as AccountError {
            XCTAssertEqual(error, .decoding)
        } catch {
            XCTFail("错误类型不对:\(error)")
        }
    }

    // MARK: - 用量 / 会话

    func testUsageRequestsTheDayWindowAndDecodesDays() async throws {
        MockHTTPProtocol.install([("/me/usage", 200, """
        {"days":[{"day":"2026-08-17","chat_requests":2,"chat_tokens":900,"market_requests":5},
                 {"day":"2026-08-18","chat_requests":1,"chat_tokens":100,"market_requests":0}]}
        """)])

        let days = try await service().usage(days: 30)

        XCTAssertEqual(MockHTTPProtocol.lastRequestedURLs, ["\(Backend.baseURL)/me/usage?days=30"])
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days.first?.day, "2026-08-17")
        XCTAssertEqual(days.first?.chat_tokens, 900)
        XCTAssertEqual(days.last?.id, "2026-08-18")
    }

    func testSessionsDecodeAndRevokeDeletesTheSession() async throws {
        MockHTTPProtocol.install([
            ("/me/sessions", 200, """
            {"sessions":[{"id":3,"client":"mac","created_at":"a","last_used_at":"b","current":true},
                         {"id":4,"client":"web","created_at":"c","last_used_at":"d","current":false}]}
            """)
        ])

        let sessions = try await service().sessions()
        XCTAssertEqual(sessions.map(\.id), [3, 4])
        XCTAssertEqual(sessions.first?.current, true)

        MockHTTPProtocol.install([("/me/sessions/4", 204, "")])
        try await service().revokeSession(id: 4)

        XCTAssertEqual(MockHTTPProtocol.lastRequestedURLs, ["\(Backend.baseURL)/me/sessions/4"])
        XCTAssertEqual(MockHTTPProtocol.lastRequestMethods, ["DELETE"])
    }

    // MARK: - 登出 / 改密

    func testLogoutAndLogoutAllHitTheDocumentedPaths() async throws {
        MockHTTPProtocol.install([("auth/logout_all", 204, ""), ("auth/logout", 204, "")])

        try await service().logout()
        try await service().logoutAll()

        XCTAssertEqual(MockHTTPProtocol.lastRequestedURLs, [
            "\(Backend.baseURL)/auth/logout",
            "\(Backend.baseURL)/auth/logout_all"
        ])
        XCTAssertEqual(MockHTTPProtocol.lastRequestMethods, ["POST", "POST"])
    }

    func testChangePasswordPostsBothPasswords() async throws {
        MockHTTPProtocol.install([("auth/password", 204, "")])

        try await service().changePassword(current: "old12345678", new: "new12345678")

        XCTAssertEqual(MockHTTPProtocol.lastRequestedURLs, ["\(Backend.baseURL)/auth/password"])
        let body = try XCTUnwrap(MockHTTPProtocol.lastRequestJSON())
        XCTAssertEqual(body["current_password"] as? String, "old12345678")
        XCTAssertEqual(body["new_password"] as? String, "new12345678")
    }

    // MARK: - 删除账号(App Store 5.1.1(v))

    func testDeleteAccountSendsThePasswordToDeleteMe() async throws {
        MockHTTPProtocol.install([("/me", 204, "")])

        try await service().deleteAccount(password: "pw12345678")

        XCTAssertEqual(MockHTTPProtocol.lastRequestedURLs, ["\(Backend.baseURL)/me"])
        XCTAssertEqual(MockHTTPProtocol.lastRequestMethods, ["DELETE"])
        XCTAssertEqual(MockHTTPProtocol.lastAuthorizationHeaders, ["Bearer axb_token"])
        let body = try XCTUnwrap(MockHTTPProtocol.lastRequestJSON())
        XCTAssertEqual(body["password"] as? String, "pw12345678")
    }

    /// 密码错了后端只回 401 invalid_credentials,会话必须保留——
    /// 调用方据此判断「不能按 401 自动登出」。
    func testDeleteAccountWithWrongPasswordReportsInvalidCredentials() async {
        MockHTTPProtocol.install([
            ("/me", 401, #"{"error":{"message":"密码错误","code":"invalid_credentials"}}"#)
        ])

        do {
            try await service().deleteAccount(password: "wrong-one")
            XCTFail("应当抛错")
        } catch let error as AccountError {
            XCTAssertEqual(error, .http(401, "密码错误", "invalid_credentials"))
            XCTAssertEqual(error.code, "invalid_credentials")
        } catch {
            XCTFail("错误类型不对:\(error)")
        }
    }

    func testQuotaExceededKeepsBackendMessage() async {
        MockHTTPProtocol.install([
            ("/me", 429, #"{"error":{"message":"今日 AI 对话额度已用完,明天 00:00 重置","code":"quota_exceeded"}}"#)
        ])

        do {
            _ = try await service().me()
            XCTFail("应当抛错")
        } catch let error as AccountError {
            XCTAssertEqual(error, .http(429, "今日 AI 对话额度已用完,明天 00:00 重置", "quota_exceeded"))
            XCTAssertEqual(error.errorDescription, "今日 AI 对话额度已用完,明天 00:00 重置")
        } catch {
            XCTFail("错误类型不对:\(error)")
        }
    }
}

/// 令牌只从 `TokenStore` 来,客户端不再内置任何访问令牌。
final class ChatRequestTokenTests: XCTestCase {
    func testAuthorizationHeaderCarriesTheProvidedToken() throws {
        let request = try OpenAIChatService.buildRequest(
            messages: [ChatMessage(role: .user, content: "hi")],
            model: "deepseek",
            token: "axb_x"
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer axb_x")
    }

    func testNoAuthorizationHeaderWhenSignedOut() throws {
        let request = try OpenAIChatService.buildRequest(
            messages: [ChatMessage(role: .user, content: "hi")],
            model: "deepseek",
            token: nil
        )

        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testBinanceProxyOmitsAuthorizationWhenSignedOut() {
        let request = BinanceMarketService.proxiedRequest("api/v3/klines?symbol=BTCUSDT", token: nil)

        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(request.url?.absoluteString.hasPrefix("\(Backend.baseURL)/market/binance/") == true)
    }

    func testBinanceProxyCarriesTheToken() {
        let request = BinanceMarketService.proxiedRequest("api/v3/klines?symbol=BTCUSDT", token: "axb_y")

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer axb_y")
    }
}

/// 社交登录(spec 1.4b):令牌交换全部经由**我们自己的后端**,
/// 客户端不直接跟 GitHub / Apple 换 token,也不持有任何 client secret。
final class AccountServiceSocialTests: XCTestCase {
    private func service(token: String? = nil) -> AccountService {
        AccountService(
            session: MockHTTPProtocol.session(),
            baseURL: Backend.baseURL,
            tokenProvider: { token }
        )
    }

    private static let userJSON = """
    {"id":12,"email":"a@b.c","display_name":"A","plan":"free","created_at":"t","kind":"user",
     "avatar_url":"https://avatars.example/1.png","providers":["github"],"has_password":false}
    """

    // MARK: - GitHub 设备码

    func testGitHubDeviceStartPostsMacClientAndDecodesTheCode() async throws {
        MockHTTPProtocol.install([("auth/github/device", 200, """
        {"device_code":"dc_1","user_code":"5DA3-EC78",
         "verification_uri":"https://github.com/login/device","expires_in":899,"interval":5}
        """)])

        let device = try await service().githubDeviceStart()

        XCTAssertEqual(MockHTTPProtocol.lastRequestedURLs, ["\(Backend.baseURL)/auth/github/device"])
        XCTAssertEqual(MockHTTPProtocol.lastRequestMethods, ["POST"])
        // 设备码流程是未登录状态发起的,不该带 Authorization。
        XCTAssertEqual(MockHTTPProtocol.lastAuthorizationHeaders, [nil])
        let body = try XCTUnwrap(MockHTTPProtocol.lastRequestJSON())
        XCTAssertEqual(body["client"] as? String, "mac")
        XCTAssertEqual(device.user_code, "5DA3-EC78")
        XCTAssertEqual(device.device_code, "dc_1")
        XCTAssertEqual(device.pollInterval, 5)
    }

    /// 202 = 用户还没在浏览器里授权;interval 非 null 时是后端要求的新轮询间隔。
    func testGitHubPollPendingCarriesTheNewInterval() async throws {
        MockHTTPProtocol.install([("device/poll", 202, #"{"pending":true,"interval":10}"#)])

        let poll = try await service().githubDevicePoll(deviceCode: "dc_1")

        XCTAssertEqual(MockHTTPProtocol.lastRequestedURLs, ["\(Backend.baseURL)/auth/github/device/poll"])
        let body = try XCTUnwrap(MockHTTPProtocol.lastRequestJSON())
        XCTAssertEqual(body["device_code"] as? String, "dc_1")
        XCTAssertEqual(body["client"] as? String, "mac")
        guard case .pending(let interval) = poll else { return XCTFail("应当是 pending:\(poll)") }
        XCTAssertEqual(interval, 10)
    }

    /// interval 为 null 表示「间隔不变」,不能被当成 0。
    func testGitHubPollPendingWithNullIntervalKeepsItNil() async throws {
        MockHTTPProtocol.install([("device/poll", 202, #"{"pending":true,"interval":null}"#)])

        guard case .pending(let interval) = try await service().githubDevicePoll(deviceCode: "dc") else {
            return XCTFail("应当是 pending")
        }
        XCTAssertNil(interval)
    }

    func testGitHubPollSignedInReturnsTokenAndUser() async throws {
        MockHTTPProtocol.install([("device/poll", 200, #"{"token":"axb_gh","user":\#(Self.userJSON)}"#)])

        guard case .signedIn(let token, let user) = try await service().githubDevicePoll(deviceCode: "dc") else {
            return XCTFail("应当是 signedIn")
        }
        XCTAssertEqual(token, "axb_gh")
        XCTAssertEqual(user.providers, ["github"])
        XCTAssertFalse(user.has_password)
        XCTAssertEqual(user.avatar_url, "https://avatars.example/1.png")
    }

    func testGitHubPollExpiredDeviceCodeBecomesHTTPError() async {
        MockHTTPProtocol.install([
            ("device/poll", 410, #"{"error":{"message":"授权码已过期,请重新发起登录","code":"device_code_expired"}}"#)
        ])

        do {
            _ = try await service().githubDevicePoll(deviceCode: "dc")
            XCTFail("应当抛错")
        } catch let error as AccountError {
            XCTAssertEqual(error.statusCode, 410)
            XCTAssertEqual(error.code, "device_code_expired")
            XCTAssertEqual(error.errorDescription, "授权码已过期,请重新发起登录")
        } catch {
            XCTFail("错误类型不对:\(error)")
        }
    }

    func testGitHubPollAccessDeniedBecomesHTTPError() async {
        MockHTTPProtocol.install([
            ("device/poll", 403, #"{"error":{"message":"你在授权页拒绝了本次登录","code":"access_denied"}}"#)
        ])

        do {
            _ = try await service().githubDevicePoll(deviceCode: "dc")
            XCTFail("应当抛错")
        } catch let error as AccountError {
            XCTAssertEqual(error.statusCode, 403)
            XCTAssertEqual(error.code, "access_denied")
        } catch {
            XCTFail("错误类型不对:\(error)")
        }
    }

    func testGitHubPollProviderErrorKeepsBackendMessage() async {
        MockHTTPProtocol.install([
            ("device/poll", 502, #"{"error":{"message":"登录服务暂时不可用:GitHub 返回 incorrect_device_code","code":"provider_error"}}"#)
        ])

        do {
            _ = try await service().githubDevicePoll(deviceCode: "bogus")
            XCTFail("应当抛错")
        } catch let error as AccountError {
            XCTAssertEqual(error.code, "provider_error")
            XCTAssertEqual(error.statusCode, 502)
        } catch {
            XCTFail("错误类型不对:\(error)")
        }
    }

    // MARK: - Apple

    func testAppleSignInPostsIdentityTokenAndFullName() async throws {
        MockHTTPProtocol.install([("auth/apple", 200, #"{"token":"axb_apple","user":\#(Self.userJSON)}"#)])

        let (token, user) = try await service().appleSignIn(identityToken: "eyJ.a.b", fullName: "张 三")

        XCTAssertEqual(MockHTTPProtocol.lastRequestedURLs, ["\(Backend.baseURL)/auth/apple"])
        XCTAssertEqual(MockHTTPProtocol.lastRequestMethods, ["POST"])
        let body = try XCTUnwrap(MockHTTPProtocol.lastRequestJSON())
        XCTAssertEqual(body["identity_token"] as? String, "eyJ.a.b")
        XCTAssertEqual(body["full_name"] as? String, "张 三")
        XCTAssertEqual(body["client"] as? String, "mac")
        XCTAssertEqual(token, "axb_apple")
        XCTAssertEqual(user.id, 12)
    }

    /// Apple 只在**首次**授权时给姓名,之后是 nil——不能发一个空 full_name 把后端的名字覆盖掉。
    func testAppleSignInOmitsFullNameWhenAbsent() async throws {
        MockHTTPProtocol.install([("auth/apple", 200, #"{"token":"axb_apple","user":\#(Self.userJSON)}"#)])

        _ = try await service().appleSignIn(identityToken: "eyJ.a.b", fullName: nil)

        let body = try XCTUnwrap(MockHTTPProtocol.lastRequestJSON())
        XCTAssertNil(body["full_name"])
    }

    func testAppleSignInInvalidTokenCarriesBackendMessage() async {
        MockHTTPProtocol.install([
            ("auth/apple", 401, #"{"error":{"message":"Apple 身份令牌无效或已过期,请重新登录","code":"invalid_identity_token"}}"#)
        ])

        do {
            _ = try await service().appleSignIn(identityToken: "bogus", fullName: nil)
            XCTFail("应当抛错")
        } catch let error as AccountError {
            XCTAssertEqual(error.code, "invalid_identity_token")
            XCTAssertEqual(error.statusCode, 401)
        } catch {
            XCTFail("错误类型不对:\(error)")
        }
    }

    // MARK: - 无密码账户

    /// 纯社交账户没有密码:删号只发 `{}`,后端不校验密码(客户端做二次确认)。
    func testDeleteAccountWithoutPasswordSendsEmptyBody() async throws {
        MockHTTPProtocol.install([("/me", 204, "")])

        try await AccountService(
            session: MockHTTPProtocol.session(), baseURL: Backend.baseURL, tokenProvider: { "axb_t" }
        ).deleteAccount(password: nil)

        XCTAssertEqual(MockHTTPProtocol.lastRequestMethods, ["DELETE"])
        let body = try XCTUnwrap(MockHTTPProtocol.lastRequestJSON())
        XCTAssertTrue(body.isEmpty, "无密码账户不该带 password 字段:\(body)")
    }

    func testDeleteAccountWithEmptyPasswordAlsoSendsEmptyBody() async throws {
        MockHTTPProtocol.install([("/me", 204, "")])

        try await AccountService(
            session: MockHTTPProtocol.session(), baseURL: Backend.baseURL, tokenProvider: { "axb_t" }
        ).deleteAccount(password: "")

        let body = try XCTUnwrap(MockHTTPProtocol.lastRequestJSON())
        XCTAssertTrue(body.isEmpty)
    }

    /// 首次设密:current_password 传空串,后端据此放行。
    func testSetPasswordSendsEmptyCurrentPassword() async throws {
        MockHTTPProtocol.install([("auth/password", 204, "")])

        try await AccountService(
            session: MockHTTPProtocol.session(), baseURL: Backend.baseURL, tokenProvider: { "axb_t" }
        ).changePassword(current: "", new: "new12345678")

        let body = try XCTUnwrap(MockHTTPProtocol.lastRequestJSON())
        XCTAssertEqual(body["current_password"] as? String, "")
        XCTAssertEqual(body["new_password"] as? String, "new12345678")
    }
}

/// 安全评审后新增的后端约定(backend 43c5de9)。
final class AccountServiceSocialHardeningTests: XCTestCase {
    private func service(token: String? = nil) -> AccountService {
        AccountService(
            session: MockHTTPProtocol.session(), baseURL: Backend.baseURL, tokenProvider: { token }
        )
    }

    private static let userJSON = """
    {"id":12,"email":"a@b.c","display_name":"A","plan":"free","created_at":"t","kind":"user",
     "avatar_url":"","providers":["apple"],"has_password":false}
    """

    /// 明文 nonce 进请求体,后端拿它比对令牌里的 sha256 声明。
    func testAppleSignInSendsThePlaintextNonce() async throws {
        MockHTTPProtocol.install([("auth/apple", 200, #"{"token":"axb_apple","user":\#(Self.userJSON)}"#)])
        let nonce = AppleNonce.make()

        _ = try await service().appleSignIn(identityToken: "eyJ.a.b", fullName: nil, nonce: nonce.raw)

        let body = try XCTUnwrap(MockHTTPProtocol.lastRequestJSON())
        XCTAssertEqual(body["nonce"] as? String, nonce.raw)
        XCTAssertNotEqual(body["nonce"] as? String, nonce.hashed, "发给后端的必须是明文,不是哈希")
    }

    func testAppleSignInOmitsAnEmptyNonce() async throws {
        MockHTTPProtocol.install([("auth/apple", 200, #"{"token":"axb_apple","user":\#(Self.userJSON)}"#)])

        _ = try await service().appleSignIn(identityToken: "eyJ.a.b", fullName: nil, nonce: "")

        XCTAssertNil(try XCTUnwrap(MockHTTPProtocol.lastRequestJSON())["nonce"])
    }

    /// 409:这个邮箱已经用密码注册过,社交 provider 不能自动认领它。
    func testEmailAlreadyRegisteredWithPasswordSurfacesAs409() async {
        MockHTTPProtocol.install([("auth/apple", 409, """
        {"error":{"message":"该邮箱已用密码注册:请先用邮箱密码登录(后续可在账户页绑定第三方登录)",
                  "code":"email_registered_with_password"}}
        """)])

        do {
            _ = try await service().appleSignIn(identityToken: "eyJ", fullName: nil, nonce: "n")
            XCTFail("应当抛错")
        } catch let error as AccountError {
            XCTAssertEqual(error.statusCode, 409)
            XCTAssertEqual(error.code, "email_registered_with_password")
            XCTAssertTrue(error.errorDescription?.contains("已用密码注册") == true)
        } catch {
            XCTFail("错误类型不对:\(error)")
        }
    }

    /// 400:设备码后端不认了(GitHub 的 incorrect_device_code),客户端要重新发起。
    func testInvalidDeviceCodeSurfacesAs400() async {
        MockHTTPProtocol.install([
            ("device/poll", 400, #"{"error":{"message":"设备码无效,请重新发起登录","code":"invalid_device_code"}}"#)
        ])

        do {
            _ = try await service().githubDevicePoll(deviceCode: "stale")
            XCTFail("应当抛错")
        } catch let error as AccountError {
            XCTAssertEqual(error.statusCode, 400)
            XCTAssertEqual(error.code, "invalid_device_code")
        } catch {
            XCTFail("错误类型不对:\(error)")
        }
    }

    /// 403 reauth_required:无密码账户的设密 / 删号要求刚登录过的会话。
    func testReauthRequiredOnSetPasswordAndDelete() async {
        for path in ["auth/password", "/me"] {
            MockHTTPProtocol.install([(path, 403, """
            {"error":{"message":"为了安全,此操作需要刚登录过的会话:请重新登录后再试","code":"reauth_required"}}
            """)])
            let service = AccountService(
                session: MockHTTPProtocol.session(), baseURL: Backend.baseURL, tokenProvider: { "axb_t" }
            )

            do {
                if path == "auth/password" {
                    try await service.changePassword(current: "", new: "new12345678")
                } else {
                    try await service.deleteAccount(password: nil)
                }
                XCTFail("\(path) 应当抛错")
            } catch let error as AccountError {
                XCTAssertEqual(error.statusCode, 403)
                XCTAssertEqual(error.code, "reauth_required")
            } catch {
                XCTFail("错误类型不对:\(error)")
            }
        }
    }
}
