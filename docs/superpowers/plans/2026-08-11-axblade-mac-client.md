# Axblade for Mac 原生 AI 客户端 — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 用 Swift + SwiftUI 构建运行于 Apple Silicon 的原生 macOS AI 聊天客户端(流式对话、多 Provider、Axblade 品牌深色 UI)。

**Architecture:** MVVM。纯函数 `SSEParser` + 协议化 `ChatService`(OpenAI 兼容 / Anthropic 两个实现)+ JSON `ConversationStore` + Keychain 密钥存储;`AppViewModel` 串接;SwiftUI `NavigationSplitView` 三段式界面。

**Tech Stack:** Swift 6.3 / SwiftUI / URLSession(async bytes)/ XCTest / XcodeGen。零第三方依赖。

## Global Constraints

- 部署目标 macOS 14.0+;`ARCHS = arm64`。
- 仓库根:`/Users/ubuntu/Desktop/Axblade-Mac-Cli`。Bundle ID `io.primit.axblade`。
- 零第三方包依赖;只用系统框架。
- App Sandbox 开启 + `com.apple.security.network.client` 权限。
- 主题色恒定:bg `#0B0D10`、surface `#12151A`、border `#232830`、text `#E8ECF1`、muted `#98A2AD`、accent `#22D3EE`。
- UI 文案中文。
- 每个任务结束必须 `xcodegen generate`(若 project.yml 变更)+ `xcodebuild` 通过后 git commit。
- 测试命令统一:`xcodebuild test -project Axblade.xcodeproj -scheme Axblade -destination 'platform=macOS,arch=arm64' -quiet`。

---

### Task 1: 工程脚手架(XcodeGen + 空 App 可构建)

**Files:**
- Create: `project.yml`, `.gitignore`, `Axblade/App/AxbladeApp.swift`, `Axblade/App/Info.plist`, `Axblade/App/Axblade.entitlements`, `Axblade/Views/Theme.swift`, `AxbladeTests/SmokeTests.swift`

**Interfaces:**
- Produces: `Theme` enum — 静态颜色 `Theme.background/.surface/.border/.text/.muted/.accent`(SwiftUI `Color`,由十六进制常量构造)+ `Theme.hexColor(_ hex: UInt32) -> Color`。后续所有 View 只从这里取色。

- [x] **Step 1: 写 project.yml**

```yaml
name: Axblade
options:
  bundleIdPrefix: io.primit
  deploymentTarget:
    macOS: "14.0"
settings:
  base:
    ARCHS: arm64
    SWIFT_VERSION: "6.0"
    MACOSX_DEPLOYMENT_TARGET: "14.0"
targets:
  Axblade:
    type: application
    platform: macOS
    sources: [Axblade]
    info:
      path: Axblade/App/Info.plist
      properties:
        CFBundleDisplayName: Axblade
        NSHumanReadableCopyright: "© 2026 Primit"
        LSMinimumSystemVersion: "14.0"
    entitlements:
      path: Axblade/App/Axblade.entitlements
      properties:
        com.apple.security.app-sandbox: true
        com.apple.security.network.client: true
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: io.primit.axblade
        CODE_SIGN_IDENTITY: "-"
        ENABLE_HARDENED_RUNTIME: false
  AxbladeTests:
    type: bundle.unit-test
    platform: macOS
    sources: [AxbladeTests]
    dependencies:
      - target: Axblade
schemes:
  Axblade:
    build:
      targets: { Axblade: all }
    test:
      targets: [AxbladeTests]
```

- [x] **Step 2: 写 .gitignore(`*.xcodeproj`、`build/`、`DerivedData/`、`.DS_Store`)、最小 `AxbladeApp.swift`(WindowGroup + "Axblade" Text)、`Theme.swift`、冒烟测试 `XCTAssertEqual(1+1, 2)`**
- [x] **Step 3: `xcodegen generate` 然后构建+测试,预期 PASS**
- [x] **Step 4: Commit `chore: scaffold Axblade app with XcodeGen (arm64, macOS 14+)`**

### Task 2: 数据模型 + ConversationStore(TDD)

**Files:**
- Create: `Axblade/Models/Models.swift`, `Axblade/Services/ConversationStore.swift`, `AxbladeTests/ModelsTests.swift`, `AxbladeTests/ConversationStoreTests.swift`

**Interfaces:**
- Produces:
  - `enum Role: String, Codable { case system, user, assistant }`
  - `struct ChatMessage: Identifiable, Codable, Equatable { let id: UUID; var role: Role; var content: String; var createdAt: Date; var isError: Bool }`(init 带默认值 `id: UUID = UUID(), createdAt: Date = Date(), isError: Bool = false`)
  - `struct Conversation: Identifiable, Codable, Equatable { let id: UUID; var title: String; var messages: [ChatMessage]; var createdAt: Date; var updatedAt: Date }` + `static func fresh() -> Conversation`(title "新对话")
  - `struct ProviderConfig: Identifiable, Codable, Equatable, Hashable { let id: UUID; var kind: ProviderKind; var name: String; var baseURL: String; var model: String }`
  - `enum ProviderKind: String, Codable, CaseIterable { case openaiCompatible, anthropic }`
  - `struct AppSettings: Codable, Equatable { var providers: [ProviderConfig]; var defaultProviderID: UUID? }`
  - `final class ConversationStore`:`init(directory: URL)`、`func loadConversations() -> [Conversation]`、`func saveConversations(_:) throws`、`func loadSettings() -> AppSettings`、`func saveSettings(_:) throws`。JSON ISO8601 日期,原子写入,目录不存在时自动创建。

