import Foundation

/// 界面语言。存进 settings.json;解码遇到未知值落回中文。
enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case zh, en

    /// 语言自身的名字用母语写死,不随当前语言翻译。
    var displayName: String {
        switch self {
        case .zh: "简体中文"
        case .en: "English"
        }
    }

    var strings: L10nStrings {
        switch self {
        case .zh: .zh
        case .en: .en
        }
    }
}

/// 全部界面文案的双语表:默认值即中文表,`en` 逐字段覆盖。
/// `LocalizationTests` 会用反射保证两张表逐字段都不同——漏翻会当场红。
/// 视图经 `viewModel.text` 或 `\.l10n` 环境取词,切换语言即时生效。
struct L10nStrings: Sendable {
    // 侧栏
    var search = "搜索"
    var newChat = "发起新对话"
    var newChatHelp = "新对话 ⌘N"
    var conversationsHeader = "对话"
    var quantToolsHeader = "量化工具"
    var notSignedIn = "未登录"
    var renameAlertTitle = "重命名会话"
    var renameFieldPlaceholder = "名称"
    var rename = "重命名"
    var delete = "删除"
    var cancel = "取消"
    var save = "保存"
    var settingsHelp = "设置 ⌘,"

    // 空状态 / 聊天
    var helloTitle = "你好!"
    var helloSubtitle = "你有什么想法?"
    var generating = "正在生成"
    var codeBlockFallback = "代码"
    var copy = "复制"
    var copied = "已复制"
    var newChatMenu = "新对话"

    // 输入卡
    var askPlaceholder = "问问 ChillSkill"
    var noEnabledSources = "没有启用的数据源(设置 → 数据源)"
    var cryptoSection = "加密货币"
    var equitySection = "股票"
    var attachHelp = "附加行情数据"
    var stopHelp = "停止生成"
    var sendHelp = "发送(Enter)"

    // 附加行情
    var attachSheetTitleFormat = "附加 %@ 行情"
    var query = "查询"
    var fetchingQuote = "正在拉取行情…"
    var attach = "附加"
    var highLowFormat = "高 %@ / 低 %@"
    var cryptoSymbolHint = "如 BTCUSDT、ETH"
    var usSymbolHint = "如 AAPL、TSLA"
    var krSymbolHint = "如 005930(三星电子)"
    var hkSymbolHint = "如 700(腾讯)"
    var aShareSymbolHint = "如 600519(贵州茅台)"

    // 设置
    var settingsGeneral = "通用"
    var settingsAccount = "账户"
    var settingsModels = "模型服务"
    var settingsSources = "数据源"
    var languageLabel = "语言 / Language"
    var modelSectionHeader = "模型"
    var modelFooter = "所有请求经由官方后端 api.chillskill.xyz 转发,客户端不保存、不需要任何 API Key。"
    var sourcesFooter = "启用的源会出现在输入卡的 + 菜单里;行情均为公共数据,无需 API Key。"

    // 账户
    var signInTitle = "登录 ChillSkill"
    var signInSubtitle = "用 GitHub 或 Apple 一键登录;也可以用邮箱注册"
    var signInGitHub = "使用 GitHub 登录"
    var signInApple = "通过 Apple 登录"
    var signInWithEmail = "使用邮箱登录 / 注册"
    var deviceCodeTitle = "在浏览器里输入这个代码"
    var deviceCodeHint = "已在浏览器打开 GitHub 授权页,请输入上面的代码"
    var copyCode = "复制代码"
    var providersLabel = "登录方式"
    var providerPassword = "邮箱"
    var email = "邮箱"
    var password = "密码"
    var confirmPassword = "确认密码"
    var displayName = "显示名"
    var signInButton = "登录"
    var signUpButton = "注册并登录"
    var switchToSignUp = "没有账户?注册"
    var switchToSignIn = "已有账户?登录"
    var signOut = "退出登录"
    var signOutAll = "退出全部设备"
    var planLabel = "套餐"
    var quotaChat = "AI 对话(今日)"
    var quotaMarket = "行情代理(今日)"
    var unlimited = "不限"
    var resetsAtFormat = "重置于 %@"
    var permissionsModels = "可用模型"
    var permissionsSources = "可用行情源"
    var sessionsHeader = "已登录设备"
    var currentSession = "当前"
    var revoke = "吊销"
    var changePassword = "修改密码"
    var currentPassword = "当前密码"
    var newPassword = "新密码"
    var passwordUpdated = "密码已更新"
    var setPassword = "设置密码"
    var setPasswordHint = "当前账号还没有密码。设置之后可以用邮箱 + 密码登录。"
    var reauthSignInAgain = "重新登录"
    var deleteAccount = "删除账号"
    var deleteAccountWarning = "删除后账号、剩余额度与全部登录设备立即失效,且无法恢复。本机的对话记录不会被删除。"
    var deleteAccountPasswordPrompt = "输入当前密码以确认删除"
    var deleteAccountConfirm = "确认删除"
    var lastUsedFormat = "最近使用 %@"
    var keychainWriteFailed = "无法把登录凭据写入钥匙串,请检查系统钥匙串权限后重试"
    var signInRequired = "请先登录(设置 › 账户)后再使用 AI 对话与行情代理"
    var signInBanner = "登录后使用 AI 对话与 Binance 行情代理"
    var openAccountSettings = "去登录"
    var passwordTooShort = "密码至少 8 位"
    var passwordMismatch = "两次输入的密码不一致"
    var refresh = "刷新"

