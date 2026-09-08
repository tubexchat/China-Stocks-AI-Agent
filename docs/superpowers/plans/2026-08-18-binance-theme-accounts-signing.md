# Mac:Binance 主题 + 后端账户登录(额度/权限)+ App Store 签名配置 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mac 客户端换成 Binance 风格(与 Web 同一套 token),登录改为官方后端邮箱+密码账户(登录后可看额度与数据权限;未登录不能用 AI/行情代理),并把工程配置成可用 Team `A2SZ953D3V` 自动签名、Hardened Runtime、可 archive 上传 App Store 的状态。

**Architecture:** 删除 GitHub/Apple 登录,新增 `AccountService`(打 `Backend.baseURL` 的 `/auth/*`、`/me*`),令牌存 Keychain(`auth.backend`),`TokenStore` 统一给 `ChatService` / `BinanceMarketService` 供令牌;`AppViewModel` 持有 `session`/`me`;`AccountSettingsView` 变成登录表单 + 账户仪表盘;`Theme` 镜像 Web 的 `design-tokens.json`;`project.yml` 落签名/上架设置,`scripts/release.sh` + `ExportOptions/*.plist` + 上架手册。

**Tech Stack:** Swift 6 / SwiftUI,macOS 14+,XcodeGen 2.45,Xcode 26.5,XCTest(`MockHTTPProtocol` 已有)。

**Spec:** `/Users/ubuntu/Desktop/axblade/Axblade-API-AI/docs/superpowers/specs/2026-08-18-accounts-quota-permissions-design.md`(第二、四节;API 契约见 1.4/1.5)。设计 token 唯一来源:`/Users/ubuntu/Desktop/axblade/ChillSkill-Website/design-tokens.json`。

## Global Constraints

- 零第三方依赖;`ARCHS=arm64`;`SWIFT_VERSION=6.0`(严格并发,注意 `Sendable`)
- 每次改完 `project.yml` 或新增文件后 `xcodegen generate`;测试用 `./scripts/test.sh`(必须 `** TEST SUCCEEDED **`)
- `LocalizationTests` 用反射保证 zh/en 每个字段都不同——新增文案两边都要写且不同
- 客户端**不再内置任何访问令牌**(`Backend.accessToken` 删除);令牌只在 Keychain
- 错误信息以后端 `error.message` 为准(已是中文/可读),客户端不再自己编 401/403/429 文案,只加前缀
- App Store:App Sandbox + `network.client` entitlement 保留;Hardened Runtime 开;不加 Sign in with Apple entitlement
- 兼容:老版本客户端用 legacy 令牌继续可用(后端保证),本仓库不需要迁移逻辑

---

### Task 1: Theme 镜像 Binance token + 测试守护

**Files:** Modify `Axblade/Views/Theme.swift`;Create `AxbladeTests/ThemeTokenTests.swift`;Modify 用到 `Theme.glow` 的视图(`grep -rn "Theme.glow" Axblade`)

**Interfaces:**
- `Theme` 新增/改值(dark/light 与 JSON 一致):`background(#0B0E11/#FFFFFF)`, `sidebar = surface(#181A20/#FAFAFA)`, `surface(#181A20/#FAFAFA)`, `surface2(#1E2329/#F5F5F5)`(原 `composer` 改名为 `surface2`,保留 `composer` 作为别名), `elevated(#2B3139/#EAECEF)`(原 `selection` 改为此值并保留 `selection` 别名), `border(#2B3139/#EAECEF)`, `text(#EAECEF/#1E2329)`, `muted(#848E9C/#707A8A)`, `disabled(#5E6673/#B7BDC6)`, `accent(#FCD535/#FCD535)`, `accentStrong(#F0B90B)`, `onAccent(#181A20)`, `accentSoft`(accent opacity 0.12/0.16), `up(#0ECB81)`, `down(#F6465D)`, `glow` → 改为 `accentSoft`(去光晕)
- 暴露 `static let tokens: [String: (dark: UInt32, light: UInt32)]` 供测试断言

