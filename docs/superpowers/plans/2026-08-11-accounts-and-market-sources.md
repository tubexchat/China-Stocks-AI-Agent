# Axblade 账户与金融数据源 — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 设置中支持 GitHub(Device Flow)/Apple 登录退出;输入卡 “+” 变为 7 个金融数据源菜单(Binance/OKX/抹茶/美股/韩股/港股/A股),行情快照可附加进对话发给 AI 分析。

**Architecture:** `AuthProvider` 协议(GitHub Device Flow 轮询 + Apple 系统登录)→ 账户存 `account.json`、token 存钥匙串;`MarketDataService` 协议 + 4 个实现(三家交易所公共 REST + Yahoo v8 chart 覆盖四个股票市场),代码归一化/请求/解析全部纯函数;`AppViewModel` 持有 `pendingAttachments`,发送时数据块并入用户消息;设置窗口 TabView 三标签。

**Tech Stack:** Swift 6.3 / SwiftUI / URLSession / AuthenticationServices / XCTest / XcodeGen。零第三方依赖。

## Global Constraints

- 仓库根 `/Users/ubuntu/Desktop/Axblade-Mac-Cli`;分支 `feat/accounts-and-market-sources`。
- 测试命令 `./scripts/test.sh`;每个任务结束测试全绿后 git commit。
- UI 文案中文;颜色只从 `Theme` 取。
- AppSettings 新字段必须 `decodeIfPresent`,旧 settings.json 不得解码失败。
- 不加 `com.apple.developer.applesignin` entitlement(ad-hoc 签名会被系统拒载);Apple 登录运行时失败给中文提示。
- 实测锁定的响应形状:Binance `priceChangePercent="-1.468"`(百分数)、MEXC `="-0.0149"`(小数,需 ×100)、OKX 无现成涨跌需用 `(last-open24h)/open24h×100`、OKX candles 新→旧需反转、Yahoo 用 `meta.regularMarketPrice/chartPreviousClose/longName/currency` + `indicators.quote[0].close`,请求带浏览器 UA。

---

### Task 1: 模型层 — MarketSourceKind / MarketSnapshot / UserAccount / 设置兼容 / 存储

**Files:**
- Create: `Axblade/Models/MarketModels.swift`, `Axblade/Models/AccountModels.swift`
- Modify: `Axblade/Models/Models.swift`(AppSettings 增 `disabledSources` + 容错解码)、`Axblade/Services/ConversationStore.swift`(account 持久化)、`Axblade/Services/KeychainStore.swift`(字符串 account API)
- Test: `AxbladeTests/MarketModelsTests.swift`, `AxbladeTests/AccountModelsTests.swift`,扩 `ConversationStoreTests`/`KeychainStoreTests`

**Interfaces (Produces):**

```swift
enum MarketSourceKind: String, Codable, CaseIterable, Sendable {
    case binance, okx, mexc, usStock, krStock, hkStock, aShare
    var displayName: String   // "Binance"/"OKX"/"抹茶 MEXC"/"美股"/"韩股"/"港股"/"A股"
    var isCrypto: Bool        // 前三个 true
}
struct MarketSnapshot: Equatable, Sendable {
    var source: MarketSourceKind; var symbol: String; var name: String?
    var price: Double; var changePercent: Double?
    var high: Double?; var low: Double?; var volume: Double?; var currency: String?
    var closes: [Double]   // 旧→新
    var fetchedAt: Date
    var promptText: String  // 【行情数据 · {source} · {symbol}(name?)· yyyy-MM-dd HH:mm】\n现价 …;24h 涨跌 …;高 …/低 …;量 …\n近N日收盘(旧→新): a, b, c
    var chipText: String    // "BTCUSDT +2.31%"(无涨跌时只有 symbol)
    static func formatNumber(_ v: Double) -> String  // |v|>=1 保留2位并去尾零;否则 4 位有效
}
enum AuthProviderKind: String, Codable, Sendable { case github, apple }  // displayName "GitHub"/"Apple"
struct UserAccount: Codable, Equatable, Sendable { var provider: AuthProviderKind; var id: String; var displayName: String; var handle: String?; var avatarURL: URL?; var linkedAt: Date }  // init 带默认 linkedAt: Date = Date(),经 snappedToMilliseconds
struct SignedInUser: Equatable, Sendable { var account: UserAccount; var secret: String? }
// AppSettings 增: var disabledSources: Set<MarketSourceKind> = []  + 自定义 init(from:) 全字段 decodeIfPresent
// ConversationStore 增: func loadAccount() -> UserAccount?; func saveAccount(_ account: UserAccount?) throws  // nil 删 account.json
// KeychainStore 增: static func setSecret(_ value: String, account: String) / secret(account:) -> String? / deleteSecret(account:)(UUID 版委托到这组)
```