    // Tools 工作区
    var quantToolsSubtitle = "本地原生计算,结果可一键交给 AI 解读 · 仅供研究参考,不构成投资建议"
    var backToTools = "返回工具列表"
    var sourcePicker = "数据源"
    var historyPicker = "历史"
    var daysFormat = "%d 天"
    var fastMAFormat = "快线 MA%d"
    var slowMAFormat = "慢线 MA%d"
    var treesFormat = "树数 %d"
    var depthFormat = "深度 %d"
    var run = "运行"
    var running = "拉取数据并计算中…"
    var analyzeWithAI = "让 AI 解读"
    var disclaimer = "仅供研究参考,不构成投资建议"
    var var95 = "单日 VaR 95%"
    var var99 = "单日 VaR 99%"
    var maxDrawdown = "最大回撤"
    var annualVol = "年化波动率"
    var sharpe = "夏普比率"
    var strategyReturn = "策略收益"
    var holdReturn = "买入持有"
    var annualized = "策略年化"
    var tradeCount = "交易次数"
    var winRate = "胜率"
    var strategyCurve = "策略净值"
    var holdCurve = "买入持有净值"
    var nextDayDirection = "次日方向"
    var predictedReturn = "预测收益"
    var hitRate = "验证集命中率"
    var sampleSplit = "训练/验证样本"
    var keyFeatures = "关键特征"
    var closesCurveFormat = "收盘价(%d 根)"
    var bullish = "看涨"
    var bearish = "看跌"
    var layeredPrefix = "分层"

    // 会话与提示语(进入消息内容,按发送时语言生成)
    var freshConversationTitle = "新对话"
    var marketFallbackTitle = "行情分析"
    var analyzePromptPrefix = "请解读以下量化分析结果,指出关键结论与风险:"
    var sourceNotRegistered = "数据源未注册"

    // 数据源与工具名
    var mexcName = "抹茶 MEXC"
    var usStockName = "美股"
    var krStockName = "韩股"
    var hkStockName = "港股"
    var aShareName = "A股"
    var gbdtName = "梯度提升树模型"
    var riskName = "风控模型"
    var factorToolName = "因子挖掘"
    var backtestName = "历史回测"
    var gbdtSubtitle = "原生 GBDT 预测次日涨跌,给出验证集命中率与特征重要性"
    var riskSubtitle = "历史 VaR、最大回撤、年化波动率、夏普比率"
    var factorSubtitle = "9 个价格类因子的 IC 检验与多空分层,按预测力排序"
    var backtestSubtitle = "双均线交叉策略 vs 买入持有,净值曲线与胜率"

    // 错误描述
    var chatInvalidURL = "后端地址无效,请更新客户端"
    var chatHTTPFormat = "服务返回 HTTP %d:%@"
    var chatStreamFormat = "生成中断:%@"
    var chatEmptyBody = "无响应内容"
    var marketInvalidSymbolFormat = "找不到代码 %@,请检查拼写或换个市场"
    var marketHTTPFormat = "行情服务返回 HTTP %d"
    var marketDecoding = "行情数据解析失败,接口格式可能变了"
    var marketNetworkFormat = "网络请求失败:%@"
    var quantTooShortFormat = "历史数据太短,至少需要 %d 根日线;换个数据源或缩短均线/特征窗口"
    var quantInvalidParameter = "快线周期必须小于慢线周期"
    var accountNotSignedIn = "尚未登录,请先在 设置 › 账户 登录"
    var accountDecoding = "账户接口返回的数据解析失败,请更新客户端"
    var appleNeedsSignedBuild = "Apple 登录需要正式签名的构建(Debug 开发版不可用),请用 GitHub 或邮箱登录"
    var appleSignInCanceled = "已取消 Apple 登录"
    var appleMissingIdentityToken = "Apple 没有返回身份令牌,请重试或改用 GitHub 登录"

