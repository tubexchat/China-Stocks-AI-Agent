import Foundation
import AppKit

/// 顶层工作区:Home = 聊天,Tools = 量化工具。
enum Workspace: String, CaseIterable, Sendable {
    case home, tools
}

/// 串起会话列表、当前会话、流式发送与设置。视图只跟它打交道。
@MainActor
final class AppViewModel: ObservableObject {
    @Published var workspace: Workspace = .home
    /// Tools 模式下当前打开的工具;nil = 工具卡列表。侧栏与内容区共用。
    @Published var selectedTool: QuantTool?
    /// 始终按「最近活跃」排在前面,不靠排序算法,靠每次更新时挪到队首。
    @Published private(set) var conversations: [Conversation]
    @Published var selectedID: UUID?
    @Published var settings: AppSettings { didSet { persistSettings() } }
    @Published private(set) var isStreaming = false
    @Published var draft = ""
    /// 待发送的行情附件(输入卡上的 chips)。
    @Published private(set) var pendingAttachments: [MarketSnapshot] = []
    /// 本地账户摘要(不含令牌);nil = 未登录。离线启动时先显示它。
    @Published private(set) var account: UserAccount?
    /// 最近一次 `/v1/me`:额度、权限、会话都从这里读。
    @Published private(set) var me: MeResponse?
    /// 已登录设备列表(设置 › 账户 手动刷新)。
    @Published private(set) var sessions: [SessionRow] = []
    /// 是否持有后端令牌。缓存成属性:视图 body 里每帧读钥匙串等于每帧一次 XPC。
    /// 只由 `authenticate` / `apply` / `signOutLocally` 维护。
    @Published private(set) var isSignedIn: Bool
    /// 登录/注册/改密进行中。
    @Published private(set) var isAuthBusy = false
    /// 最近一次账户操作的失败描述(按当前语言)。
    @Published var authError: String?
    /// GitHub 设备码流程里要用户配合的那一步(展示用户码);nil = 没在走设备流。
    @Published private(set) var authProgress: AuthProgress?
    /// 未登录页的邮箱表单是否展开。后端回 409 `email_registered_with_password`
    /// (这个邮箱已经用密码注册过)时自动展开,省得用户自己去翻折叠区。
    @Published var isEmailFormExpanded = false

