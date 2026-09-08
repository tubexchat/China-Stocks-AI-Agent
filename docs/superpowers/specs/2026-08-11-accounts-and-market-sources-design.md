# Axblade 账户登录与金融数据源 — 设计规格

日期:2026-08-11
状态:已定稿(设计已经用户确认;后端 API 由用户另行立项,本仓库只做前端)
定位:Axblade 是纯金融数据分析的 AI 工具。

## 1. 目标

1. **账户**:设置中支持登录/退出,登录方式为 GitHub 与 Apple。当前无后端,
   登录仅做本地身份展示(侧栏底部头像+昵称);认证抽象成协议,后端上线后换实现即可。
2. **数据源**:输入卡 “+” 变为数据源菜单,支持 Binance、OKX、抹茶(MEXC)、
   美股、韩股、港股、A股 共 7 个源。用户选源→输入代码→预览行情→附加到对话,
   行情数据以可见文本块并入用户消息发给 AI 分析。
3. 设置窗口扩展为三个标签:**账户 / 模型服务 / 数据源**。

**非目标(本期不做)**:AI 自动工具调用(接口留好)、交易所私有资产(API Key)、
云同步、WebSocket 实时推送。

## 2. 账户

### 模型与存储

- `enum AuthProviderKind: String, Codable { case github, apple }`
- `struct UserAccount: Codable, Equatable { provider, id, displayName, handle?, avatarURL?, linkedAt }`
- 账户存 `account.json`(ConversationStore 新增 loadAccount/saveAccount,传 nil 删文件);
  token/secret 存钥匙串(KeychainStore 新增字符串 account 的通用 API)。
- 退出登录 = 删 account.json + 删钥匙串 token。

### AuthProvider 协议

```swift
protocol AuthProvider {
    func signIn() async throws -> SignedInUser   // SignedInUser { account, secret: String? }
}
```

- **GitHubAuthProvider — Device Flow**(原生 app 无需 client secret):
  1. POST github.com/login/device/code(client_id, scope=read:user)→ user_code/verification_uri/interval
  2. UI 展示用户码 + 打开浏览器;按 interval 轮询 login/oauth/access_token
  3. 拿到 token 后 GET api.github.com/user → login/name/avatar_url
  - `AuthConfig.githubClientID` 常量,默认空;为空时报中文错误提示注册 OAuth App 并启用 Device Flow。
  - 传输层可注入(URLProtocol mock),轮询/解析全部可测。
- **AppleAuthProvider**:AuthenticationServices 系统登录框。凭证→UserAccount 的映射为纯函数可测;
  ad-hoc 开发签名无法满足 Sign in with Apple entitlement,运行时报错以中文提示
  (需开发者账号签名)。**不**预置 `com.apple.developer.applesignin` entitlement——
  受限 entitlement 配 ad-hoc 签名会被系统拒载;正式签名发布时再加。
- 后端上线后:新增「后端代理 OAuth」实现同一协议,UI/存储不动。

### UI

- 设置「账户」标签:未登录 → GitHub 登录按钮 + SignInWithAppleButton;
  GitHub 流程中显示用户码/等待态/取消。已登录 → 头像(GitHub 拉 avatarURL,Apple 显首字母圈)、
  昵称、来源徽标、「退出登录」。
- 侧栏底部:已登录显示头像+昵称(替代 “Axblade” 文案),齿轮不变。

## 3. 数据源

### 源清单

```swift
enum MarketSourceKind: String, Codable, CaseIterable {
    case binance, okx, mexc          // 加密货币,公共 REST
    case usStock, krStock, hkStock, aShare   // 股票,统一走 Yahoo Finance v8 chart
}
```

- 每源:displayName(中文)、category(加密货币/股票)。默认全部启用;
  `AppSettings.disabledSources: Set<MarketSourceKind>`(存禁用集合,新增源默认开)。
- **兼容性**:AppSettings 新字段一律 `decodeIfPresent`,旧 settings.json 不得因缺 key 而整体解码失败。

### 行情服务

```swift
protocol MarketDataService: Sendable {
    func snapshot(rawSymbol: String) async throws -> MarketSnapshot
}
```

- `MarketSnapshot { source, symbol, name?, price, changePercent24h?, high?, low?, volume?, currency?, closes: [Double](旧→新,≤30 根日线), fetchedAt }`
- `promptText`:紧凑中文数据块(来源/代码/时间戳/现价/24h 涨跌/高低/量/近 30 日收盘序列);
  `chipText`:如 “BTCUSDT +2.31%”。
- 实现与端点:
  - Binance:`/api/v3/ticker/24hr` + `/api/v3/klines?interval=1d&limit=30`
  - OKX:`/api/v5/market/ticker` + `/api/v5/market/candles?bar=1D`(注意 data 数组新→旧,需反转)
  - MEXC:`/api/v3/ticker/24hr` + `/api/v3/klines`(Binance 兼容形状)
  - Yahoo(四个股票市场共用):`query1.finance.yahoo.com/v8/finance/chart/{symbol}?range=1mo&interval=1d`,
    带浏览器 User-Agent;现价/前收/币种取 meta,收盘序列取 indicators.quote[0].close。
- **代码归一化(纯函数,重点单测)**:
  - Binance/MEXC:大写、去 `-`/`/`;无报价后缀(如 `btc`)补 `USDT`。
  - OKX:大写、转 `BASE-QUOTE`(识别 USDT/USDC/BTC/ETH/USD 后缀;`BTC`→`BTC-USDT`)。
  - 美股:大写原样;韩股:纯数字→`.KS`;港股:数字→去前导零补足 4 位→`.HK`;
    A股:6/9 开头→`.SS`,0/3 开头→`.SZ`;凡含 `.` 的输入尊重用户后缀。
- 错误:`MarketDataError: LocalizedError`(中文):代码不存在/网络失败/HTTP 状态/解析失败。

### 附加流程

- 输入卡 “+” → Menu(按「加密货币」「股票」分组,只列启用的源;全禁用时显示提示项)。
  「新对话」入口保留在侧栏与 ⌘N。
- 选源 → sheet:代码输入框 + 查询 → 预览行情卡 → 「附加」;错误就地显示在 sheet 内。
- `AppViewModel` 新增 `pendingAttachments: [MarketSnapshot]`、`marketServices: [MarketSourceKind: MarketDataService]`(可注入 fake)。
- 发送合并规则:用户文本在前,数据块在后;**标题仍取用户输入的文字**(无文字仅附数据时取首个 symbol);
  允许只附数据不写字发送;发送后清空 pending;chip 可单个移除。

## 4. 测试与验收

- 单测(TDD):代码归一化 7 条路径、四家请求构造、四家响应解析(真实端点抓取的 JSON fixture)、
  promptText/chipText 格式、AppSettings 旧文件兼容、账户往返与钥匙串字符串 API、
  GitHub Device Flow(URLProtocol 按 URL 路由的 mock:pending→token→user 全链路 + denied)、
  AppViewModel 附加/合并/标题/清空。
- 快照:设置三标签、带 chip 的输入卡、附加 sheet 预览、已登录侧栏。
- 实现期用 curl 验证四家真实端点形状后再固化 fixture。