    // MARK: - 两张表

    static let zh = L10nStrings()

    static let en: L10nStrings = {
        var s = L10nStrings()
        s.search = "Search"
        s.newChat = "New conversation"
        s.newChatHelp = "New chat ⌘N"
        s.conversationsHeader = "Conversations"
        s.quantToolsHeader = "Quant Tools"
        s.notSignedIn = "Not signed in"
        s.renameAlertTitle = "Rename Conversation"
        s.renameFieldPlaceholder = "Name"
        s.rename = "Rename"
        s.delete = "Delete"
        s.cancel = "Cancel"
        s.save = "Save"
        s.settingsHelp = "Settings ⌘,"
        s.helloTitle = "Hello!"
        s.helloSubtitle = "What's on your mind?"
        s.generating = "Generating"
        s.codeBlockFallback = "code"
        s.copy = "Copy"
        s.copied = "Copied"
        s.newChatMenu = "New Chat"
        s.askPlaceholder = "Ask ChillSkill"
        s.noEnabledSources = "No enabled data sources (Settings → Data Sources)"
        s.cryptoSection = "Crypto"
        s.equitySection = "Stocks"
        s.attachHelp = "Attach market data"
        s.stopHelp = "Stop generating"
        s.sendHelp = "Send (Enter)"
        s.attachSheetTitleFormat = "Attach %@ quote"
        s.query = "Fetch"
        s.fetchingQuote = "Fetching quote…"
        s.attach = "Attach"
        s.highLowFormat = "High %@ / Low %@"
        s.cryptoSymbolHint = "e.g. BTCUSDT, ETH"
        s.usSymbolHint = "e.g. AAPL, TSLA"
        s.krSymbolHint = "e.g. 005930 (Samsung)"
        s.hkSymbolHint = "e.g. 700 (Tencent)"
        s.aShareSymbolHint = "e.g. 600519 (Moutai)"
        s.settingsGeneral = "General"
        s.settingsAccount = "Account"
        s.settingsModels = "Models"
        s.settingsSources = "Data Sources"
        s.languageLabel = "Language / 语言"
        s.modelSectionHeader = "Model"
        s.modelFooter = "All requests are relayed through the official backend api.chillskill.xyz; the client stores no API key and needs none."
        s.sourcesFooter = "Enabled sources appear in the + menu of the composer; all quotes are public data, no API key required."
        s.signInTitle = "Sign in to ChillSkill"
        s.signInSubtitle = "One click with GitHub or Apple — or use an email account"
        s.signInGitHub = "Sign in with GitHub"
        s.signInApple = "Sign in with Apple"
        s.signInWithEmail = "Use email instead"
        s.deviceCodeTitle = "Enter this code in your browser"
        s.deviceCodeHint = "The GitHub authorization page is open in your browser — type the code above"
        s.copyCode = "Copy code"
        s.providersLabel = "Sign-in methods"
        s.providerPassword = "Email"
        s.email = "Email"
        s.password = "Password"
        s.confirmPassword = "Confirm password"
        s.displayName = "Display name"
        s.signInButton = "Sign in"
        s.signUpButton = "Sign up and sign in"
        s.switchToSignUp = "No account? Sign up"
        s.switchToSignIn = "Already have an account? Sign in"
        s.signOut = "Sign out"
        s.signOutAll = "Sign out of all devices"
        s.planLabel = "Plan"
        s.quotaChat = "AI chat (today)"
        s.quotaMarket = "Market proxy (today)"
        s.unlimited = "Unlimited"
        s.resetsAtFormat = "Resets at %@"
        s.permissionsModels = "Available models"
        s.permissionsSources = "Available market sources"
        s.sessionsHeader = "Signed-in devices"
        s.currentSession = "This device"
        s.revoke = "Revoke"
        s.changePassword = "Change password"
        s.currentPassword = "Current password"
        s.newPassword = "New password"
        s.passwordUpdated = "Password updated"
        s.setPassword = "Set a password"
        s.setPasswordHint = "This account has no password yet. Set one to also sign in with email + password."
        s.reauthSignInAgain = "Sign in again"
        s.deleteAccount = "Delete account"
        s.deleteAccountWarning = "Deleting your account immediately voids it along with any remaining quota and every signed-in device. This cannot be undone. Conversations stored on this Mac are kept."
        s.deleteAccountPasswordPrompt = "Enter your current password to confirm"
        s.deleteAccountConfirm = "Delete permanently"
        s.lastUsedFormat = "Last used %@"
        s.keychainWriteFailed = "Could not store your credentials in the Keychain — check Keychain access and try again"
        s.signInRequired = "Sign in first (Settings › Account) to use AI chat and the market proxy"
        s.signInBanner = "Sign in to use AI chat and the Binance market proxy"
        s.openAccountSettings = "Sign in"
        s.passwordTooShort = "Password must be at least 8 characters"
        s.passwordMismatch = "The two passwords do not match"
        s.refresh = "Reload"
        s.quantToolsSubtitle = "Native local computation; hand results to AI in one click · For research only, not investment advice"
        s.backToTools = "Back to tools"
        s.sourcePicker = "Source"
        s.historyPicker = "History"
        s.daysFormat = "%d days"
        s.fastMAFormat = "Fast MA%d"
        s.slowMAFormat = "Slow MA%d"
        s.treesFormat = "Trees %d"
        s.depthFormat = "Depth %d"
        s.run = "Run"
        s.running = "Fetching data and computing…"
        s.analyzeWithAI = "Ask AI to interpret"
        s.disclaimer = "For research only, not investment advice"
        s.var95 = "1-day VaR 95%"
        s.var99 = "1-day VaR 99%"
        s.maxDrawdown = "Max drawdown"
        s.annualVol = "Annualized volatility"
        s.sharpe = "Sharpe ratio"
        s.strategyReturn = "Strategy return"
        s.holdReturn = "Buy & hold"
        s.annualized = "Strategy annualized"
        s.tradeCount = "Trades"
        s.winRate = "Win rate"
        s.strategyCurve = "Strategy equity"
        s.holdCurve = "Buy & hold equity"
        s.nextDayDirection = "Next-day direction"
        s.predictedReturn = "Predicted return"
        s.hitRate = "Validation hit rate"
        s.sampleSplit = "Train/validation samples"
        s.keyFeatures = "Key features"
        s.closesCurveFormat = "Close prices (%d bars)"
        s.bullish = "Bullish"
        s.bearish = "Bearish"
        s.layeredPrefix = "spread"
        s.freshConversationTitle = "New conversation"
        s.marketFallbackTitle = "Market analysis"
        s.analyzePromptPrefix = "Please interpret the following quantitative analysis, highlighting key conclusions and risks:"
        s.sourceNotRegistered = "Data source not registered"
        s.mexcName = "MEXC"
        s.usStockName = "US Stocks"
        s.krStockName = "KR Stocks"
        s.hkStockName = "HK Stocks"
        s.aShareName = "A-Shares"
        s.gbdtName = "Gradient Boosted Trees"
        s.riskName = "Risk Model"
        s.factorToolName = "Factor Mining"
        s.backtestName = "Backtest"
        s.gbdtSubtitle = "Native GBDT predicts next-day direction with validation hit rate and feature importance"
        s.riskSubtitle = "Historical VaR, max drawdown, annualized volatility, Sharpe ratio"
        s.factorSubtitle = "IC test and long-short layering of 9 price factors, ranked by predictive power"
        s.backtestSubtitle = "Dual moving-average crossover vs buy & hold, with equity curves and win rate"
        s.chatInvalidURL = "Invalid backend address — please update the app"
        s.chatHTTPFormat = "Server returned HTTP %d: %@"
        s.chatStreamFormat = "Generation interrupted: %@"
        s.chatEmptyBody = "empty response body"
        s.marketInvalidSymbolFormat = "Symbol %@ not found — check the spelling or try another market"
        s.marketHTTPFormat = "Quote service returned HTTP %d"
        s.marketDecoding = "Failed to parse quote data — the API format may have changed"
        s.marketNetworkFormat = "Network request failed: %@"
        s.quantTooShortFormat = "Not enough history — at least %d daily bars needed; try another source or shorter windows"
        s.quantInvalidParameter = "Fast MA period must be shorter than the slow one"
        s.accountNotSignedIn = "Not signed in yet — sign in under Settings › Account first"
        s.accountDecoding = "Could not parse the account response — please update the app"
        s.appleNeedsSignedBuild = "Sign in with Apple needs a properly signed build (unavailable in Debug builds) — use GitHub or email instead"
        s.appleSignInCanceled = "Apple sign-in canceled"
        s.appleMissingIdentityToken = "Apple returned no identity token — try again or sign in with GitHub"
        return s
    }()