    var service: any ChatService
    var marketServices: [MarketSourceKind: any MarketDataService]
    var accountService: AccountService
    /// 令牌写入口(默认落钥匙串并回读校验)。测试注入内存实现,
    /// 免得宿主的钥匙串权限决定测试成败。
    var tokenWriter: @Sendable (String?) -> Bool = { TokenStore.set($0) }
    /// 打开 GitHub 授权页。测试注入空实现,免得跑测试时弹浏览器。
    var openURL: @Sendable (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// 设备码轮询之间的等待。测试注入即时返回的实现。
    var sleeper: @Sendable (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    /// 原生 Sign in with Apple 的取凭据步骤。测试注入假凭据(不弹系统面板)。
    var appleCredentialProvider: @MainActor () async throws -> AppleCredential = {
        try await AppleSignInCoordinator().run()
    }
    private(set) var streamingTask: Task<Void, Never>?
    /// 正在进行的社交登录(设备码轮询 / Apple);`cancelSignIn()` 取消它,测试可以 await。
    private(set) var signInTask: Task<Void, Never>?
    /// 启动时那次 `refreshMe`,测试可以 await。
    private(set) var accountTask: Task<Void, Never>?

    private let store: ConversationStore

    private static let titleLimit = 20

    init(
        store: ConversationStore,
        service: any ChatService = OpenAIChatService(),
        marketServices: [MarketSourceKind: any MarketDataService] = MarketServiceRegistry.services(),
        accountService: AccountService = AccountService()
    ) {
        self.store = store
        self.service = service
        self.marketServices = marketServices
        self.accountService = accountService
        self.isSignedIn = accountService.tokenProvider() != nil
        let loadedSettings = store.loadSettings()
        self.settings = loadedSettings
        self.account = store.loadAccount()

        let loaded = store.loadConversations()
            .sorted { ($0.updatedAt, $0.id.uuidString) > ($1.updatedAt, $1.id.uuidString) }
        let freshTitle = loadedSettings.language.strings.freshConversationTitle
        self.conversations = loaded.isEmpty ? [Conversation.fresh(title: freshTitle)] : loaded
        self.selectedID = self.conversations.first?.id

        // 有令牌就顺手对一次账,额度/权限即时反映后台的变更。
        if isSignedIn {
            accountTask = Task { [weak self] in await self?.refreshMe() }
        }
    }

    convenience init() {
        self.init(store: ConversationStore(directory: ConversationStore.defaultDirectory()))
    }

    var current: Conversation? {
        guard let selectedID else { return nil }
        return conversations.first { $0.id == selectedID }
    }

    // MARK: - 会话管理

    func newConversation() {
        // 已经站在一个空会话上就别再造一个,免得侧栏堆满「新对话」。
        if let current, current.messages.isEmpty {
            selectedID = current.id
            return
        }
        let conversation = Conversation.fresh(title: text.freshConversationTitle)
        conversations.insert(conversation, at: 0)
        selectedID = conversation.id
        persistConversations()
    }

    func deleteConversation(_ id: UUID) {
        if selectedID == id { stopStreaming() }
        conversations.removeAll { $0.id == id }
        if conversations.isEmpty {
            conversations = [Conversation.fresh(title: text.freshConversationTitle)]
        }
        if selectedID == id || selectedID == nil {
            selectedID = conversations.first?.id
        }
        persistConversations()
    }

    func renameConversation(_ id: UUID, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].title = title
        conversations[index].updatedAt = Date()
        persistConversations()
    }

    // MARK: - 模型选择

    /// 可选模型:登录后按 `/v1/me` 的权限来(display_name 也用后端的),
    /// 未登录或离线拿不到 me 时回落到固定表,选择器不会空。
    var availableModels: [BackendModel] {
        guard let me, !me.permissions.models.isEmpty else { return Backend.models }
        return me.permissions.models.map { BackendModel(alias: $0.alias, displayName: $0.display_name) }
    }

    var currentModel: BackendModel {
        availableModels.first { $0.alias == settings.modelAlias }
            ?? availableModels.first
            ?? Backend.model(alias: settings.modelAlias)
    }

    func selectModel(_ alias: String) {
        guard availableModels.contains(where: { $0.alias == alias }) else { return }
        settings.modelAlias = alias
    }

    // MARK: - 语言

    /// 当前语言的整张文案表;settings 是 @Published,切语言时视图自动刷新。
    var text: L10nStrings {
        settings.language.strings
    }

    func selectLanguage(_ language: AppLanguage) {
        settings.language = language
    }

    // MARK: - 账户

    func signIn(email: String, password: String) async {
        let service = accountService
        await authenticate { try await service.login(email: email, password: password) }
    }

    func signUp(email: String, password: String, displayName: String) async {
        let service = accountService
        await authenticate {
            try await service.signup(email: email, password: password, displayName: displayName)
        }
    }

    // MARK: - 社交登录(主入口)

    /// GitHub 设备码:申请码 → 展示 + 打开浏览器 → 按后端给的间隔轮询 → 换到令牌。
    /// 令牌交换全程经我们自己的后端,客户端不持有 GitHub 的任何 secret。
    func signInWithGitHub() {
        guard !isAuthBusy else { return }
        isAuthBusy = true
        authError = nil
        signInTask = Task { [weak self] in await self?.runGitHubDeviceFlow() }
    }

    /// 原生 Sign in with Apple:系统面板拿 identity token,交给后端验签。
    func signInWithApple() {
        guard !isAuthBusy else { return }
        isAuthBusy = true
        authError = nil
        signInTask = Task { [weak self] in await self?.runAppleSignIn() }
    }

    /// 用户在设备码页按了取消:停轮询、收起用户码,不留半截状态。
    func cancelSignIn() {
        signInTask?.cancel()
    }

    /// 设备码被后端判无效(400 `invalid_device_code`)时整个流程重来一遍。
    /// 限次数:后端要是一直回 400,不能变成无限申请码。
    private static let deviceFlowAttempts = 2

    private func runGitHubDeviceFlow() async {
        defer {
            isAuthBusy = false
            authProgress = nil
        }
        for attempt in 0..<Self.deviceFlowAttempts {
            do {
                try await pumpGitHubDeviceFlow()
                return
            } catch is CancellationError {
                // 用户按了取消,不当成错误。
                return
            } catch let error as AccountError
                where error.code == "invalid_device_code" && attempt + 1 < Self.deviceFlowAttempts {
                // 这枚设备码后端不认了(过期或被清掉),换一枚重来,不打扰用户。
                authProgress = nil
                continue
            } catch {
                report(error)
                return
            }
        }
    }

    /// 走一遍完整的设备码流程;设备码本身失效时抛出去,由上面决定要不要重来。
    private func pumpGitHubDeviceFlow() async throws {
        let device = try await accountService.githubDeviceStart()
        guard let url = device.verificationURL else { throw AccountError.decoding }
        authProgress = .userCode(device.user_code, verificationURL: url)
        openURL(url)

        var wait = device.pollInterval
        while true {
            try await sleeper(wait)
            try Task.checkCancellation()
            switch try await accountService.githubDevicePoll(deviceCode: device.device_code) {
            case .pending(let interval):
                // 非 nil 表示后端(GitHub slow_down)要求放慢,照做。
                if let interval { wait = Double(max(interval, 1)) }
            case .signedIn(let token, _):
                try await adopt(token: token)
                return
            }
        }
    }

    private func runAppleSignIn() async {
        defer { isAuthBusy = false }
        do {
            let credential = try await appleCredentialProvider()
            try Task.checkCancellation()
            let issued = try await accountService.appleSignIn(
                identityToken: credential.identityToken,
                fullName: credential.fullName,
                nonce: credential.nonce
            )
            try await adopt(token: issued.token)
        } catch is CancellationError {
        } catch AppleSignInError.canceled {
            // 用户在系统面板上取消,没必要报错。
        } catch {
            report(error)
        }
    }

    /// 登录失败的统一出口。409 `email_registered_with_password` 说明这个邮箱
    /// 已经用密码注册过(社交 provider 的邮箱不能自动认领它),
    /// 这时把邮箱表单展开——用户要做的就是改用密码登录。
    private func report(_ error: any Error) {
        authError = text.describe(error)
        if (error as? AccountError)?.code == "email_registered_with_password" {
            isEmailFormExpanded = true
        }
    }

    /// 拉一次 `/v1/me`。401 说明令牌已失效(过期或被吊销),本地跟着登出。
    func refreshMe() async {
        guard isSignedIn else { return }
        do {
            apply(try await accountService.me())
        } catch let error as AccountError where error.statusCode == 401 {
            signOutLocally()
        } catch {
            authError = text.describe(error)
        }
    }

    func refreshSessions() async {
        guard isSignedIn else { return }
        do {
            sessions = try await accountService.sessions()
        } catch let error as AccountError where error.statusCode == 401 {
            signOutLocally()
        } catch {
            authError = text.describe(error)
        }
    }

    /// 吊销当前令牌;后端失败也照样清本地,不能把用户困在登录态里。
    func signOut() async {
        try? await accountService.logout()
        signOutLocally()
    }

    func signOutAll() async {
        try? await accountService.logoutAll()
        signOutLocally()
    }

    /// 改密成功后后端会吊销其它会话;错误交给视图展示,所以这里 throws。
    func changePassword(current: String, new: String) async throws {
        isAuthBusy = true
        defer { isAuthBusy = false }
        try await accountService.changePassword(current: current, new: new)
        await refreshSessions()
    }

    func revokeSession(id: Int) async {
        do {
            try await accountService.revokeSession(id: id)
            await refreshSessions()
        } catch {
            authError = text.describe(error)
        }
    }

    /// 注销账号(App Store 5.1.1(v))。密码错误后端只回 401 且保留会话,
    /// 所以这里**只在成功时**清本地——错误原样抛给视图内联展示,不走自动登出。
    /// 纯社交账户没有密码,`password` 传 nil。
    func deleteAccount(password: String?) async throws {
        isAuthBusy = true
        defer { isAuthBusy = false }
        try await accountService.deleteAccount(password: password)
        signOutLocally()
    }

    /// 只清本地状态(令牌、摘要、额度),不调后端。
    func signOutLocally() {
        _ = tokenWriter(nil)
        isSignedIn = false
        account = nil
        me = nil
        sessions = []
        authError = nil
        authProgress = nil
        try? store.saveAccount(nil)
    }

    /// 登录与注册只差一个签发令牌的调用,后面的流程完全一样。
    private func authenticate(_ issueToken: () async throws -> String) async {
        guard !isAuthBusy else { return }
        isAuthBusy = true
        authError = nil
        do {
            try await adopt(token: try await issueToken())
        } catch {
            report(error)
        }
        isAuthBusy = false
    }

    /// 后端签发的令牌落地 + 对一次账。邮箱、GitHub、Apple 三条路共用这一段。
    private func adopt(token: String) async throws {
        guard tokenWriter(token) else {
            authError = text.keychainWriteFailed
            return
        }
        isSignedIn = true
        // 刚签发的令牌只借给紧接着这一次 me(),不等钥匙串回读;
        // 但绝不能钉回 accountService——否则登出清了钥匙串,
        // tokenProvider 还捧着旧令牌,isSignedIn 会一直是 true。
        var justIssued = accountService
        justIssued.tokenProvider = { token }
        apply(try await justIssued.me())
    }

    /// `/v1/me` 落地:内存留全量,磁盘只留一份不含令牌的摘要。
    private func apply(_ response: MeResponse) {
        me = response
        let summary = UserAccount(
            email: response.user.email ?? "",
            displayName: response.user.display_name,
            plan: response.user.plan
        )
        account = summary
        try? store.saveAccount(summary)
        clampModelSelection()
    }

    /// 套餐降级后,已选模型可能已经没权限了,收敛到第一个可用的。
    private func clampModelSelection() {
        guard !availableModels.contains(where: { $0.alias == settings.modelAlias }),
              let fallback = availableModels.first
        else { return }
        settings.modelAlias = fallback.alias
    }

    // MARK: - 行情附加

    var enabledSources: [MarketSourceKind] {
        MarketSourceKind.allCases.filter { !settings.disabledSources.contains($0) }
    }

    func setSource(_ kind: MarketSourceKind, enabled: Bool) {
        if enabled {
            settings.disabledSources.remove(kind)
        } else {
            settings.disabledSources.insert(kind)
        }
    }

    func fetchSnapshot(source: MarketSourceKind, symbol: String) async throws -> MarketSnapshot {
        try requireSignInForProxiedSource(source)
        guard let service = marketServices[source] else {
            throw MarketDataError.network(text.sourceNotRegistered)
        }
        return try await service.snapshot(rawSymbol: symbol)
    }

    func fetchDailyCloses(source: MarketSourceKind, symbol: String, days: Int) async throws -> [Double] {
        try requireSignInForProxiedSource(source)
        guard let service = marketServices[source] else {
            throw MarketDataError.network(text.sourceNotRegistered)
        }
        return try await service.dailyCloses(rawSymbol: symbol, days: days)
    }

    /// 只有 Binance 走官方后端代理(封锁 IP 需要出海),未登录必然 401;
    /// 与其绕一圈拿后端的报错,不如当场说清楚,一个字节都不发。
    /// 其余数据源是公共接口,未登录照常可用。
    private func requireSignInForProxiedSource(_ source: MarketSourceKind) throws {
        guard source == .binance, !isSignedIn else { return }
        throw MarketDataError.network(text.signInRequired)
    }

    func attach(_ snapshot: MarketSnapshot) {
        pendingAttachments.append(snapshot)
    }

    func removeAttachment(id: String) {
        pendingAttachments.removeAll { $0.id == id }
    }

    /// 工具页「让 AI 解读」:回到 Home、开新会话、把量化报告作为用户消息直接发出。
    /// 不动用户没发出去的草稿。
    func analyze(report: String) {
        workspace = .home
        let savedDraft = draft
        draft = ""
        newConversation()
        draft = text.analyzePromptPrefix + "\n\n" + report
        send()
        draft = savedDraft
    }

    // MARK: - 发送

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = pendingAttachments
        guard !text.isEmpty || !attachments.isEmpty,
              !isStreaming, let conversationID = selectedID else { return }

        // 未登录时后端必然 401,与其绕一圈,不如当场说清楚(草稿原样留着)。
        guard isSignedIn else {
            append(
                ChatMessage(role: .assistant, content: self.text.signInRequired, isError: true),
                to: conversationID
            )
            persistConversations()
            return
        }
        draft = ""
        pendingAttachments = []

        // 用户文字在前、数据块在后;标题只认用户文字,纯附加时用首个代码。
        let language = settings.language
        let blocks = attachments.map { $0.promptText(in: language) }.joined(separator: "\n\n")
        let content = text.isEmpty ? blocks : (blocks.isEmpty ? text : text + "\n\n" + blocks)

        append(ChatMessage(role: .user, content: content), to: conversationID)
        retitleIfNeeded(
            conversationID,
            from: text.isEmpty ? (attachments.first?.symbol ?? self.text.marketFallbackTitle) : text
        )

        let history = outboundHistory(of: conversationID)
        let placeholder = ChatMessage(role: .assistant, content: "")
        append(placeholder, to: conversationID)
        isStreaming = true

        let service = service
        let model = settings.modelAlias
        streamingTask = Task { [weak self] in
            var failure: Error?
            do {
                for try await delta in service.streamReply(messages: history, model: model) {
                    try Task.checkCancellation()
                    self?.appendDelta(delta, to: placeholder.id, in: conversationID)
                }
            } catch is CancellationError {
                // 用户按了停止,已经吐出来的内容原样留着。
            } catch {
                failure = error
            }
            self?.finishStreaming(conversationID, placeholderID: placeholder.id, failure: failure)
        }
    }