- [ ] **Step 1:** 失败测试 `ThemeTokenTests`:断言 `Theme.tokens["accent"] == (0xFCD535, 0xFCD535)`、`background == (0x0B0E11, 0xFFFFFF)`、`up == (0x0ECB81,0x0ECB81)`、`down == (0xF6465D,0xF6465D)`、`surface2 == (0x1E2329, 0xF5F5F5)`、`text == (0xEAECEF, 0x1E2329)`、`muted == (0x848E9C, 0x707A8A)`;文件头注释写明「与 ChillSkill-Website/design-tokens.json 保持一致」
- [ ] **Step 2:** `./scripts/test.sh` 红 → 实现 Theme → 绿
- [ ] **Step 3:** 视图微调:`BrandMark` 用 accent 黄;侧栏选中用 `Theme.elevated`;输入卡 `Theme.surface2`;`ToolsView` 里涨跌/正负数用 `Theme.up`/`Theme.down`(grep `.green`/`.red`/`Color.green` 替换);数字文本加 `.monospacedDigit()`;按钮圆角统一 6–8
- [ ] **Step 4:** `xcodebuild build … Release` 无警告级错误;`./scripts/test.sh` 全绿(SnapshotTests 会重渲染);Commit `feat(theme): Binance 深/浅色 token(与 Web design-tokens.json 一致)`

### Task 2: AccountService + TokenStore(替换 GitHub/Apple)

**Files:** Delete `Axblade/Services/AuthProviders.swift`, `AxbladeTests/GitHubAuthTests.swift`;Modify `Axblade/Models/AccountModels.swift`, `Axblade/Services/Backend.swift`, `Axblade/Services/ChatService.swift:45`, `Axblade/Services/CryptoMarketServices.swift:12`, `AxbladeTests/AccountModelsTests.swift`, `AxbladeTests/LiveNetworkSmokeTests.swift`(去掉 AuthProvider 引用);Create `Axblade/Services/AccountService.swift`, `AxbladeTests/AccountServiceTests.swift`

**Interfaces:**
```swift
// AccountModels.swift(替换旧内容)
struct QuotaBucket: Codable, Equatable, Sendable { var limit: Int?; var used: Int; var remaining: Int?; var reset_at: String }
struct ModelPermission: Codable, Equatable, Sendable, Identifiable { var alias: String; var display_name: String; var id: String { alias } }
struct MarketSourcePermission: Codable, Equatable, Sendable, Identifiable { var id: String; var label: String; var paths: [String] }
struct MeUser: Codable, Equatable, Sendable { var id: Int; var email: String?; var display_name: String; var plan: String; var created_at: String; var kind: String }
struct MePlan: Codable, Equatable, Sendable { var name: String; var chat_requests_per_day: Int?; var market_requests_per_day: Int? }
struct MeSession: Codable, Equatable, Sendable { var id: Int; var client: String; var created_at: String }
struct MeResponse: Codable, Equatable, Sendable { var user: MeUser; var plan: MePlan; var quota: [String: QuotaBucket]; var permissions: Permissions; var session: MeSession?
    struct Permissions: Codable, Equatable, Sendable { var models: [ModelPermission]; var market_sources: [MarketSourcePermission] } }
struct SessionRow: Codable, Equatable, Sendable, Identifiable { var id: Int; var client: String; var created_at: String; var last_used_at: String; var current: Bool }
struct UsageDay: Codable, Equatable, Sendable, Identifiable { var day: String; var chat_requests: Int; var chat_tokens: Int; var market_requests: Int; var id: String { day } }
/// 本地缓存的账户摘要(不含令牌),存 account.json 供离线启动显示。
struct UserAccount: Codable, Equatable, Sendable { var email: String; var displayName: String; var plan: String }

// Backend.swift:删除 accessToken;新增
enum TokenStore { static let keychainAccount = "auth.backend"
    static func token() -> String? { KeychainStore.secret(account: keychainAccount) }
    static func set(_ t: String?) { t.map { KeychainStore.setSecret($0, account: keychainAccount) } ?? KeychainStore.deleteSecret(account: keychainAccount) } }

// AccountService.swift
enum AccountError: LocalizedError, Equatable { case notSignedIn, http(Int, String /*server message*/, String? /*code*/), decoding }
struct AccountService: Sendable {
    var session: URLSession = .shared
    var baseURL: String = Backend.baseURL            // ".../v1"
    var tokenProvider: @Sendable () -> String? = { TokenStore.token() }
    func signup(email: String, password: String, displayName: String) async throws -> String /*token*/
    func login(email: String, password: String) async throws -> String
    func logout() async throws                        // POST /auth/logout(204)
    func logoutAll() async throws
    func changePassword(current: String, new: String) async throws
    func me() async throws -> MeResponse
    func usage(days: Int) async throws -> [UsageDay]
    func sessions() async throws -> [SessionRow]
    func revokeSession(id: Int) async throws
}
```
- 请求体 `client: "mac"`;非 2xx 解析 `{"error":{"message","code"}}` → `AccountError.http(status, message, code)`;`ChatService`/`BinanceMarketService` 改为 `if let t = TokenStore.token() { setValue("Bearer \(t)") }`;`OpenAIChatService.buildRequest` 加参数 `token: String?`(默认 `TokenStore.token()`)方便测试