- [x] **Step 1: 写失败测试**:枚举 7 个 case 与分组;chipText/promptText 用固定 Date 断言整串;formatNumber(64038.0)=="64038"、(2.31)=="2.31"、(0.001234)=="0.001234";旧版 settings JSON(只有 providers/defaultProviderID)解码成功且 disabledSources 为空;account 往返/传 nil 删文件;钥匙串字符串 API 往返(沿用 skipIfKeychainUnavailable)。
- [x] **Step 2: 跑测试确认 FAIL(类型不存在)**
- [x] **Step 3: 实现全部类型与存储扩展**
- [x] **Step 4: `./scripts/test.sh` 全绿**
- [x] **Step 5: Commit `feat: add market source and account models`**

### Task 2: 行情服务 — 归一化/请求/解析 + 4 个实现

**Files:**
- Create: `Axblade/Services/MarketDataService.swift`(协议+错误+注册表)、`Axblade/Services/CryptoMarketServices.swift`(Binance/OKX/MEXC)、`Axblade/Services/YahooFinanceService.swift`
- Test: `AxbladeTests/SymbolNormalizationTests.swift`, `AxbladeTests/MarketParsingTests.swift`(fixture 用 Global Constraints 里实测的 JSON 形状)、`AxbladeTests/MarketIntegrationTests.swift`(URLProtocol 按 URL 前缀路由的 `MockHTTPProtocol`)

**Interfaces:**
- Consumes: Task 1 全部类型。
- Produces:

```swift
enum MarketDataError: LocalizedError, Equatable { case invalidSymbol(String), http(Int), decoding, network(String) }  // 中文 errorDescription
protocol MarketDataService: Sendable { func snapshot(rawSymbol: String) async throws -> MarketSnapshot }
struct BinanceMarketService: MarketDataService { var session: URLSession = .shared; static func normalize(_ raw: String) -> String }
struct OKXMarketService: MarketDataService { ...; static func normalize(_ raw: String) -> String }
struct MEXCMarketService: MarketDataService { ...; static func normalize(_ raw: String) -> String }
struct YahooFinanceService: MarketDataService { var market: MarketSourceKind; var session: URLSession = .shared; static func normalize(_ raw: String, market: MarketSourceKind) -> String }
enum MarketServiceRegistry { static func services(session: URLSession = .shared) -> [MarketSourceKind: any MarketDataService] }  // 7 个 kind 全映射
```

**归一化规则(锁定):** 已知报价后缀 = USDT/USDC/FDUSD/BTC/ETH/USD。Binance/MEXC:大写去 `-/ `,无后缀补 USDT(`btc`→`BTCUSDT`)。OKX:大写,`/`→`-`;无 `-` 时在已知后缀前插 `-`,纯 base 补 `-USDT`(`BTCUSDT`→`BTC-USDT`)。Yahoo:含 `.` 原样大写;美股大写;韩股纯数字→`.KS`;港股纯数字去前导零补 4 位→`.HK`(`700`→`0700.HK`);A股 6/9 开头→`.SS`,0/3 开头→`.SZ`,其余→`.SS`。

- [x] **Step 1: 写归一化+解析失败测试 → FAIL**(解析测试直接调 `static func parse...`,fixture 抄实测形状含 MEXC 小数陷阱、OKX 反转)
- [x] **Step 2: 实现三家加密服务 + Yahoo(Yahoo 请求头 `User-Agent: Mozilla/5.0 …`;`range=1mo&interval=1d`;close 数组过滤 null)→ 归一化/解析测试 PASS**
- [x] **Step 3: 写 MockHTTPProtocol(静态 `[String pattern: (status, body)]` 路由)集成测试:Binance 全链路快照、Yahoo 全链路、404→`.http`、坏 JSON→`.decoding` → PASS**
- [x] **Step 4: Commit `feat: add market data services for exchanges and Yahoo Finance`**

### Task 3: AppViewModel 附加流程

**Files:**
- Modify: `Axblade/ViewModels/AppViewModel.swift`
- Test: `AxbladeTests/AppViewModelTests.swift`(追加)

**Interfaces:**
- Produces(AppViewModel 新增):

```swift
@Published var pendingAttachments: [MarketSnapshot]
var marketServices: [MarketSourceKind: any MarketDataService]   // init 注入,默认 MarketServiceRegistry.services()
var enabledSources: [MarketSourceKind]                          // allCases 减 settings.disabledSources,保持声明顺序
func setSource(_ kind: MarketSourceKind, enabled: Bool)
func fetchSnapshot(source: MarketSourceKind, symbol: String) async throws -> MarketSnapshot
func attach(_ snapshot: MarketSnapshot) / func removeAttachment(id …)
```

- send() 合并:`content = text + "\n\n" + blocks`(text 空则只有 blocks);**标题取用户文字**,纯附加时取首个 symbol;允许 draft 空但有附件时发送;发送后清空 pending。
- [x] **Step 1: 失败测试**(附加+发送合并内容、标题规则、纯附件发送、发送后清空、enabledSources/setSource 持久化)→ FAIL
- [x] **Step 2: 实现 → 全绿;Commit `feat: add market snapshot attachments to conversation flow`**

### Task 4: 认证 — GitHub Device Flow + Apple + 编排

