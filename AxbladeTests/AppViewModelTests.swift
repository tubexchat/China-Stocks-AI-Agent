import XCTest
import AuthenticationServices
@testable import Axblade

/// 记录服务收到了什么、按脚本吐增量的假 ChatService。
private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ChatMessage] = []
    private var model = ""

    var received: [ChatMessage] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    var receivedModel: String {
        lock.lock(); defer { lock.unlock() }
        return model
    }

    func record(_ messages: [ChatMessage], model: String) {
        lock.lock(); defer { lock.unlock() }
        storage = messages
        self.model = model
    }
}

private struct FakeChatService: ChatService {
    var chunks: [String] = []
    var failure: ChatServiceError?
    var holdsOpenForever = false
    let recorder = Recorder()

    func streamReply(
        messages: [ChatMessage],
        model: String
    ) -> AsyncThrowingStream<String, Error> {
        recorder.record(messages, model: model)
        let chunks = chunks
        let failure = failure
        let holdsOpenForever = holdsOpenForever
        return AsyncThrowingStream { continuation in
            let task = Task {
                for chunk in chunks {
                    continuation.yield(chunk)
                    await Task.yield()
                }
                if let failure {
                    continuation.finish(throwing: failure)
                } else if holdsOpenForever {
                    while !Task.isCancelled { await Task.yield() }
                    continuation.finish()
                } else {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// 跨并发域共享的令牌盒子:测试里代替钥匙串。
private final class TokenBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    init(_ value: String?) { self.value = value }

    var token: String? {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func set(_ newValue: String?) -> Bool {
        lock.lock(); defer { lock.unlock() }
        value = newValue
        return true
    }
}

/// 数一数行情服务到底被调用了几次。
private final class MarketCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var calls: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }

    func record() {
        lock.lock(); defer { lock.unlock() }
        count += 1
    }
}

@MainActor
final class AppViewModelTests: XCTestCase {
    private var directory: URL!
    /// 账户测试会写真钥匙串,跑完把机器上原有的令牌放回去。
    private var savedToken: String?

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AxbladeVM-\(UUID().uuidString)", isDirectory: true)
        savedToken = TokenStore.token()
    }

    override func tearDown() {
        TokenStore.set(savedToken)
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    /// 登录态由 `token` 决定,不受本机钥匙串影响;默认已登录,聊天路径才走得通。
    /// 令牌读写都走内存盒子(宿主的钥匙串权限时有时无,不能让它决定测试成败)。
    /// 启动时那次 `refreshMe` 在这里取消,免得后台请求污染 mock 的记录。
    private func makeViewModel(
        service: FakeChatService = FakeChatService(chunks: ["a", "b"]),
        token: String? = "test-token",
        tokenWriter: (@Sendable (String?) -> Bool)? = nil,
        data: StubDataProvider = StubDataProvider()
    ) -> AppViewModel {
        let box = TokenBox(token)
        let viewModel = AppViewModel(
            store: ConversationStore(directory: directory),
            service: service,
            data: data,
            accountService: AccountService(
                session: MockHTTPProtocol.session(),
                baseURL: Backend.baseURL,
                tokenProvider: { box.token }
            ),
            researchStore: MarketResearchStore(directory: directory.appendingPathComponent("research"))
        )
        viewModel.tokenWriter = tokenWriter ?? { box.set($0) }
        viewModel.accountTask?.cancel()
        return viewModel
    }

    /// spec 1.5 的 /v1/me 示例。
    private static let meJSON = """
    {"user":{"id":12,"email":"a@b.c","display_name":"A","plan":"free","created_at":"t","kind":"user"},
     "plan":{"name":"free","chat_requests_per_day":50,"market_requests_per_day":500},
     "quota":{"chat":{"limit":50,"used":3,"remaining":47,"reset_at":"r"},
              "market":{"limit":500,"used":0,"remaining":500,"reset_at":"r"}},
     "permissions":{"models":[{"alias":"deepseek","display_name":"DeepSeek-V4-Flash-0731"}],
                    "market_sources":[{"id":"binance","label":"Binance Spot","paths":["klines"]}]},
     "session":{"id":3,"client":"mac","created_at":"t"}}
    """

    // MARK: - 发送

    func testStreamedChunksLandInOneAssistantMessage() async {
        let viewModel = makeViewModel()
        viewModel.draft = "你好"

        viewModel.send()
        await viewModel.streamingTask?.value

        XCTAssertEqual(viewModel.current?.messages.count, 2)
        XCTAssertEqual(viewModel.current?.messages.first?.role, .user)
        XCTAssertEqual(viewModel.current?.messages.first?.content, "你好")
        XCTAssertEqual(viewModel.current?.messages.last?.role, .assistant)
        XCTAssertEqual(viewModel.current?.messages.last?.content, "ab")
        XCTAssertEqual(viewModel.current?.messages.last?.isError, false)
    }

    func testStreamingFlagResetsAndDraftClears() async {
        let viewModel = makeViewModel()
        viewModel.draft = "你好"

        viewModel.send()
        XCTAssertTrue(viewModel.isStreaming)
        XCTAssertEqual(viewModel.draft, "")

        await viewModel.streamingTask?.value
        XCTAssertFalse(viewModel.isStreaming)
    }

    func testFirstUserMessageBecomesTheTitle() async {
        let viewModel = makeViewModel()
        viewModel.draft = "帮我写一个快速排序"

        viewModel.send()
        await viewModel.streamingTask?.value

        XCTAssertEqual(viewModel.current?.title, "帮我写一个快速排序")
    }

    func testLongTitleIsTruncated() async {
        let viewModel = makeViewModel()
        viewModel.draft = String(repeating: "长", count: 40)

        viewModel.send()
        await viewModel.streamingTask?.value

        XCTAssertEqual(viewModel.current?.title, String(repeating: "长", count: 20) + "…")
    }

    func testBlankDraftSendsNothing() async {
        let viewModel = makeViewModel()
        viewModel.draft = "   \n "

        viewModel.send()
        await viewModel.streamingTask?.value

        XCTAssertEqual(viewModel.current?.messages.count, 0)
        XCTAssertFalse(viewModel.isStreaming)
    }

    func testConversationSurvivesRelaunch() async {
        let viewModel = makeViewModel()
        viewModel.draft = "你好"

        viewModel.send()
        await viewModel.streamingTask?.value

        let reloaded = ConversationStore(directory: directory).loadConversations()
        XCTAssertEqual(reloaded.first?.messages.last?.content, "ab")
    }

    // MARK: - 出错路径

    func testStreamFailureBecomesAnErrorMessage() async {
        let viewModel = makeViewModel(service: FakeChatService(failure: .http(401, "unauthorized")))
        viewModel.draft = "你好"

        viewModel.send()
        await viewModel.streamingTask?.value

        let last = viewModel.current?.messages.last
        XCTAssertEqual(last?.isError, true)
        XCTAssertEqual(last?.content, ChatServiceError.http(401, "unauthorized").errorDescription)
        XCTAssertFalse(viewModel.isStreaming)
    }

    func testPartialOutputIsKeptWhenTheStreamFailsMidway() async {
        let viewModel = makeViewModel(
            service: FakeChatService(chunks: ["半句"], failure: .stream("服务繁忙"))
        )
        viewModel.draft = "你好"

        viewModel.send()
        await viewModel.streamingTask?.value

        let contents = viewModel.current?.messages.map(\.content)
        XCTAssertEqual(contents?.dropFirst().first, "半句")
        XCTAssertEqual(viewModel.current?.messages.last?.isError, true)
    }

    func testErrorMessagesAreNotSentBackToTheModel() async {
        let service = FakeChatService(chunks: ["ok"])
        let viewModel = makeViewModel(service: FakeChatService(failure: .stream("崩了")))
        viewModel.draft = "第一次"
        viewModel.send()
        await viewModel.streamingTask?.value

        viewModel.service = service
        viewModel.draft = "第二次"
        viewModel.send()
        await viewModel.streamingTask?.value

        XCTAssertEqual(service.recorder.received.filter { $0.role != .system }.map(\.content), ["第一次", "第二次"])
    }

    // MARK: - 停止

    func testStopStreamingKeepsWhatArrivedSoFar() async {
        let viewModel = makeViewModel(
            service: FakeChatService(chunks: ["写到一半"], holdsOpenForever: true)
        )
        viewModel.draft = "你好"
        viewModel.send()

        while viewModel.current?.messages.last?.content.isEmpty != false {
            await Task.yield()
        }
        viewModel.stopStreaming()
        await viewModel.streamingTask?.value

        XCTAssertFalse(viewModel.isStreaming)
        XCTAssertEqual(viewModel.current?.messages.last?.content, "写到一半")
        XCTAssertEqual(viewModel.current?.messages.last?.isError, false)
    }

    // MARK: - 会话管理

    func testNewConversationBecomesSelected() async {
        let viewModel = makeViewModel()
        viewModel.draft = "先聊点什么"
        viewModel.send()
        await viewModel.streamingTask?.value
        let first = viewModel.selectedID

        viewModel.newConversation()

        XCTAssertNotEqual(viewModel.selectedID, first)
        XCTAssertEqual(viewModel.conversations.count, 2)
        XCTAssertEqual(viewModel.current?.messages.count, 0)
    }

    func testEmptyConversationsAreNotDuplicated() {
        let viewModel = makeViewModel()
        let id = viewModel.selectedID

        viewModel.newConversation()
        viewModel.newConversation()

        XCTAssertEqual(viewModel.conversations.count, 1)
        XCTAssertEqual(viewModel.selectedID, id)
    }

    func testDeletingSelectedConversationSelectsAnother() async {
        let viewModel = makeViewModel()
        viewModel.draft = "第一个"
        viewModel.send()
        await viewModel.streamingTask?.value
        let first = try! XCTUnwrap(viewModel.selectedID)
        viewModel.newConversation()

        viewModel.deleteConversation(first)

        XCTAssertEqual(viewModel.conversations.count, 1)
        XCTAssertNotEqual(viewModel.selectedID, first)
        XCTAssertNotNil(viewModel.selectedID)
    }

    func testDeletingTheLastConversationLeavesAFreshOne() {
        let viewModel = makeViewModel()
        let id = try! XCTUnwrap(viewModel.selectedID)

        viewModel.deleteConversation(id)

        XCTAssertEqual(viewModel.conversations.count, 1)
        XCTAssertEqual(viewModel.current?.messages.count, 0)
    }

    func testRenamingIgnoresBlankTitles() {
        let viewModel = makeViewModel()
        let id = try! XCTUnwrap(viewModel.selectedID)

        viewModel.renameConversation(id, to: "  Swift 并发  ")
        XCTAssertEqual(viewModel.current?.title, "Swift 并发")

        viewModel.renameConversation(id, to: "   ")
        XCTAssertEqual(viewModel.current?.title, "Swift 并发")
    }

    func testConversationsAreSortedByRecentActivity() async {
        let viewModel = makeViewModel()
        viewModel.draft = "旧的"
        viewModel.send()
        await viewModel.streamingTask?.value
        viewModel.newConversation()
        viewModel.draft = "新的"
        viewModel.send()
        await viewModel.streamingTask?.value

        XCTAssertEqual(viewModel.conversations.first?.title, "新的")
    }

    // MARK: - 行情附加

    private static let sampleSnapshot = MarketSnapshot(
        symbol: "600519.SH", name: "贵州茅台",
        price: 1309.3, changePercent: -0.51,
        closes: [], fetchedAt: Date(timeIntervalSince1970: 1_786_500_000)
    )

    func testAttachmentBlocksAreAppendedAfterUserText() async {
        let service = FakeChatService(chunks: ["ok"])
        let viewModel = makeViewModel(service: service)
        viewModel.attach(Self.sampleSnapshot)
        viewModel.draft = "帮我分析走势"

        viewModel.send()
        await viewModel.streamingTask?.value

        let sent = service.recorder.received.first { $0.role == .user }?.content ?? ""
        XCTAssertTrue(sent.hasPrefix("帮我分析走势\n\n【A股行情 · 600519.SH(贵州茅台)"), sent)
        XCTAssertEqual(viewModel.current?.messages.first?.content, "帮我分析走势", "界面上只显示用户文字")
        XCTAssertEqual(viewModel.current?.messages.first?.contextLabels, ["600519.SH 贵州茅台"])
        XCTAssertEqual(viewModel.current?.title, "帮我分析走势")   // 标题不吃数据块
        XCTAssertTrue(viewModel.pendingAttachments.isEmpty)        // 发送后清空
    }

    func testAttachmentsAloneCanBeSentAndTitleUsesSymbol() async {
        let viewModel = makeViewModel()
        viewModel.attach(Self.sampleSnapshot)
        viewModel.draft = ""

        viewModel.send()
        await viewModel.streamingTask?.value

        XCTAssertEqual(viewModel.current?.messages.first?.role, .user)
        XCTAssertEqual(viewModel.current?.messages.first?.content, "")
        XCTAssertTrue(viewModel.current?.messages.first?.outboundContent.hasPrefix("【A股行情") == true)
        XCTAssertEqual(viewModel.current?.title, "贵州茅台")
    }

    func testRemoveAttachment() {
        let viewModel = makeViewModel()
        viewModel.attach(Self.sampleSnapshot)

        viewModel.removeAttachment(id: Self.sampleSnapshot.id)

        XCTAssertTrue(viewModel.pendingAttachments.isEmpty)
    }

    func testFetchSnapshotResolvesNameAndCloses() async throws {
        let viewModel = makeViewModel()

        let snapshot = try await viewModel.fetchSnapshot(symbol: "600519")

        XCTAssertEqual(snapshot.symbol, "600519.SH")
        XCTAssertEqual(snapshot.name, "贵州茅台")
        XCTAssertEqual(snapshot.price, 1309.3)
        XCTAssertEqual(snapshot.closes.count, 30)
    }

    func testFetchSnapshotRejectsNonAShareSymbols() async {
        let viewModel = makeViewModel()
        do {
            _ = try await viewModel.fetchSnapshot(symbol: "AAPL")
            XCTFail("美股代码不该通过")
        } catch let error as FuyaoError {
            XCTAssertEqual(error, .api(code: 3001, message: String(format: viewModel.text.marketInvalidSymbolFormat, "AAPL")))
        } catch {
            XCTFail("错误类型不对:\(error)")
        }
    }

    // MARK: - 智能体上下文

    func testAgentAttachesLiveDataByIntentAndSystemPrompt() async {
        let service = FakeChatService(chunks: ["ok"])
        let stub = StubDataProvider()
        let viewModel = makeViewModel(service: service, data: stub)
        viewModel.draft = "今天涨停情绪怎么样"

        viewModel.send()
        await viewModel.streamingTask?.value

        let received = service.recorder.received
        XCTAssertEqual(received.first?.role, .system)
        XCTAssertTrue(received.first?.content.contains("A股智能体") == true)
        let user = received.first { $0.role == .user }
        XCTAssertTrue(user?.content.hasPrefix("今天涨停情绪怎么样\n\n【涨停情绪市场脉冲") == true, user?.content ?? "")
        XCTAssertEqual(viewModel.current?.messages.first?.contextLabels, ["涨停情绪"])
        XCTAssertEqual(viewModel.current?.messages.first?.content, "今天涨停情绪怎么样")
        XCTAssertEqual(stub.count("limitUpPool"), 1)
    }

    func testAgentAutoContextCanBeDisabled() async {
        let service = FakeChatService(chunks: ["ok"])
        let stub = StubDataProvider()
        let viewModel = makeViewModel(service: service, data: stub)
        viewModel.settings.agentAutoContext = false
        viewModel.draft = "今天涨停情绪怎么样"

        viewModel.send()
        await viewModel.streamingTask?.value

        XCTAssertTrue(stub.calls.isEmpty)
        XCTAssertEqual(service.recorder.received.first { $0.role == .user }?.content, "今天涨停情绪怎么样")
        XCTAssertEqual(ConversationStore(directory: directory).loadSettings().agentAutoContext, false)
    }

    func testAgentReusesOpenModuleReport() async {
        let service = FakeChatService(chunks: ["ok"])
        let stub = StubDataProvider()
        let viewModel = makeViewModel(service: service, data: stub)
        viewModel.limitUpPulse.load(date: ShanghaiDate.string(Date()))
        await viewModel.limitUpPulse.task?.value
        XCTAssertNotNil(viewModel.limitUpPulse.report)
        let before = stub.count("limitUpPool")
        viewModel.draft = "涨停情绪"

        viewModel.send()
        await viewModel.streamingTask?.value

        XCTAssertEqual(stub.count("limitUpPool"), before, "模块页已经有报告,不重复拉")
        XCTAssertEqual(viewModel.current?.messages.first?.contextLabels, ["涨停情绪"])
    }

    func testAttachModuleReportGoesOutAsBlock() async {
        let service = FakeChatService(chunks: ["ok"])
        let viewModel = makeViewModel(service: service)
        viewModel.settings.agentAutoContext = false
        viewModel.attachReport("【热度报告】共振 3 只", label: "市场热度与飙升雷达")
        XCTAssertEqual(viewModel.pendingAttachments.first?.chipText, "市场热度与飙升雷达")

        viewModel.send()
        await viewModel.streamingTask?.value

        XCTAssertEqual(service.recorder.received.first { $0.role == .user }?.content, "【热度报告】共振 3 只")
        XCTAssertEqual(viewModel.current?.title, "市场热度与飙升雷达")
    }

    // MARK: - 模块工作区

    func testAnalyzeJumpsToChatAndSendsReportInFreshConversation() async {
        let service = FakeChatService(chunks: ["解读完毕"])
        let viewModel = makeViewModel(service: service)
        viewModel.draft = "旧草稿"
        viewModel.openModule(.limitUpPulse)
        XCTAssertEqual(viewModel.workspace, .modules)
        XCTAssertEqual(viewModel.selectedModule, .limitUpPulse)

        viewModel.analyze(report: "【历史回测 · A股 · 600519.SH】策略收益 +12%")
        await viewModel.streamingTask?.value

        XCTAssertEqual(viewModel.workspace, .chat)
        let first = viewModel.current?.messages.first
        XCTAssertEqual(first?.role, .user)
        XCTAssertTrue(first?.content.contains("请解读以下盘面数据") == true)
        XCTAssertTrue(first?.content.contains("策略收益 +12%") == true)
        XCTAssertEqual(viewModel.current?.messages.last?.content, "解读完毕")
        XCTAssertEqual(viewModel.draft, "旧草稿", "不应吃掉用户没发的草稿")
    }

    func testAnalyzeStartsFromFreshConversation() async {
        let viewModel = makeViewModel()
        viewModel.draft = "第一句"
        viewModel.send()
        await viewModel.streamingTask?.value
        let existing = viewModel.selectedID

        viewModel.analyze(report: "报告")
        await viewModel.streamingTask?.value

        XCTAssertNotEqual(viewModel.selectedID, existing)
        XCTAssertEqual(viewModel.conversations.count, 2)
    }

    // MARK: - 账户

    func testSignOutLocallyClearsAccountAndFile() throws {
        let store = ConversationStore(directory: directory)
        try store.saveAccount(UserAccount(email: "a@b.c", displayName: "N", plan: "free"))
        let viewModel = makeViewModel()
        XCTAssertNotNil(viewModel.account)

        viewModel.signOutLocally()

        XCTAssertNil(viewModel.account)
        XCTAssertNil(ConversationStore(directory: directory).loadAccount())
    }

    /// 未登录不许发网络:直接落一条「请先登录」的报错气泡。
    func testSendWithoutSignInAppendsSignInRequiredAndSkipsTheService() async {
        let service = FakeChatService(chunks: ["不该被调用"])
        let viewModel = makeViewModel(service: service, token: nil)
        viewModel.draft = "你好"

        viewModel.send()
        await viewModel.streamingTask?.value

        XCTAssertTrue(service.recorder.received.isEmpty, "未登录不该调用 ChatService")
        XCTAssertEqual(viewModel.current?.messages.last?.isError, true)
        XCTAssertEqual(viewModel.current?.messages.last?.content, viewModel.text.signInRequired)
        XCTAssertFalse(viewModel.isStreaming)
    }

    func testSignInStoresAccountFromMeAndClearsError() async {
        MockHTTPProtocol.install([
            ("auth/login", 200, #"{"token":"axb_new","user":{"id":12,"email":"a@b.c","display_name":"A","plan":"free","created_at":"t","kind":"user"}}"#),
            ("/me", 200, Self.meJSON)
        ])
        let viewModel = makeViewModel(token: nil)

        await viewModel.signIn(email: "a@b.c", password: "pw12345678")

        XCTAssertEqual(viewModel.account?.email, "a@b.c")
        XCTAssertEqual(viewModel.account?.plan, "free")
        XCTAssertEqual(viewModel.me?.quota["chat"]?.limit, 50)
        XCTAssertNil(viewModel.authError)
        XCTAssertFalse(viewModel.isAuthBusy)
        XCTAssertEqual(ConversationStore(directory: directory).loadAccount()?.email, "a@b.c")
    }

    /// 令牌只落钥匙串,不进 account.json。
    func testSignInPutsTheTokenInTheKeychain() async throws {
        try skipIfKeychainUnavailable()
        MockHTTPProtocol.install([
            ("auth/login", 200, #"{"token":"axb_keychain","user":{"id":12,"email":"a@b.c","display_name":"A","plan":"free","created_at":"t","kind":"user"}}"#),
            ("/me", 200, Self.meJSON)
        ])
        let viewModel = makeViewModel(token: nil)
        viewModel.tokenWriter = { TokenStore.set($0) }   // 这条测的就是真钥匙串那条路

        await viewModel.signIn(email: "a@b.c", password: "pw12345678")

        XCTAssertEqual(TokenStore.token(), "axb_keychain")
        XCTAssertTrue(viewModel.isSignedIn)
    }

    /// 登录时借用的令牌不能钉回 service:否则登出清了钥匙串,
    /// tokenProvider 还捧着旧令牌,请求会一直带着已作废的令牌。
    /// 这里的写入口故意不落地,tokenProvider 就该保持 nil。
    func testSignInDoesNotPinTheIssuedTokenIntoTheService() async {
        MockHTTPProtocol.install([
            ("auth/login", 200, #"{"token":"axb_new","user":{"id":12,"email":"a@b.c","display_name":"A","plan":"free","created_at":"t","kind":"user"}}"#),
            ("/me", 200, Self.meJSON)
        ])
        let viewModel = makeViewModel(token: nil, tokenWriter: { _ in true })

        await viewModel.signIn(email: "a@b.c", password: "pw12345678")

        XCTAssertEqual(viewModel.account?.email, "a@b.c")
        XCTAssertNil(viewModel.accountService.tokenProvider(), "令牌来源被登录改写了")
    }

    /// 钥匙串写不进去就不能报「登录成功」——否则界面显示已登录、请求却没令牌。
    func testSignInSurfacesAFailedTokenWrite() async {
        MockHTTPProtocol.install([
            ("auth/login", 200, #"{"token":"axb_new","user":{"id":12,"email":"a@b.c","display_name":"A","plan":"free","created_at":"t","kind":"user"}}"#),
            ("/me", 200, Self.meJSON)
        ])
        let viewModel = makeViewModel(token: nil, tokenWriter: { _ in false })

        await viewModel.signIn(email: "a@b.c", password: "pw12345678")

        XCTAssertNil(viewModel.account)
        XCTAssertFalse(viewModel.isSignedIn)
        XCTAssertEqual(viewModel.authError, viewModel.text.keychainWriteFailed)
    }

    func testSignOutLocallyFlipsIsSignedInImmediately() async {
        MockHTTPProtocol.install([
            ("auth/login", 200, #"{"token":"axb_new","user":{"id":12,"email":"a@b.c","display_name":"A","plan":"free","created_at":"t","kind":"user"}}"#),
            ("/me", 200, Self.meJSON)
        ])
        let viewModel = makeViewModel(token: nil)

        await viewModel.signIn(email: "a@b.c", password: "pw12345678")
        XCTAssertTrue(viewModel.isSignedIn)

        viewModel.signOutLocally()

        XCTAssertFalse(viewModel.isSignedIn)
        XCTAssertNil(viewModel.account)
    }

    // MARK: - 删除账号

    func testDeleteAccountClearsEverythingOnSuccess() async throws {
        let store = ConversationStore(directory: directory)
        try store.saveAccount(UserAccount(email: "a@b.c", displayName: "A", plan: "free"))
        MockHTTPProtocol.install([("/me", 204, "")])
        let viewModel = makeViewModel(token: "t")

        try await viewModel.deleteAccount(password: "pw12345678")

        XCTAssertNil(viewModel.account)
        XCTAssertFalse(viewModel.isSignedIn)
        XCTAssertNil(ConversationStore(directory: directory).loadAccount())
    }

    /// 密码错误只是 401,不能顺手把人登出——这是删除流程和其它 401 的关键区别。
    func testDeleteAccountWithWrongPasswordKeepsTheSession() async throws {
        let store = ConversationStore(directory: directory)
        try store.saveAccount(UserAccount(email: "a@b.c", displayName: "A", plan: "free"))
        MockHTTPProtocol.install([
            ("/me", 401, #"{"error":{"message":"密码错误","code":"invalid_credentials"}}"#)
        ])
        let viewModel = makeViewModel(token: "t")

        do {
            try await viewModel.deleteAccount(password: "wrong-one")
            XCTFail("应当抛错")
        } catch let error as AccountError {
            XCTAssertEqual(error.code, "invalid_credentials")
        }

        XCTAssertNotNil(viewModel.account, "密码错误不该把人登出")
        XCTAssertTrue(viewModel.isSignedIn)
        XCTAssertNotNil(ConversationStore(directory: directory).loadAccount())
    }

    // MARK: - 模型权限

    func testModelPickerFollowsAccountPermissions() async {
        MockHTTPProtocol.install([("/me", 200, Self.meJSON)])
        let viewModel = makeViewModel(token: "t")
        viewModel.selectModel("kimi")
        XCTAssertEqual(viewModel.currentModel.alias, "kimi")

        await viewModel.refreshMe()   // meJSON 只授权 deepseek

        XCTAssertEqual(viewModel.availableModels.map(\.alias), ["deepseek"])
        XCTAssertEqual(viewModel.currentModel.alias, "deepseek", "降级后必须重新收敛到有权限的模型")

        viewModel.selectModel("kimi")
        XCTAssertEqual(viewModel.currentModel.alias, "deepseek", "没权限的模型不该选得中")
    }

    /// 未登录/离线拿不到 /me 时,回落到固定模型表,别让选择器空掉。
    func testModelPickerFallsBackToTheStaticListWithoutMe() {
        let viewModel = makeViewModel(token: nil)

        XCTAssertEqual(viewModel.availableModels.map(\.alias), Backend.models.map(\.alias))
    }

    func testSignInFailureShowsTheBackendMessage() async {
        MockHTTPProtocol.install([
            ("auth/login", 401, #"{"error":{"message":"邮箱或密码错误","code":"invalid_credentials"}}"#)
        ])
        let viewModel = makeViewModel(token: nil)

        await viewModel.signIn(email: "a@b.c", password: "wrong")

        XCTAssertNil(viewModel.account)
        XCTAssertEqual(viewModel.authError, "邮箱或密码错误")
        XCTAssertFalse(viewModel.isAuthBusy)
    }

    func testSignUpHitsTheSignupEndpointAndSignsIn() async {
        MockHTTPProtocol.install([
            ("auth/signup", 201, #"{"token":"axb_signup","user":{"id":13,"email":"n@b.c","display_name":"N","plan":"free","created_at":"t","kind":"user"}}"#),
            ("/me", 200, Self.meJSON)
        ])
        let viewModel = makeViewModel(token: nil)

        await viewModel.signUp(email: "n@b.c", password: "pw12345678", displayName: "N")

        XCTAssertTrue(MockHTTPProtocol.lastRequestedURLs.contains("\(Backend.baseURL)/auth/signup"))
        XCTAssertEqual(viewModel.account?.email, "a@b.c")   // 账户信息以 /me 为准
    }

    func testRefreshMeOn401ClearsTheAccount() async throws {
        let store = ConversationStore(directory: directory)
        try store.saveAccount(UserAccount(email: "a@b.c", displayName: "A", plan: "free"))
        MockHTTPProtocol.install([
            ("/me", 401, #"{"error":{"message":"访问令牌缺失或无效","code":"unauthorized"}}"#)
        ])
        let viewModel = makeViewModel(token: "expired")
        XCTAssertNotNil(viewModel.account)

        await viewModel.refreshMe()

        XCTAssertNil(viewModel.account)
        XCTAssertNil(viewModel.me)
        XCTAssertNil(ConversationStore(directory: directory).loadAccount())
    }

    /// 流式聊天拿到 401 说明令牌被吊销了,本地状态跟着清掉。
    func testStreamHTTP401SignsOutLocally() async throws {
        let store = ConversationStore(directory: directory)
        try store.saveAccount(UserAccount(email: "a@b.c", displayName: "A", plan: "free"))
        MockHTTPProtocol.install([("/me", 200, Self.meJSON)])
        let viewModel = makeViewModel(
            service: FakeChatService(failure: .http(401, #"{"error":{"message":"访问令牌缺失或无效","code":"unauthorized"}}"#)),
            token: "revoked"
        )
        viewModel.draft = "你好"

        viewModel.send()
        await viewModel.streamingTask?.value

        XCTAssertNil(viewModel.account)
        XCTAssertEqual(viewModel.current?.messages.last?.isError, true)
    }

    /// 429 原样展示后端文案,不再是一坨 JSON。
    func testQuotaExceededShowsTheBackendMessage() async {
        let viewModel = makeViewModel(
            service: FakeChatService(failure: .http(429, #"{"error":{"message":"今日 AI 对话额度已用完","code":"quota_exceeded"}}"#)),
            token: "t"
        )
        MockHTTPProtocol.install([("/me", 200, Self.meJSON)])
        viewModel.draft = "你好"

        viewModel.send()
        await viewModel.streamingTask?.value

        let last = viewModel.current?.messages.last
        XCTAssertEqual(last?.isError, true)
        XCTAssertTrue(last?.content.contains("今日 AI 对话额度已用完") == true, last?.content ?? "")
        XCTAssertFalse(last?.content.contains("quota_exceeded") == true, "不该把原始 JSON 甩给用户")
    }

    func testSignOutCallsTheBackendThenClearsLocalState() async throws {
        let store = ConversationStore(directory: directory)
        try store.saveAccount(UserAccount(email: "a@b.c", displayName: "A", plan: "free"))
        MockHTTPProtocol.install([("auth/logout", 204, "")])
        let viewModel = makeViewModel(token: "t")

        await viewModel.signOut()

        XCTAssertTrue(MockHTTPProtocol.lastRequestedURLs.contains("\(Backend.baseURL)/auth/logout"))
        XCTAssertNil(viewModel.account)
        XCTAssertNil(ConversationStore(directory: directory).loadAccount())
    }

    /// 启动时若已登录就对一次账,额度/权限立刻反映后台的变更。
    func testLaunchRefreshesMeWhenSignedIn() async {
        MockHTTPProtocol.install([("/me", 200, Self.meJSON)])

        let viewModel = AppViewModel(
            store: ConversationStore(directory: directory),
            service: FakeChatService(),
            accountService: AccountService(
                session: MockHTTPProtocol.session(),
                baseURL: Backend.baseURL,
                tokenProvider: { "launch-token" }
            )
        )
        await viewModel.accountTask?.value

        XCTAssertEqual(viewModel.me?.user.email, "a@b.c")
        XCTAssertEqual(viewModel.account?.plan, "free")
    }

    func testAccountIsLoadedOnLaunch() throws {
        let store = ConversationStore(directory: directory)
        let account = UserAccount(email: "old@b.c", displayName: "老用户", plan: "pro")
        try store.saveAccount(account)

        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.account, account)
    }

    // MARK: - 模型选择

    func testDefaultModelIsDeepSeek() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.currentModel.alias, "deepseek")
        XCTAssertEqual(viewModel.currentModel.displayName, "DeepSeek-V4-Flash-0731")
    }

    func testSelectingModelPersistsAcrossRelaunch() {
        let viewModel = makeViewModel()

        viewModel.selectModel("kimi")

        XCTAssertEqual(viewModel.currentModel.displayName, "Kimi-K2.7-Code")
        XCTAssertEqual(ConversationStore(directory: directory).loadSettings().modelAlias, "kimi")
    }

    func testSelectingUnknownModelIsIgnored() {
        let viewModel = makeViewModel()

        viewModel.selectModel("gpt-4o")

        XCTAssertEqual(viewModel.currentModel.alias, "deepseek")
    }

    func testSendPassesTheSelectedModelToTheService() async {
        let service = FakeChatService(chunks: ["ok"])
        let viewModel = makeViewModel(service: service)
        viewModel.selectModel("kimi")
        viewModel.draft = "你好"

        viewModel.send()
        await viewModel.streamingTask?.value

        XCTAssertEqual(service.recorder.receivedModel, "kimi")
    }

    // MARK: - 语言切换

    func testSelectingLanguagePersistsAndSwitchesStrings() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.settings.language, .zh)
        XCTAssertEqual(viewModel.text.newChat, L10nStrings.zh.newChat)

        viewModel.selectLanguage(.en)

        XCTAssertEqual(viewModel.text.newChat, L10nStrings.en.newChat)
        XCTAssertEqual(ConversationStore(directory: directory).loadSettings().language, .en)
    }

    private func skipIfKeychainUnavailable() throws {
        let probe = "test.probe.\(UUID().uuidString)"
        KeychainStore.setSecret("probe", account: probe)
        let readBack = KeychainStore.secret(account: probe)
        KeychainStore.deleteSecret(account: probe)
        try XCTSkipIf(readBack == nil, "当前构建无法访问钥匙串(ad-hoc 签名 + 沙盒)")
    }

    /// 多 provider 时代的 settings.json 必须能带着数据源开关平滑迁移,不崩、不丢。
    func testLegacyProviderSettingsMigrateToDefaultBackendModel() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacy = """
        {
          "defaultProviderID" : "11111111-2222-3333-4444-555555555555",
          "providers" : [
            {
              "baseURL" : "https://api.deepseek.com/v1",
              "id" : "11111111-2222-3333-4444-555555555555",
              "kind" : "openaiCompatible",
              "model" : "DeepSeek-V4-Flash-0731",
              "name" : "DeepSeek"
            }
          ]
        }
        """
        try Data(legacy.utf8).write(to: directory.appendingPathComponent("settings.json"))

        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.currentModel.alias, "deepseek")
        XCTAssertTrue(viewModel.settings.agentAutoContext)
        XCTAssertEqual(viewModel.settings.sectorTag, "industry")
    }
}

// MARK: - 社交登录(spec 1.4b)

/// 假后端:设备码 → 轮询(先 pending 再签发)→ /me。
/// `/auth/github/device` 是 `/auth/github/device/poll` 的前缀,
/// 路由表按 `contains` 匹配分不开这两条,所以这里按精确路径应答。
private final class FakeAuthBackend: @unchecked Sendable {
    static let userJSON = """
    {"id":12,"email":"a@b.c","display_name":"A","plan":"free","created_at":"t","kind":"user",
     "avatar_url":"https://avatars.example/1.png","providers":["github"],"has_password":false}
    """
    static let meJSON = """
    {"user":\(userJSON),
     "plan":{"name":"free","chat_requests_per_day":50,"market_requests_per_day":500},
     "quota":{"chat":{"limit":50,"used":3,"remaining":47,"reset_at":"r"}},
     "permissions":{"models":[{"alias":"deepseek","display_name":"DeepSeek-V4-Flash-0731"}],
                    "market_sources":[]},
     "session":{"id":3,"client":"mac","created_at":"t"}}
    """

    private let lock = NSLock()
    private var polls = 0
    private var starts = 0
    private var bodies: [String: String] = [:]
    private let pendingPolls: Int
    private let pendingInterval: Int?
    /// 非 nil 时轮询直接以这个错误结束。
    private let pollFailure: (status: Int, body: String)?
    /// 前 N 次轮询回 400 invalid_device_code(客户端应当换一枚设备码重来)。
    private let invalidPolls: Int

    init(pendingPolls: Int = 0, pendingInterval: Int? = nil,
         pollFailure: (status: Int, body: String)? = nil, invalidPolls: Int = 0) {
        self.pendingPolls = pendingPolls
        self.pendingInterval = pendingInterval
        self.pollFailure = pollFailure
        self.invalidPolls = invalidPolls
    }

    var pollCount: Int {
        lock.lock(); defer { lock.unlock() }
        return polls
    }

    /// 申请了几次设备码。
    var deviceStarts: Int {
        lock.lock(); defer { lock.unlock() }
        return starts
    }

    /// 某个路径最后一次收到的请求体(断言 identity_token 用)。
    func body(forPathSuffix suffix: String) -> [String: Any]? {
        lock.lock(); defer { lock.unlock() }
        guard let raw = bodies[suffix] else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]
    }

    func respond(_ request: URLRequest) -> (status: Int, body: String) {
        let url = request.url?.absoluteString ?? ""
        let raw = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""

        if url.hasSuffix("/auth/github/device/poll") {
            lock.lock()
            polls += 1
            let count = polls
            bodies["poll"] = raw
            lock.unlock()
            if count <= invalidPolls {
                return (400, #"{"error":{"message":"设备码无效,请重新发起登录","code":"invalid_device_code"}}"#)
            }
            if let pollFailure { return pollFailure }
            guard count > pendingPolls + invalidPolls else {
                return (202, #"{"pending":true,"interval":\#(pendingInterval.map(String.init) ?? "null")}"#)
            }
            return (200, #"{"token":"axb_gh","user":\#(Self.userJSON)}"#)
        }
        if url.hasSuffix("/auth/github/device") {
            lock.lock(); starts += 1; lock.unlock()
            return (200, """
            {"device_code":"dc_1","user_code":"5DA3-EC78",
             "verification_uri":"https://github.com/login/device","expires_in":899,"interval":5}
            """)
        }
        if url.hasSuffix("/auth/apple") {
            lock.lock(); bodies["apple"] = raw; lock.unlock()
            return (200, #"{"token":"axb_apple","user":\#(Self.userJSON)}"#)
        }
        if url.hasSuffix("/me") { return (200, Self.meJSON) }
        return (404, #"{"error":{"message":"no route \#(url)","code":"not_found"}}"#)
    }
}

/// 记录 view model 打开了哪个网址 / 等了多久,跨并发域安全。
private final class CallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    private var waits: [Double] = []

    var openedURLs: [URL] {
        lock.lock(); defer { lock.unlock() }
        return urls
    }

    var sleptSeconds: [Double] {
        lock.lock(); defer { lock.unlock() }
        return waits
    }

    func open(_ url: URL) {
        lock.lock(); defer { lock.unlock() }
        urls.append(url)
    }

    func sleep(_ seconds: Double) {
        lock.lock(); defer { lock.unlock() }
        waits.append(seconds)
    }
}

@MainActor
final class SocialSignInViewModelTests: XCTestCase {
    private var directory: URL!
    private var savedToken: String?

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AxbladeSocial-\(UUID().uuidString)", isDirectory: true)
        savedToken = TokenStore.token()
    }

    override func tearDown() {
        TokenStore.set(savedToken)
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    /// 未登录起步;令牌写内存盒子,浏览器与 sleep 都是假的。
    private func makeViewModel(box: TokenBox, log: CallLog) -> AppViewModel {
        let viewModel = AppViewModel(
            store: ConversationStore(directory: directory),
            service: FakeChatService(),
            data: StubDataProvider(),
            accountService: AccountService(
                session: MockHTTPProtocol.session(),
                baseURL: Backend.baseURL,
                tokenProvider: { box.token }
            ),
            researchStore: MarketResearchStore(directory: directory.appendingPathComponent("research"))
        )
        viewModel.accountTask?.cancel()
        viewModel.tokenWriter = { box.set($0) }
        viewModel.openURL = { log.open($0) }
        viewModel.sleeper = { log.sleep($0) }
        return viewModel
    }

    // MARK: - GitHub 设备码

    /// pending → signedIn:浏览器被打开、轮询间隔听后端的、令牌落地、账户信息应用。
    func testGitHubDeviceFlowPollsUntilSignedIn() async {
        let backend = FakeAuthBackend(pendingPolls: 1, pendingInterval: 7)
        MockHTTPProtocol.install(responder: { backend.respond($0) })
        let box = TokenBox(nil)
        let log = CallLog()
        let viewModel = makeViewModel(box: box, log: log)

        viewModel.signInWithGitHub()
        await viewModel.signInTask?.value

        XCTAssertEqual(log.openedURLs, [URL(string: "https://github.com/login/device")!])
        XCTAssertEqual(backend.pollCount, 2)
        // 第一轮用设备码给的 5 秒,pending 带回新的 7 秒后照做(slow_down)。
        XCTAssertEqual(log.sleptSeconds, [5, 7])
        XCTAssertEqual(box.token, "axb_gh", "令牌没落地")
        XCTAssertTrue(viewModel.isSignedIn)
        XCTAssertEqual(viewModel.account?.email, "a@b.c")
        XCTAssertEqual(viewModel.me?.user.providers, ["github"])
        XCTAssertNil(viewModel.authProgress, "登录完成后不该还挂着用户码")
        XCTAssertFalse(viewModel.isAuthBusy)
        XCTAssertNil(viewModel.authError)
    }

    /// 轮询期间界面要拿得到用户码;取消之后立刻停轮询、清状态。
    func testCancelSignInStopsPollingAndClearsTheUserCode() async {
        let backend = FakeAuthBackend(pendingPolls: .max)
        MockHTTPProtocol.install(responder: { backend.respond($0) })
        let box = TokenBox(nil)
        let log = CallLog()
        let viewModel = makeViewModel(box: box, log: log)
        viewModel.sleeper = { _ in await Task.yield() }

        viewModel.signInWithGitHub()
        for _ in 0..<2000 where viewModel.authProgress == nil { await Task.yield() }

        XCTAssertEqual(
            viewModel.authProgress,
            .userCode("5DA3-EC78", verificationURL: URL(string: "https://github.com/login/device")!)
        )
        for _ in 0..<2000 where backend.pollCount < 1 { await Task.yield() }
        XCTAssertGreaterThanOrEqual(backend.pollCount, 1, "取消前应当确实在轮询")

        viewModel.cancelSignIn()
        await viewModel.signInTask?.value
        let pollsAtCancel = backend.pollCount
        for _ in 0..<200 { await Task.yield() }

        XCTAssertEqual(backend.pollCount, pollsAtCancel, "取消后还在轮询")
        XCTAssertNil(viewModel.authProgress)
        XCTAssertFalse(viewModel.isAuthBusy)
        XCTAssertFalse(viewModel.isSignedIn)
        XCTAssertNil(box.token)
        XCTAssertNil(viewModel.authError, "用户主动取消不是错误")
    }

    func testGitHubDeviceStartFailureSurfacesTheBackendMessage() async {
        MockHTTPProtocol.install([
            ("auth/github/device", 502, #"{"error":{"message":"登录服务暂时不可用:GitHub 返回 502","code":"provider_error"}}"#)
        ])
        let box = TokenBox(nil)
        let viewModel = makeViewModel(box: box, log: CallLog())

        viewModel.signInWithGitHub()
        await viewModel.signInTask?.value

        XCTAssertEqual(viewModel.authError, "登录服务暂时不可用:GitHub 返回 502")
        XCTAssertFalse(viewModel.isSignedIn)
        XCTAssertFalse(viewModel.isAuthBusy)
        XCTAssertNil(viewModel.authProgress)
    }

    /// 用户在 GitHub 授权页点了拒绝:403 的后端文案原样展示,不留半截登录态。
    func testGitHubAccessDeniedEndsTheFlowWithTheBackendMessage() async {
        let backend = FakeAuthBackend(
            pollFailure: (403, #"{"error":{"message":"你在授权页拒绝了本次登录","code":"access_denied"}}"#)
        )
        MockHTTPProtocol.install(responder: { backend.respond($0) })
        let box = TokenBox(nil)
        let viewModel = makeViewModel(box: box, log: CallLog())

        viewModel.signInWithGitHub()
        await viewModel.signInTask?.value

        XCTAssertEqual(viewModel.authError, "你在授权页拒绝了本次登录")
        XCTAssertEqual(backend.pollCount, 1, "拿到 403 就该停,不能接着轮")
        XCTAssertFalse(viewModel.isSignedIn)
        XCTAssertNil(box.token)
    }

    /// 同一时刻只能有一个登录流程在跑。
    func testSecondSignInIsIgnoredWhileOneIsRunning() async {
        let backend = FakeAuthBackend(pendingPolls: .max)
        MockHTTPProtocol.install(responder: { backend.respond($0) })
        let viewModel = makeViewModel(box: TokenBox(nil), log: CallLog())
        viewModel.sleeper = { _ in await Task.yield() }

        let appleCalls = MarketCallCounter()
        viewModel.appleCredentialProvider = {
            appleCalls.record()
            return AppleCredential(identityToken: "eyJ", fullName: nil)
        }

        viewModel.signInWithGitHub()
        for _ in 0..<2000 where viewModel.authProgress == nil { await Task.yield() }
        viewModel.signInWithApple()
        for _ in 0..<200 { await Task.yield() }

        XCTAssertEqual(appleCalls.calls, 0, "设备码还在轮询时不该又弹 Apple 面板")
        XCTAssertNotNil(viewModel.authProgress, "第二次登录不该顶掉正在跑的那次")
        viewModel.cancelSignIn()
        await viewModel.signInTask?.value
    }

    // MARK: - 安全评审后的新错误(backend 43c5de9)

    /// 400 invalid_device_code:这枚码后端不认了,应当**自动**换一枚重来,不打扰用户。
    func testInvalidDeviceCodeRestartsTheDeviceFlow() async {
        let backend = FakeAuthBackend(invalidPolls: 1)
        MockHTTPProtocol.install(responder: { backend.respond($0) })
        let box = TokenBox(nil)
        let log = CallLog()
        let viewModel = makeViewModel(box: box, log: log)

        viewModel.signInWithGitHub()
        await viewModel.signInTask?.value

        XCTAssertEqual(backend.deviceStarts, 2, "设备码被判无效后应当重新申请一枚")
        XCTAssertEqual(log.openedURLs.count, 2, "新的用户码要重新把授权页打开")
        XCTAssertTrue(viewModel.isSignedIn)
        XCTAssertEqual(box.token, "axb_gh")
        XCTAssertNil(viewModel.authError, "自动重来成功了就不该留错误")
    }

    /// 但不能无限重来:后端一直回 400 时最多再试一次,然后把后端文案交给用户。
    func testInvalidDeviceCodeGivesUpAfterOneRetry() async {
        let backend = FakeAuthBackend(invalidPolls: .max)
        MockHTTPProtocol.install(responder: { backend.respond($0) })
        let viewModel = makeViewModel(box: TokenBox(nil), log: CallLog())

        viewModel.signInWithGitHub()
        await viewModel.signInTask?.value

        XCTAssertEqual(backend.deviceStarts, 2, "最多重来一次")
        XCTAssertEqual(viewModel.authError, "设备码无效,请重新发起登录")
        XCTAssertFalse(viewModel.isSignedIn)
        XCTAssertNil(viewModel.authProgress)
        XCTAssertFalse(viewModel.isAuthBusy)
    }

    /// 409:这个邮箱已经用密码注册过。展开邮箱表单——用户要做的就是改用密码登录。
    func testEmailRegisteredWithPasswordExpandsTheEmailForm() async {
        MockHTTPProtocol.install([("auth/apple", 409, """
        {"error":{"message":"该邮箱已用密码注册:请先用邮箱密码登录","code":"email_registered_with_password"}}
        """)])
        let box = TokenBox(nil)
        let viewModel = makeViewModel(box: box, log: CallLog())
        viewModel.appleCredentialProvider = {
            AppleCredential(identityToken: "eyJ", fullName: nil, nonce: "n")
        }
        XCTAssertFalse(viewModel.isEmailFormExpanded)

        viewModel.signInWithApple()
        await viewModel.signInTask?.value

        XCTAssertEqual(viewModel.authError, "该邮箱已用密码注册:请先用邮箱密码登录")
        XCTAssertTrue(viewModel.isEmailFormExpanded, "得把邮箱表单展开,否则用户不知道往哪走")
        XCTAssertFalse(viewModel.isSignedIn)
        XCTAssertNil(box.token)
    }

    /// GitHub 那条路同样要展开邮箱表单。
    func testGitHubEmailRegisteredWithPasswordAlsoExpandsTheEmailForm() async {
        let backend = FakeAuthBackend(pollFailure: (409, """
        {"error":{"message":"该邮箱已用密码注册:请先用邮箱密码登录","code":"email_registered_with_password"}}
        """))
        MockHTTPProtocol.install(responder: { backend.respond($0) })
        let viewModel = makeViewModel(box: TokenBox(nil), log: CallLog())

        viewModel.signInWithGitHub()
        await viewModel.signInTask?.value

        XCTAssertTrue(viewModel.isEmailFormExpanded)
        XCTAssertEqual(backend.deviceStarts, 1, "409 不是设备码的问题,不该重来")
        XCTAssertFalse(viewModel.isSignedIn)
    }

    /// 403 reauth_required 不是「令牌失效」:会话必须留着,只提示重新登录。
    func testReauthRequiredOnDeleteKeepsTheSession() async {
        MockHTTPProtocol.install([("/me", 403, """
        {"error":{"message":"为了安全,此操作需要刚登录过的会话:请重新登录后再试","code":"reauth_required"}}
        """)])
        let viewModel = makeViewModel(box: TokenBox("axb_t"), log: CallLog())

        do {
            try await viewModel.deleteAccount(password: nil)
            XCTFail("应当抛错")
        } catch {
            XCTAssertTrue(AccountSettingsView.needsReauth(error), "界面据此显示「重新登录」")
            XCTAssertEqual(viewModel.text.describe(error), "为了安全,此操作需要刚登录过的会话:请重新登录后再试")
        }
        XCTAssertTrue(viewModel.isSignedIn, "reauth_required 不能顺手把人登出")
        XCTAssertFalse(viewModel.isAuthBusy)
    }

    func testReauthRequiredOnSetPasswordKeepsTheSession() async {
        MockHTTPProtocol.install([("auth/password", 403, """
        {"error":{"message":"为了安全,此操作需要刚登录过的会话:请重新登录后再试","code":"reauth_required"}}
        """)])
        let viewModel = makeViewModel(box: TokenBox("axb_t"), log: CallLog())

        do {
            try await viewModel.changePassword(current: "", new: "new12345678")
            XCTFail("应当抛错")
        } catch {
            XCTAssertTrue(AccountSettingsView.needsReauth(error))
        }
        XCTAssertTrue(viewModel.isSignedIn)
    }

    /// 「重新登录」按钮做的事:只清本地,回到登录页。
    func testSignOutLocallyReturnsToTheSignInScreen() {
        let box = TokenBox("axb_t")
        let viewModel = makeViewModel(box: box, log: CallLog())

        viewModel.signOutLocally()

        XCTAssertFalse(viewModel.isSignedIn)
        XCTAssertNil(box.token)
        XCTAssertNil(viewModel.me)
    }

    // MARK: - Apple

    func testAppleSignInExchangesTheIdentityTokenForABackendToken() async throws {
        let backend = FakeAuthBackend()
        MockHTTPProtocol.install(responder: { backend.respond($0) })
        let box = TokenBox(nil)
        let viewModel = makeViewModel(box: box, log: CallLog())
        viewModel.appleCredentialProvider = {
            AppleCredential(identityToken: "eyJ.header.payload", fullName: "张 三", nonce: "raw-nonce-123")
        }

        viewModel.signInWithApple()
        await viewModel.signInTask?.value

        let body = try XCTUnwrap(backend.body(forPathSuffix: "apple"))
        XCTAssertEqual(body["identity_token"] as? String, "eyJ.header.payload")
        XCTAssertEqual(body["full_name"] as? String, "张 三")
        XCTAssertEqual(body["client"] as? String, "mac")
        XCTAssertEqual(body["nonce"] as? String, "raw-nonce-123", "防重放的明文 nonce 没带上")
        XCTAssertEqual(box.token, "axb_apple")
        XCTAssertTrue(viewModel.isSignedIn)
        XCTAssertFalse(viewModel.isAuthBusy)
    }

    /// ad-hoc(Debug)构建缺 entitlement 时系统只给 unknown(1000):
    /// 必须翻成「换个登录方式」,而不是把 1000 甩给用户。
    func testAppleSignInWithoutEntitlementExplainsItNeedsASignedBuild() async {
        MockHTTPProtocol.install(responder: { _ in (500, "") })
        let box = TokenBox(nil)
        let viewModel = makeViewModel(box: box, log: CallLog())
        viewModel.appleCredentialProvider = { () async throws -> AppleCredential in
            throw AppleSignInError.needsSignedBuild
        }

        viewModel.signInWithApple()
        await viewModel.signInTask?.value

        XCTAssertEqual(viewModel.authError, L10nStrings.zh.appleNeedsSignedBuild)
        XCTAssertTrue(viewModel.authError?.contains("GitHub") == true, "得告诉用户改用什么")
        XCTAssertFalse(viewModel.isSignedIn)
        XCTAssertNil(box.token)
    }

    /// 用户在系统面板上按取消不是错误,不该弹红字。
    func testAppleSignInCancelIsNotAnError() async {
        MockHTTPProtocol.install(responder: { _ in (500, "") })
        let viewModel = makeViewModel(box: TokenBox(nil), log: CallLog())
        viewModel.appleCredentialProvider = { () async throws -> AppleCredential in
            throw AppleSignInError.canceled
        }

        viewModel.signInWithApple()
        await viewModel.signInTask?.value

        XCTAssertNil(viewModel.authError)
        XCTAssertFalse(viewModel.isAuthBusy)
        XCTAssertFalse(viewModel.isSignedIn)
    }

    func testAppleBackendRejectionShowsTheBackendMessage() async {
        MockHTTPProtocol.install([
            ("auth/apple", 401, #"{"error":{"message":"Apple 身份令牌无效或已过期,请重新登录","code":"invalid_identity_token"}}"#)
        ])
        let viewModel = makeViewModel(box: TokenBox(nil), log: CallLog())
        viewModel.appleCredentialProvider = { AppleCredential(identityToken: "bogus", fullName: nil) }

        viewModel.signInWithApple()
        await viewModel.signInTask?.value

        XCTAssertEqual(viewModel.authError, "Apple 身份令牌无效或已过期,请重新登录")
        XCTAssertFalse(viewModel.isSignedIn)
    }
}

/// Apple 凭据 → 后端入参的纯函数部分。
final class AppleCredentialMapperTests: XCTestCase {
    func testIdentityTokenIsDecodedAsUTF8AndNameIsFormatted() throws {
        var name = PersonNameComponents()
        name.givenName = "San"
        name.familyName = "Zhang"

        let credential = try AppleCredentialMapper.credential(
            identityToken: Data("eyJ.a.b".utf8), fullName: name
        )

        XCTAssertEqual(credential.identityToken, "eyJ.a.b")
        XCTAssertEqual(credential.fullName?.contains("Zhang"), true)
    }

    /// 二次登录 Apple 不再给姓名:不能变成空串发给后端。
    func testMissingNameStaysNil() throws {
        let credential = try AppleCredentialMapper.credential(
            identityToken: Data("token".utf8), fullName: PersonNameComponents()
        )

        XCTAssertNil(credential.fullName)
    }

    func testMissingIdentityTokenThrows() {
        XCTAssertThrowsError(
            try AppleCredentialMapper.credential(identityToken: nil, fullName: nil)
        ) { error in
            XCTAssertEqual(error as? AppleSignInError, .missingIdentityToken)
        }
    }

    /// 缺 entitlement 的构建里系统给 ASAuthorizationError.unknown(1000)。
    func testUnknownAuthorizationErrorBecomesNeedsSignedBuild() {
        let unknown = ASAuthorizationError(.unknown)

        XCTAssertEqual(
            AppleCredentialMapper.translate(unknown) as? AppleSignInError, .needsSignedBuild
        )
        XCTAssertEqual(
            AppleCredentialMapper.translate(ASAuthorizationError(.canceled)) as? AppleSignInError, .canceled
        )
    }
}

/// Apple 登录的防重放随机数(后端 `claims.nonce == sha256(raw)`)。
/// 构造 ASAuthorization 请求要在主线程,所以整个类挂 @MainActor。
@MainActor
final class AppleNonceTests: XCTestCase {
    /// 后端算的是 `hashlib.sha256(nonce.encode()).hexdigest()`——
    /// 必须是小写十六进制,不是 base64,不然每次登录都被判 invalid_identity_token。
    func testHashedNonceIsTheSHA256HexOfTheRawNonce() {
        let nonce = AppleNonce.make()

        XCTAssertEqual(nonce.hashed, AppleNonce.hash(nonce.raw))
        XCTAssertEqual(nonce.hashed.count, 64)
        XCTAssertTrue(
            nonce.hashed.allSatisfy { $0.isHexDigit && !$0.isUppercase },
            "必须是小写十六进制:\(nonce.hashed)"
        )
    }

    /// 对着已知向量核一遍,免得哪天把 sha256 换成别的摘要还自洽。
    func testHashMatchesAKnownSHA256Vector() {
        XCTAssertEqual(
            AppleNonce.hash("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    /// 后端限制:8–64 位 urlsafe。32 字节 base64url 正好 43 位。
    func testRawNonceIsUrlSafeAndWithinTheBackendLengthLimit() {
        let raw = AppleNonce.make().raw
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

        XCTAssertEqual(raw.count, 43)
        XCTAssertTrue((8...64).contains(raw.count))
        XCTAssertNil(raw.rangeOfCharacter(from: allowed.inverted), "出现了非 urlsafe 字符:\(raw)")
    }

    func testEveryNonceIsDifferent() {
        let nonces = (0..<50).map { _ in AppleNonce.make().raw }

        XCTAssertEqual(Set(nonces).count, 50, "随机数重复了,防重放就形同虚设")
    }

    /// 设给 Apple 的是**哈希**,发给后端的才是明文——这两个搞反了就一直 401。
    func testAuthorizationRequestCarriesTheHashedNonce() {
        let nonce = AppleNonce.make()

        let request = AppleSignInCoordinator.request(hashedNonce: nonce.hashed)

        XCTAssertEqual(request.nonce, nonce.hashed)
        XCTAssertEqual(request.nonce, AppleNonce.hash(nonce.raw))
        XCTAssertNotEqual(request.nonce, nonce.raw)
        XCTAssertEqual(request.requestedScopes, [.fullName, .email])
    }
}