- [ ] **Step 1:** 失败测试 `AccountServiceTests`(用 `MockHTTPProtocol.install/session()`):login 发 `POST …/auth/login` 且 body 含 email/password/client=mac,200 → 返回 token;401 body `{"error":{"message":"邮箱或密码错误","code":"invalid_credentials"}}` → 抛 `.http(401,"邮箱或密码错误","invalid_credentials")`;`me()` 解码 spec 1.5 的示例 JSON(quota["chat"].limit == 50,permissions.models.first?.alias == "deepseek");`me()` 未登录(tokenProvider 返回 nil)→ 抛 `.notSignedIn` 且**不发请求**;`OpenAIChatService.buildRequest(token: "axb_x")` 头为 `Bearer axb_x`,`token: nil` 时无 Authorization 头
- [ ] **Step 2:** 红 → 实现 → 绿;删除旧 provider 与其测试;`AccountModelsTests` 改为测新模型解码;`LiveNetworkSmokeTests` 里若有内置令牌真机调用,改为「无令牌时跳过(XCTSkip)」
- [ ] **Step 3:** Commit `feat(account): 后端邮箱登录 AccountService,移除 GitHub/Apple 登录与内置令牌`

### Task 3: AppViewModel 账户状态

**Files:** Modify `Axblade/ViewModels/AppViewModel.swift`, `Axblade/Services/ConversationStore.swift`(account.json 存新 `UserAccount`), `AxbladeTests/AppViewModelTests.swift`

**Interfaces:**
```swift
@Published private(set) var account: UserAccount?      // 本地摘要(离线可见)
@Published private(set) var me: MeResponse?             // 最近一次 /v1/me
@Published private(set) var isAuthBusy = false
@Published var authError: String?
var accountService: AccountService
var isSignedIn: Bool { TokenStore.token() != nil }
func signIn(email: String, password: String) async     // 成功:存令牌、拉 me、写 account.json、authError=nil
func signUp(email: String, password: String, displayName: String) async
func refreshMe() async                                   // 401 → signOutLocally()
func signOut() async                                     // 调 logout(失败也忽略)→ signOutLocally()
func signOutLocally()                                    // 清 Keychain、account、me
func changePassword(current: String, new: String) async throws
func revokeSession(id: Int) async
```
- 初始化:`account = store.loadAccount()`;若 `isSignedIn` 则 `Task { await refreshMe() }`
- `send()`:若 `!isSignedIn` → 直接落一条报错气泡 `text.signInRequired` 并 return(不发网络)
- 流式失败若是 `ChatServiceError.http(401, _)` → `signOutLocally()`;`http(429,…)`/`http(403,…)` 原样展示后端 message