**Files:**
- Create: `Axblade/Services/AuthProviders.swift`
- Modify: `Axblade/ViewModels/AppViewModel.swift`(account 编排)
- Test: `AxbladeTests/GitHubAuthTests.swift`

**Interfaces:**
- Produces:

```swift
enum AuthProgress: Equatable, Sendable { case userCode(String, verificationURL: URL) }
protocol AuthProvider: Sendable { func signIn(progress: @escaping @Sendable (AuthProgress) -> Void) async throws -> SignedInUser }
enum AuthError: LocalizedError, Equatable { case notConfigured, denied, expired, http(Int), decoding, needsDeveloperSigning }  // 中文;notConfigured 提示填 AuthConfig.githubClientID
enum AuthConfig { static var githubClientID = "" }
struct GitHubAuthProvider: AuthProvider {
    var clientID: String = AuthConfig.githubClientID
    var session: URLSession = .shared
    var openURL: @Sendable (URL) -> Void            // 默认 NSWorkspace.shared.open
    var sleeper: @Sendable (Double) async throws -> Void   // 默认 Task.sleep,测试注入空实现
}
struct AppleAuthProvider: AuthProvider { static func account(userID: String, fullName: PersonNameComponents?, email: String?) -> UserAccount }
// AppViewModel 增:
@Published var account: UserAccount?
@Published var authProgress: AuthProgress?
@Published var authError: String?
var authProviders: [AuthProviderKind: any AuthProvider]   // init 注入
func signIn(with kind: AuthProviderKind)   // Task 包裹,成功后存 account.json + 钥匙串 "auth.<kind>"
func signOut()
```

- GitHub 端点:POST `github.com/login/device/code`(form: client_id/scope=read:user,Accept: application/json)→ POST `login/oauth/access_token`(grant_type=urn:ietf:params:oauth:grant-type:device_code,处理 authorization_pending/slow_down(+5s)/expired_token/access_denied)→ GET `api.github.com/user`(Bearer)。
- [x] **Step 1: 失败测试**(MockHTTPProtocol 脚本:device_code→pending→token→user 全链路出正确 UserAccount+secret 且 progress 收到用户码;denied 抛 `.denied`;clientID 空抛 `.notConfigured`;Apple 映射:有名字用名字、无名字用 email 前缀、都无用 "Apple 用户")→ FAIL
- [x] **Step 2: 实现两个 provider + AppViewModel 编排(fake provider 测 signIn/signOut 状态与持久化)→ 全绿;Commit `feat: add GitHub device flow and Apple sign-in`**

### Task 5: UI — 设置三标签 / 侧栏账户行 / “+” 数据源菜单与附加 sheet

**Files:**
- Create: `Axblade/Views/AccountSettingsView.swift`, `Axblade/Views/SourcesSettingsView.swift`, `Axblade/Views/AttachmentSheet.swift`
- Modify: `Axblade/Views/SettingsView.swift`(变 TabView 容器,原内容改名 `ProvidersSettingsView` 同文件保留)、`Axblade/Views/SidebarView.swift`(底栏账户)、`Axblade/Views/ComposerView.swift`(chips 行 + “+” 菜单 + sheet)

**要点:**
- SettingsView = TabView:账户 `person.crop.circle` / 模型服务 `sparkles` / 数据源 `chart.line.uptrend.xyaxis`,frame 760×520。
- 账户页:未登录 → 两个登录按钮;`authProgress == .userCode` 时显示大号用户码 + “已在浏览器打开授权页,输入上面的代码” + 取消;已登录 → AsyncImage 头像(Apple 无头像显首字母圈)+ 昵称 + 来源 + 红色「退出登录」。
- 数据源页:两个 Section(加密货币/股票)Toggle 列表,绑定 `setSource`。
- 侧栏底栏:有账户 → 头像+displayName;无 → BrandMark+“Axblade”。
- Composer:“+” 变 Menu(分组只列 enabledSources,全禁用显示禁用提示项);选中 → `.sheet` AttachmentSheet(代码输入+查询+预览卡+附加,错误就地红字);TextField 上方 chips 行(capsule:chipText + ✕)。
- [x] **Step 1: 实现全部视图接线,`./scripts/test.sh` 全绿(既有快照仍过)**
- [x] **Step 2: Commit `feat: add account, sources settings and attachment UI`**

### Task 6: 快照/实机验证与收尾

**Files:**
- Modify: `AxbladeTests/SnapshotTests.swift`(新增:账户页已登录态、数据源页、带 chips 的工作区)、`README.md`

- [x] **Step 1: 快照渲染逐张肉眼核对,布局问题修到满意**
- [x] **Step 2: Release 构建启动实机,AX 驱动验证 “+” 菜单与设置三标签可达;curl 实测过的源(Binance/Yahoo)在真机跑一次真实附加**
- [x] **Step 3: README 增账户与数据源章节;`./scripts/test.sh` 全绿;Commit `docs: document accounts and market sources`;合并回 main(finishing skill)**