- [x] **Step 1: 写失败测试(往返:save→load 相等;空目录 load 返回 `[]` / 默认 settings;损坏文件 load 返回空不抛)**
- [x] **Step 2: 跑测试确认 FAIL(类型不存在)**
- [x] **Step 3: 实现 Models + Store(JSONEncoder `.iso8601` + `.atomic` 写盘)**
- [x] **Step 4: 跑测试 PASS**
- [x] **Step 5: Commit `feat: add chat models and JSON conversation store`**

### Task 3: SSEParser(TDD)

**Files:**
- Create: `Axblade/Services/SSEParser.swift`, `AxbladeTests/SSEParserTests.swift`

**Interfaces:**
- Produces: `struct SSEParser`,方法:
  - `mutating func consume(line: String) -> SSEEvent?` — 输入一行(无换行符),`data: {...}` 行返回事件,空行/注释/其他字段返回 nil
  - `enum SSEEvent: Equatable { case data(String); case done }`(`data: [DONE]` → `.done`)
  - `static func openAIDelta(fromDataPayload json: String) -> String?` — 解析 `choices[0].delta.content`
  - `static func anthropicDelta(fromDataPayload json: String) -> String?` — 解析 `type == "content_block_delta"` 的 `delta.text`

**测试用例(全部真实断言):**

```swift
func testDataLineYieldsEvent() {
    var p = SSEParser()
    XCTAssertEqual(p.consume(line: "data: hello"), .data("hello"))
}
func testDoneSentinel() {
    var p = SSEParser()
    XCTAssertEqual(p.consume(line: "data: [DONE]"), .done)
}
func testIgnoresCommentsAndBlankAndEventLines() {
    var p = SSEParser()
    XCTAssertNil(p.consume(line: ""))
    XCTAssertNil(p.consume(line: ": keep-alive"))
    XCTAssertNil(p.consume(line: "event: message_start"))
}
func testOpenAIDeltaExtraction() {
    let json = #"{"choices":[{"delta":{"content":"你好"}}]}"#
    XCTAssertEqual(SSEParser.openAIDelta(fromDataPayload: json), "你好")
    XCTAssertNil(SSEParser.openAIDelta(fromDataPayload: #"{"choices":[{"delta":{}}]}"#))
}
func testAnthropicDeltaExtraction() {
    let json = #"{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hi"}}"#
    XCTAssertEqual(SSEParser.anthropicDelta(fromDataPayload: json), "Hi")
    XCTAssertNil(SSEParser.anthropicDelta(fromDataPayload: #"{"type":"message_stop"}"#))
}
```

- [x] **Step 1: 写上述失败测试 → FAIL**
- [x] **Step 2: 实现(`data:` 前缀剥离 + trim;JSONSerialization 提取 delta)→ PASS**
- [x] **Step 3: Commit `feat: add SSE parser for OpenAI and Anthropic streams`**

### Task 4: KeychainStore + ChatService 流式实现

**Files:**
- Create: `Axblade/Services/KeychainStore.swift`, `Axblade/Services/ChatService.swift`, `AxbladeTests/ChatServiceTests.swift`

**Interfaces:**
- Produces:
  - `enum KeychainStore { static func setAPIKey(_ key: String, for id: UUID); static func apiKey(for id: UUID) -> String?; static func deleteAPIKey(for id: UUID) }`(service `io.primit.axblade`,account 为 provider UUID 字符串)
  - `enum ChatServiceError: LocalizedError, Equatable { case missingAPIKey, invalidURL, http(Int, String) }`(中文 errorDescription)
  - `protocol ChatService { func streamReply(messages: [ChatMessage], config: ProviderConfig, apiKey: String) -> AsyncThrowingStream<String, Error> }`
  - `struct OpenAIChatService: ChatService` — POST `{baseURL}/chat/completions`,body `{model, stream:true, messages:[{role,content}]}`,header `Authorization: Bearer`;
  - `struct AnthropicChatService: ChatService` — POST `{baseURL}/v1/messages`,headers `x-api-key`、`anthropic-version: 2023-06-01`,system 消息提升为顶层 `system` 字段,`max_tokens: 4096`
  - 两者共用 `static func buildRequest(...) throws -> URLRequest`(internal,可单测)+ 私有流循环:`URLSession.bytes` → 按行喂 `SSEParser` → yield 文本增量;HTTP ≠2xx 时读 body 抛 `.http`。
- Consumes: Task 2 `ChatMessage/ProviderConfig`,Task 3 `SSEParser`。