- [ ] **Step 1:** 失败测试:`AppViewModelTests` 加 —— 未登录 `send()` 追加 isError 气泡且 `service` 未被调用(用现有的 fake service 计数);`signIn` 成功后 `account?.email == "a@b.c"` 且 Keychain 有令牌(测试后清理);`refreshMe` 遇 401 清空 account
- [ ] **Step 2:** 实现;绿;Commit `feat(account): ViewModel 登录状态、未登录拦截、401 自动登出`

### Task 4: AccountSettingsView(登录表单 + 仪表盘)+ 侧栏 + Composer 横幅 + 文案

**Files:** Rewrite `Axblade/Views/AccountSettingsView.swift`;Modify `Axblade/Views/SidebarView.swift:196-215`, `Axblade/Views/ComposerView.swift`, `Axblade/Services/Localization.swift`(删 GitHub/Apple/deviceCode 文案,加下列)

**文案(zh → en 都要写):** `signInTitle "登录 Axblade"`, `signInSubtitle "使用 chillskill.xyz 账户;还没有账户可直接注册"`, `email "邮箱"`, `password "密码"`, `confirmPassword "确认密码"`, `displayName "显示名"`, `signInButton "登录"`, `signUpButton "注册并登录"`, `switchToSignUp "没有账户?注册"`, `switchToSignIn "已有账户?登录"`, `signOut "退出登录"`, `signOutAll "退出全部设备"`, `planLabel "套餐"`, `quotaChat "AI 对话(今日)"`, `quotaMarket "行情代理(今日)"`, `unlimited "不限"`, `resetsAtFormat "重置于 %@"`, `permissionsModels "可用模型"`, `permissionsSources "可用行情源"`, `sessionsHeader "已登录设备"`, `currentSession "当前"`, `revoke "吊销"`, `changePassword "修改密码"`, `currentPassword "当前密码"`, `newPassword "新密码"`, `passwordUpdated "密码已更新"`, `signInRequired "请先登录(设置 › 账户)后再使用 AI 对话与行情代理"`, `signInBanner "登录后使用 AI 对话与 Binance 行情代理"`, `openAccountSettings "去登录"`, `passwordTooShort "密码至少 8 位"`, `passwordMismatch "两次输入的密码不一致"`, `refresh "刷新"`

**视图:**
- 未登录:分段控件 登录/注册;`TextField(email)`、`SecureField(password)`(注册多 displayName、confirm);校验通过才启用按钮;错误红字;`isAuthBusy` 时 ProgressView
- 已登录:顶部邮箱 + 套餐徽章(`Theme.accentSoft` 底 `Theme.accent` 字);两条额度 `ProgressView(value:)`(limit nil → 文本「不限」)+ 「重置于」;权限两组 chips(模型 display_name;行情源 label + paths);已登录设备列表(client / created_at / 当前 / 吊销);修改密码折叠区;底部「刷新」「退出登录」「退出全部设备」
- 侧栏底部:已登录显示邮箱首字母圈 + email(lineLimit 1)+ 套餐小徽章;未登录仍显示「未登录」
- Composer:`!viewModel.isSignedIn` 时输入卡上方一条 `Theme.accentSoft` 横幅:`signInBanner` + `SettingsLink { Text(openAccountSettings) }`

- [ ] **Step 1:** 文案(zh/en)→ `./scripts/test.sh` 里 `LocalizationTests` 绿
- [ ] **Step 2:** 视图实现;`xcodebuild build` 通过;SnapshotTests 通过(如快照测试断言了旧登录页元素,更新断言)
- [ ] **Step 3:** Commit `feat(ui): 账户页登录/注册与额度权限仪表盘,侧栏与输入卡登录提示`

### Task 5: 签名 / 上架工程配置

**Files:** Modify `project.yml`, `Axblade/App/Info.plist`, `README.md`;Create `ExportOptions/AppStore.plist`, `ExportOptions/DeveloperID.plist`, `scripts/release.sh`, `docs/app-store-submission.md`;`.gitignore` 加 `build/`、`*.xcarchive`、`ExportOptions/*.local.plist`

