import XCTest
@testable import Axblade

/// 打真实后端(api.chillskill.xyz)的账户回路冒烟,默认跳过。
/// 手动验证:`xcodebuild test … TEST_RUNNER_AXBLADE_LIVE=1 -only-testing:AxbladeTests/LiveAccountSmokeTests`
/// 全程用一次性账号,跑完自己删掉;令牌只在内存,**不碰本机钥匙串**。
final class LiveAccountSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        let markerExists = FileManager.default.fileExists(atPath: NSTemporaryDirectory() + "AXBLADE_LIVE")
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["AXBLADE_LIVE"] != "1" && !markerExists,
            "未设置 AXBLADE_LIVE=1(或容器 tmp 标记文件),跳过真网账户冒烟"
        )
    }

    /// 设备码流程只验到「后端确实签发了一个真实的 GitHub 用户码」为止:
    /// 再往下要人去浏览器点授权,自动化跑不了,**不完成授权**。
    func testGitHubDeviceStartAgainstTheLiveBackend() async throws {
        let device = try await AccountService(tokenProvider: { nil }).githubDeviceStart()

        XCTAssertFalse(device.device_code.isEmpty)
        XCTAssertFalse(device.user_code.isEmpty)
        // GitHub 的用户码形如 5DA3-EC78
        XCTAssertTrue(device.user_code.contains("-"), "用户码形状不对:\(device.user_code)")
        XCTAssertEqual(device.verificationURL?.host, "github.com")
        XCTAssertGreaterThanOrEqual(device.pollInterval, 1)
        print("LIVE github device: user_code=\(device.user_code) " +
              "uri=\(device.verification_uri) interval=\(device.pollInterval)")
    }

    /// 注册 → /me → 密码错误的删除(会话必须保住)→ 删除 → 原密码登录失败。
    func testAccountLifecycleAgainstTheLiveBackend() async throws {
        let stamp = Int(Date().timeIntervalSince1970)
        let email = "macfix+\(stamp)@chillskill.xyz"
        let password = "MacFix-\(stamp)"
        let box = TokenHolder()
        let service = AccountService(tokenProvider: { box.value })

        // 1. 注册:后端回的字段名就叫 token
        let token = try await service.signup(email: email, password: password, displayName: "Mac Fix \(stamp)")
        XCTAssertFalse(token.isEmpty)
        box.value = token

        // 2. /v1/me:客户端写死的 quota key 与时间格式必须对得上
        let me = try await service.me()
        XCTAssertEqual(me.user.email, email)
        XCTAssertEqual(me.user.kind, "user")
        XCTAssertEqual(me.session?.client, "mac", "注册请求带的 client 应当落到会话上")
        let chat = try XCTUnwrap(me.quota["chat"], "quota 里没有 chat")
        let market = try XCTUnwrap(me.quota["market"], "quota 里没有 market")
        XCTAssertEqual(chat.used, 0)
        XCTAssertNotEqual(
            AccountSettingsView.readableTimestamp(chat.reset_at), chat.reset_at,
            "reset_at 解析不了 ISO8601,界面会显示原始字符串:\(chat.reset_at)"
        )
        print("LIVE account: plan=\(me.plan.name) chat=\(chat.used)/\(chat.limit.map(String.init) ?? "∞") " +
              "market=\(market.used)/\(market.limit.map(String.init) ?? "∞") " +
              "models=\(me.permissions.models.map(\.alias)) sources=\(me.permissions.market_sources.map(\.id))")

        // 3. 密码错误的删除:401 invalid_credentials,且会话必须还在
        do {
            try await service.deleteAccount(password: password + "-wrong")
            XCTFail("密码错了不该删成功")
        } catch let error as AccountError {
            XCTAssertEqual(error.statusCode, 401)
            XCTAssertEqual(error.code, "invalid_credentials")
        }
        let stillAlive = try await service.me()
        XCTAssertEqual(stillAlive.user.email, email, "删除失败不该顺手吊销会话")

        // 4. 真删 → 令牌立刻失效
        try await service.deleteAccount(password: password)
        do {
            _ = try await service.me()
            XCTFail("账号已删,令牌不该还能用")
        } catch let error as AccountError {
            XCTAssertEqual(error.statusCode, 401)
        }

        // 5. 原密码再登录:登不进去了
        do {
            _ = try await service.login(email: email, password: password)
            XCTFail("账号已删,不该还能登录")
        } catch let error as AccountError {
            XCTAssertEqual(error.statusCode, 401)
            XCTAssertEqual(error.code, "invalid_credentials")
        }
        print("LIVE account: \(email) 已注册并删除,回路完整")
    }
}

/// 只在内存里存令牌,免得冒烟测试污染本机钥匙串。
private final class TokenHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: String?

    var value: String? {
        get { lock.lock(); defer { lock.unlock() }; return storage }
        set { lock.lock(); defer { lock.unlock() }; storage = newValue }
    }
}