    func stopStreaming() {
        streamingTask?.cancel()
    }

    // MARK: - 内部

    /// 发给模型的历史:不含报错气泡,也不含还没填内容的占位消息。
    private func outboundHistory(of conversationID: UUID) -> [ChatMessage] {
        guard let conversation = conversations.first(where: { $0.id == conversationID }) else { return [] }
        return conversation.messages.filter { !$0.isError && !$0.content.isEmpty }
    }

    private func append(_ message: ChatMessage, to conversationID: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[index].messages.append(message)
        conversations[index].updatedAt = Date()
        moveToFront(index)
    }

    private func appendDelta(_ delta: String, to messageID: UUID, in conversationID: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }),
              let messageIndex = conversations[index].messages.firstIndex(where: { $0.id == messageID })
        else { return }
        conversations[index].messages[messageIndex].content += delta
    }

    private func retitleIfNeeded(_ conversationID: UUID, from text: String) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }),
              conversations[index].messages.filter({ $0.role == .user }).count == 1
        else { return }
        conversations[index].title = text.count > Self.titleLimit
            ? String(text.prefix(Self.titleLimit)) + "…"
            : text
    }

    /// 没走到网络就失败的路径:直接落一条报错气泡。
    private func finish(_ conversationID: UUID, with error: ChatServiceError) {
        append(errorMessage(for: error), to: conversationID)
        isStreaming = false
        persistConversations()
    }

    private func finishStreaming(_ conversationID: UUID, placeholderID: UUID, failure: Error?) {
        if let index = conversations.firstIndex(where: { $0.id == conversationID }),
           let messageIndex = conversations[index].messages.firstIndex(where: { $0.id == placeholderID }),
           conversations[index].messages[messageIndex].content.isEmpty {
            // 一个字都没吐出来的占位消息不留在界面上。
            conversations[index].messages.remove(at: messageIndex)
        }
        if let failure {
            append(errorMessage(for: failure), to: conversationID)
            // 令牌失效(过期/被吊销)时本地跟着登出,免得一直撞 401。
            if case .http(401, _)? = failure as? ChatServiceError { signOutLocally() }
        }
        isStreaming = false
        streamingTask = nil
        persistConversations()
    }

    private func errorMessage(for error: Error) -> ChatMessage {
        ChatMessage(role: .assistant, content: text.describe(error), isError: true)
    }

    private func moveToFront(_ index: Int) {
        guard index > 0 else { return }
        let conversation = conversations.remove(at: index)
        conversations.insert(conversation, at: 0)
    }

    private func persistConversations() {
        try? store.saveConversations(conversations)
    }

    private func persistSettings() {
        try? store.saveSettings(settings)
    }
}