    // MARK: - 派生文案

    func sourceName(_ kind: MarketSourceKind) -> String {
        switch kind {
        case .binance: "Binance"
        case .okx: "OKX"
        case .mexc: mexcName
        case .usStock: usStockName
        case .krStock: krStockName
        case .hkStock: hkStockName
        case .aShare: aShareName
        }
    }

    func toolName(_ tool: QuantTool) -> String {
        switch tool {
        case .gbdt: gbdtName
        case .risk: riskName
        case .factor: factorToolName
        case .backtest: backtestName
        }
    }

    func toolSubtitle(_ tool: QuantTool) -> String {
        switch tool {
        case .gbdt: gbdtSubtitle
        case .risk: riskSubtitle
        case .factor: factorSubtitle
        case .backtest: backtestSubtitle
        }
    }

    func symbolHint(_ source: MarketSourceKind) -> String {
        switch source {
        case .binance, .okx, .mexc: cryptoSymbolHint
        case .usStock: usSymbolHint
        case .krStock: krSymbolHint
        case .hkStock: hkSymbolHint
        case .aShare: aShareSymbolHint
        }
    }

    /// GBDT 引擎返回中文方向("看涨"/"看跌"),展示前按语言映射。
    func direction(_ raw: String) -> String {
        switch raw {
        case "看涨": bullish
        case "看跌": bearish
        default: raw
        }
    }