**project.yml 变更:**
```yaml
settings:
  base:
    ARCHS: arm64
    SWIFT_VERSION: "6.0"
    MACOSX_DEPLOYMENT_TARGET: "14.0"
    DEVELOPMENT_TEAM: A2SZ953D3V
    CODE_SIGN_STYLE: Automatic
    MARKETING_VERSION: "0.3.0"
    CURRENT_PROJECT_VERSION: "3"
targets:
  Axblade:
    info:
      properties:
        …(原有)
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        LSApplicationCategoryType: public.app-category.finance
        ITSAppUsesNonExemptEncryption: false
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: io.primit.axblade
        ENABLE_HARDENED_RUNTIME: true
        CODE_SIGN_IDENTITY: "Apple Development"
      configs:
        Release:
          CODE_SIGN_IDENTITY: "Apple Development"   # archive 时由 exportOptions 决定分发签名
```
(测试 target 保持 `CODE_SIGN_IDENTITY: "-"`、`CODE_SIGN_STYLE: Manual` 免签)

**ExportOptions/AppStore.plist:** `method=app-store-connect`, `teamID=A2SZ953D3V`, `signingStyle=automatic`, `uploadSymbols=true`, `destination=upload`;**DeveloperID.plist:** `method=developer-id`, `teamID`, `signingStyle=automatic`, `destination=export`

**scripts/release.sh:**
```bash
#!/usr/bin/env bash
# 用法: scripts/release.sh archive | export-appstore | export-devid | notarize <app-or-dmg>
set -euo pipefail; cd "$(dirname "$0")/.."
ARCHIVE=build/Axblade.xcarchive
case "${1:-}" in
  archive) xcodegen generate >/dev/null
    xcodebuild archive -project Axblade.xcodeproj -scheme Axblade -configuration Release \
      -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" -allowProvisioningUpdates | tail -5 ;;
  export-appstore) xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist ExportOptions/AppStore.plist \
      -exportPath build/appstore -allowProvisioningUpdates ;;
  export-devid) xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist ExportOptions/DeveloperID.plist \
      -exportPath build/devid -allowProvisioningUpdates ;;
  notarize) xcrun notarytool submit "$2" --keychain-profile AC_NOTARY --wait && xcrun stapler staple "$2" ;;
  *) echo "usage: $0 archive|export-appstore|export-devid|notarize <path>"; exit 2 ;;
esac
```
**docs/app-store-submission.md:** 已自动化项(签名配置、archive、export/upload 命令、隐私政策 URL `https://chillskill.xyz/en/privacy`、分类、加密豁免、沙盒)/ 需要账号本人一次性操作(Xcode › Settings › Accounts 登录 zhangweiteakwondo@qq.com;App Store Connect 新建 App:名称 Axblade、Bundle ID io.primit.axblade、SKU axblade-mac;`notarytool store-credentials AC_NOTARY`(App 专用密码);截图 1280×800/1440×900/2560×1600/2880×1800;审核备注给测试账号)/ 提交流程与常见报错

- [ ] **Step 1:** 改 `project.yml`、Info.plist;`xcodegen generate`;`xcodebuild build -configuration Release` 通过(自动签名用本机 Apple Development 证书);`codesign -dv --entitlements - build/…/Axblade.app` 显示 `flags=0x10000(runtime)` 与 sandbox entitlement
- [ ] **Step 2:** `./scripts/release.sh archive` 试跑;成功则 `./scripts/release.sh export-devid` 试跑(需要账号会话时会报错,把错误原文记进手册「需要本人操作」段);不因失败阻塞
- [ ] **Step 3:** `./scripts/test.sh` 全绿;README「构建/发布/上架」段更新;Commit `chore(release): 自动签名 Team A2SZ953D3V、Hardened Runtime、上架元数据与发布脚本/手册`

### Task 6: 文档收尾与推送

- [ ] README:登录说明改为「官方后端账户(邮箱+密码,可在 chillskill.xyz 注册)」,写清额度/权限展示位置、Binance 主题与 token 来源;架构树更新(去 AuthProviders,加 AccountService)
- [ ] `./scripts/test.sh` 全绿;`git status` 干净;`git push origin main`