**测试(不打真网,只测请求构造):** OpenAI request 的 URL 拼接(baseURL 末尾斜杠容错)、Authorization header、JSON body 字段;Anthropic 的 x-api-key header 与 system 提升。

- [x] **Step 1: 写 buildRequest 失败测试 → FAIL**
- [x] **Step 2: 实现 KeychainStore + 两个 service → 测试 PASS**
- [x] **Step 3: Commit `feat: add streaming chat services and keychain storage`**

### Task 5: AppViewModel(会话编排)

**Files:**
- Create: `Axblade/ViewModels/AppViewModel.swift`, `AxbladeTests/AppViewModelTests.swift`

**Interfaces:**
- Produces: `@MainActor final class AppViewModel: ObservableObject`:
  - `@Published var conversations: [Conversation]`、`@Published var selectedID: UUID?`、`@Published var settings: AppSettings`、`@Published var isStreaming: Bool`、`@Published var draft: String`
  - `var current: Conversation?`(计算属性)
  - `func newConversation()`、`func deleteConversation(_ id: UUID)`、`func renameConversation(_ id: UUID, to: String)`
  - `func send()` — 追加 user 消息 + 空 assistant 消息,启动流式 Task 增量追加;首条消息后用前 20 字符设标题;完成/失败后持久化
  - `func stopStreaming()` — 取消 Task
  - `func addProvider(_:) / updateProvider(_:) / removeProvider(_:)`、`var activeProvider: ProviderConfig?`
  - `init(store: ConversationStore, services: [ProviderKind: ChatService])` — 注入以便测试用 fake service
  - 无 provider 或无 key 时 `send()` 在会话内追加 `isError` 消息(文案:"请先在 设置 → 模型服务 中配置 API Key")
- Consumes: Task 2/3/4 全部接口。

**测试:** 用 fake `ChatService`(yield "a","b" 后结束)断言 send() 后 assistant 消息内容 == "ab"、isStreaming 复位、标题自动生成;无 provider 时产生 isError 消息。

- [x] **Step 1: 失败测试 → FAIL**
- [x] **Step 2: 实现 → PASS**
- [x] **Step 3: Commit `feat: add AppViewModel conversation orchestration`**

### Task 6: SwiftUI 界面

**Files:**
- Create: `Axblade/Views/SidebarView.swift`, `Axblade/Views/ChatView.swift`, `Axblade/Views/MessageRow.swift`, `Axblade/Views/ComposerView.swift`, `Axblade/Views/EmptyStateView.swift`, `Axblade/Views/SettingsView.swift`, `Axblade/Views/MarkdownText.swift`, `Axblade/Views/BrandMark.swift`
- Modify: `Axblade/App/AxbladeApp.swift`

**Interfaces:**
- Consumes: `AppViewModel` 全部 published 属性与方法;`Theme` 颜色。
- Produces(组件契约):
  - `BrandMark(size: CGFloat)` — 青色六边形刀锋 SVG 风 logo(Path 绘制)
  - `MarkdownText(content: String)` — 把 content 按 ``` 围栏切段;文本段用 `Text(AttributedString(markdown:, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))`,代码段用等宽字体深色卡片 + 复制按钮
  - `MessageRow(message: ChatMessage, isStreaming: Bool)` — user 右对齐 surface 气泡;assistant 左侧 BrandMark + 全宽;isError 红色边框;流式中尾部 accent 光标块
  - `ComposerView` — `TextField(axis: .vertical).lineLimit(1...8)`,Enter 发送(`.onSubmit`)、⌘Enter 换行说明省略;流式中显示停止按钮;左侧 provider Picker(绑定 `settings.defaultProviderID`)
  - `EmptyStateView(suggestions: [String], onPick: (String) -> Void)` — 居中 BrandMark + "你好,我是 Axblade" + 4 个建议 chips
  - `SettingsView` — `Settings` 场景,provider 列表 CRUD 表单(名称/类型/BaseURL/模型/APIKey SecureField,保存时写 Keychain)
  - App 入口:`NavigationSplitView`,强制 `.preferredColorScheme(.dark)`,窗口最小 900×600
- [x] **Step 1: 实现全部 View + 接线,`xcodegen generate` + 构建通过(UI 无单测,验收在 Task 7)**
- [x] **Step 2: Commit `feat: build Axblade chat UI (sidebar, chat, composer, settings)`**

### Task 7: 端到端验证与收尾

**Files:**
- Create: `README.md`
- Modify: 发现的问题按需修

- [x] **Step 1: `xcodebuild test`(全部单测 PASS)+ Release 构建;`lipo -archs` 确认 arm64**
- [x] **Step 2: `open` 启动 app,截图验证:侧栏+空状态、发消息流式(用本地 mock 或直接核对错误消息路径)、设置窗口**
- [x] **Step 3: 修复截图中发现的布局/交互问题,重建重验**
- [x] **Step 4: 写 README(简介/构建命令/配置 provider 说明),Commit `docs: add README; polish UI`**