    /// 各处 catch 的统一出口:已知错误按当前语言描述,未知错误原样透传。
    func describe(_ error: Error) -> String {
        switch error {
        case let error as ChatServiceError: describeChat(error)
        case let error as MarketDataError: describeMarket(error)
        case let error as QuantError: describeQuant(error)
        case let error as AccountError: describeAccount(error)
        case let error as AppleSignInError: describeApple(error)
        default: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func describeChat(_ error: ChatServiceError) -> String {
        switch error {
        case .invalidURL:
            return chatInvalidURL
        case .http(let status, let body):
            // 后端的 {"error":{"message"}} 直接取 message,别把原始 JSON 甩给用户。
            let text = (Self.backendMessage(in: body) ?? body)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmed = text.isEmpty ? chatEmptyBody
                : (text.count > 300 ? String(text.prefix(300)) + "…" : text)
            return String(format: chatHTTPFormat, status, trimmed)
        case .stream(let message):
            return String(format: chatStreamFormat, message)
        }
    }

    /// 从后端错误体里取 `error.message`;不是这个形状就返回 nil。
    static func backendMessage(in body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any],
              let message = error["message"] as? String, !message.isEmpty
        else { return nil }
        return message
    }

    private func describeMarket(_ error: MarketDataError) -> String {
        switch error {
        case .invalidSymbol(let symbol): String(format: marketInvalidSymbolFormat, symbol)
        case .http(let status): String(format: marketHTTPFormat, status)
        case .decoding: marketDecoding
        case .network(let message): String(format: marketNetworkFormat, message)
        }
    }

    private func describeQuant(_ error: QuantError) -> String {
        switch error {
        case .tooShort(let minimum): String(format: quantTooShortFormat, minimum)
        case .invalidParameter: quantInvalidParameter
        }
    }

    /// Apple 登录只有**客户端本地**的失败走这里(后端失败走 AccountError)。
    private func describeApple(_ error: AppleSignInError) -> String {
        switch error {
        case .needsSignedBuild: appleNeedsSignedBuild
        case .canceled: appleSignInCanceled
        case .missingIdentityToken: appleMissingIdentityToken
        }
    }

    /// 后端错误一律用它自己的 `error.message`(已是可读文案),客户端只翻译本地态。
    private func describeAccount(_ error: AccountError) -> String {
        switch error {
        case .notSignedIn: accountNotSignedIn
        case .http(_, let message, _): message
        case .decoding: accountDecoding
        }
    }
}
