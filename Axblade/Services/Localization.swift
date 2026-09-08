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
    // 产品
    var appName = "A股智能体"
    var appTagline = "涨停情绪 · 龙虎榜资金 · 热度雷达 · 全市场趋势"

    // 侧栏
    var search = "搜索"
    var newChat = "发起新对话"
    var newChatHelp = "新对话 ⌘N"
    var conversationsHeader = "对话"
    var workspaceChat = "对话"
    var workspaceModules = "盘面"
    var modulesHeader = "盘面模块"
    var notSignedIn = "未登录"
    var renameAlertTitle = "重命名会话"
    var renameFieldPlaceholder = "名称"
    var rename = "重命名"
    var delete = "删除"
    var cancel = "取消"
    var save = "保存"
    var settingsHelp = "设置 ⌘,"

    // 空状态 / 聊天
    var helloTitle = "你好,我是 A股智能体"
    var helloSubtitle = "问我涨停情绪、龙虎榜资金、板块趋势,或直接给一个股票代码"
    var suggestionLimitUp = "今天涨停情绪怎么样?"
    var suggestionDragonTiger = "昨天龙虎榜有哪些游资在买?"
    var suggestionHeat = "现在热度最高的股票是哪些?"
    var suggestionStock = "分析一下 600519"
    var generating = "正在生成"
    var codeBlockFallback = "代码"
    var copy = "复制"
    var copied = "已复制"
    var newChatMenu = "新对话"
    var contextAttachedFormat = "已附带实时数据:%@"

    // 输入卡
    var askPlaceholder = "问问 A股智能体,或输入股票代码…"
    var attachHelp = "附加 A 股行情"
    var attachQuote = "附加个股行情"
    var attachModuleReport = "附加模块报告"
    var stopHelp = "停止生成"
    var sendHelp = "发送(Enter)"
    var agentAutoContextLabel = "智能体自动附带实时数据"
    var agentAutoContextHint = "按问题意图自动拉取涨停 / 龙虎榜 / 热榜 / 指数与个股快照,拼进消息给模型"

    // 附加行情
    var attachSheetTitle = "附加 A 股行情"
    var query = "查询"
    var fetchingQuote = "正在拉取行情…"
    var attach = "附加"
    var highLowFormat = "高 %@ / 低 %@"
    var aShareSymbolHint = "如 600519、000001、300750"

    // 设置
    var settingsGeneral = "通用"
    var settingsAccount = "账户"
    var settingsModels = "模型服务"
    var settingsData = "数据源"
    var languageLabel = "语言 / Language"
    var modelSectionHeader = "模型"
    var modelFooter = "AI 对话经由官方后端转发,客户端不保存模型 API Key。"
    var dataKeyHeader = "同花顺金融数据 API Key(fuyao.aicubes.cn)"
    var dataKeyPlaceholder = "sk-fuyao-…"
    var dataKeyUsingBuiltIn = "当前使用内置 Key;填写后以你自己的 Key 为准,存系统钥匙串"
    var dataKeyUsingCustom = "当前使用自定义 Key(系统钥匙串)"
    var dataKeyReset = "恢复内置 Key"
    var dataKeyTest = "测试连接"
    var dataKeyTestOKFormat = "连接正常:交易日历 %d 天"
    var dataKeyFooter = "所有盘面数据(涨停、龙虎榜、热榜、指数、K 线)来自同花顺金融数据 API;本地缓存只存行情,不存密钥。"
    var researchCacheFormat = "本地研究缓存 %@"
    var clearCache = "清空缓存"

    // 账户
    var signInTitle = "登录后使用 AI 对话"
    var signInSubtitle = "用 GitHub 或 Apple 一键登录;也可以用邮箱注册。盘面模块无需登录。"
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
    var signInRequired = "请先登录(设置 › 账户)后再使用 AI 对话"
    var signInBanner = "登录后使用 AI 对话;盘面模块无需登录"
    var openAccountSettings = "去登录"
    var passwordTooShort = "密码至少 8 位"
    var passwordMismatch = "两次输入的密码不一致"
    var refresh = "刷新"

    // 模块通用
    var modulesSubtitle = "数据来自同花顺金融数据 API,分析在本地完成;结果可一键交给 AI 解读 · 仅供研究参考,不构成投资建议"
    var backToModules = "返回模块列表"
    var loading = "正在拉取数据…"
    var analyzeWithAI = "让 AI 解读"
    var disclaimer = "仅供研究参考,不构成投资建议"
    var previousDay = "前一交易日"
    var nextDay = "后一交易日"
    var today = "今天"
    var noData = "暂无数据"
    var updatedAtFormat = "更新于 %@"
    var stock = "股票"
    var name = "名称"
    var price = "现价"
    var change = "涨跌幅"
    var reason = "原因"
    var concepts = "概念"
    var netBuy = "净买入"
    var buy = "买入"
    var sell = "卖出"
    var count = "家数"
    var rank = "排名"
    var heat = "热度"
    var showMore = "展开全部"
    var showLess = "收起"

    // 模块 1:涨停情绪市场脉冲
    var limitUpPulseName = "涨停情绪市场脉冲"
    var limitUpPulseSubtitle = "涨停 / 跌停 / 炸板池与连板天梯 → 情绪分、封板率、题材聚类、时间分布"
    var sentimentScore = "情绪分"
    var limitUpCount = "涨停"
    var limitDownCount = "跌停"
    var breakCount = "炸板"
    var sealRate = "封板率"
    var firstBoard = "首板"
    var consecutive = "连板"
    var highestBoard = "最高板"
    var earlySeal = "10 点前封板"
    var sealStrength = "封单强度"
    var totalSeal = "总封单"
    var boardDistribution = "板位分布"
    var timeDistribution = "涨停时间分布"
    var themeClusters = "题材聚类"
    var leaders = "高度龙头"
    var topSeals = "封单最强"
    var ladderTrend = "连板天梯 · 近 30 日"
    var ladderHeight = "高度"
    var ladderCount = "连板家数"
    var promotionRate = "晋级率"
    var limitUpTime = "涨停时间"
    var sealMoney = "封单"
    var openTimes = "开板次数"
    var boardsFormat = "%d板"
    var limitUpPool = "涨停池"
    var limitBreakPool = "炸板池"
    var limitDownPool = "跌停池"

    // 模块 2:龙虎榜资金流拓扑图
    var dragonTigerTopologyName = "龙虎榜资金流拓扑图"
    var dragonTigerTopologySubtitle = "游资 / 机构席位 → 股票 → 概念 三层资金流向,线宽即金额,红买绿卖"
    var topologyPlayers = "席位(游资 / 机构)"
    var topologyStocks = "上榜股票"
    var topologyConcepts = "概念聚合"
    var topologyHint = "点击节点高亮关联资金流;再次点击取消"
    var topologyNetIn = "净流入"
    var topologyNetOut = "净流出"
    var topologyNodeCountFormat = "%d 个席位 · %d 只股票 · %d 个概念"
    var topologyEdges = "最大资金边"

    // 模块 3:市场热度与飙升雷达
    var heatRadarName = "市场热度与飙升雷达"
    var heatRadarSubtitle = "热股榜 × 飙升榜 × 个股异动原因交叉:共振股、飙升股、异动关键词热度"
    var periodDay = "日榜"
    var periodHour = "小时榜"
    var hotList = "热股榜"
    var surgeList = "飙升榜"
    var resonance = "热度共振"
    var resonanceHint = "同时出现在热股榜与飙升榜"
    var climbers = "排名飙升"
    var anomalyTags = "异动标签"
    var anomalyKeywords = "异动关键词热度"
    var anomalyReasons = "个股异动原因"
    var rankTrend = "近 30 日热榜排名走势"
    var radarHint = "雷达:沿螺旋按热榜排名由内向外展开,点越大热度越高;红点上升,绿点下降;圈点 = 共振;点击看排名走势"
    var rankChange = "排名变化"

    // 模块 4:本地全市场趋势研究
    var marketTrendName = "本地全市场趋势研究"
    var marketTrendSubtitle = "全市场 5000+ 只快照 + 300+ 板块指数日 K 落本地增量缓存,宽度、轮动、趋势分全本地计算"
    var refreshIncremental = "增量刷新"
    var rebuildAll = "全量重建"
    var sectorIndustry = "行业"
    var sectorConcept = "概念"
    var marketRegime = "大盘状态"
    var indicesHeader = "主要指数"
    var breadthHeader = "市场宽度"
    var breadthUp = "上涨"
    var breadthDown = "下跌"
    var breadthFlat = "平盘"
    var breadthMedian = "中位涨跌"
    var breadthTurnover = "总成交额"
    var breadthConcentration = "前 100 只成交占比"
    var breadthDistribution = "涨跌分布"
    var breadthHistory = "上涨占比历史"
    var boardsHeader = "各板块"
    var strongestSectors = "最强板块"
    var weakestSectors = "最弱板块"
    var rotationHeatmap = "板块轮动热力图 · 近 10 日"
    var trendScore = "趋势分"
    var ret20 = "20 日"
    var ret60 = "60 日"
    var maAlignment = "均线结构"
    var bullishAlignment = "多头排列"
    var bearishAlignment = "空头排列"
    var mixedAlignment = "均线交织"
    var stockResearch = "个股趋势研究"
    var stockResearchHint = "输入代码,拉一年前复权日 K,本地跑趋势 / 风控 / 回测 / GBDT / 因子"
    var research = "研究"
    var dumpHeader = "全市场 Parquet 数据包"
    var dumpHint = "直接下载同花顺整库导出,用 Python / DuckDB 做离线回测"
    var dump10y = "10 年日 K"
    var dump10d = "近 10 日日 K"
    var dumpFactors = "复权因子"
    var cacheEmptyHint = "还没有本地数据。点「增量刷新」拉取全市场快照与板块日 K(首次约 1–2 分钟)。"
    var topGainers = "涨幅前列"
    var topLosers = "跌幅前列"
    var topTurnover = "成交额前列"

    // 模块 5:龙虎榜机构与游资观察
    var dragonTigerWatchName = "龙虎榜机构与游资观察"
    var dragonTigerWatchSubtitle = "多日龙虎榜聚合:机构净买卖、游资活跃度与偏好、反复上榜的股票"
    var watchWindow = "回看"
    var watchDaysFormat = "%d 个交易日"
    var orgNetTotal = "机构合计净买入"
    var hotMoneyNetTotal = "游资合计净买入"
    var orgBuys = "机构净买入"
    var orgSells = "机构净卖出"
    var activePlayers = "活跃游资"
    var repeatedStocks = "反复上榜"
    var appearancesFormat = "上榜 %d 次"
    var orgCountFormat = "%d 买 / %d 卖"
    var playerPreference = "偏好概念"
    var playerStocks = "操作股票"
    var dailyRows = "逐日明细"
    var date = "日期"
    var player = "游资"

    // 量化工具
    var quantToolsHeader = "量化工具"
    var sourcePicker = "数据源"
    var historyPicker = "历史"
    var daysFormat = "%d 天"
    var fastMAFormat = "快线 MA%d"
    var slowMAFormat = "慢线 MA%d"
    var treesFormat = "树数 %d"
    var depthFormat = "深度 %d"
    var run = "运行"
    var running = "拉取数据并计算中…"
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
    var gbdtName = "梯度提升树模型"
    var riskName = "风控模型"
    var factorToolName = "因子挖掘"
    var backtestName = "历史回测"
    var gbdtSubtitle = "原生 GBDT 预测次日涨跌,给出验证集命中率与特征重要性"
    var riskSubtitle = "历史 VaR、最大回撤、年化波动率、夏普比率"
    var factorSubtitle = "9 个价格类因子的 IC 检验与多空分层,按预测力排序"
    var backtestSubtitle = "双均线交叉策略 vs 买入持有,净值曲线与胜率"

    // 会话与提示语(进入消息内容,按发送时语言生成)
    var freshConversationTitle = "新对话"
    var marketFallbackTitle = "行情分析"
    var analyzePromptPrefix = "请解读以下盘面数据,指出关键结论、资金与情绪线索,以及需要跟踪的风险:"

    // 错误描述
    var chatInvalidURL = "后端地址无效,请更新客户端"
    var chatHTTPFormat = "服务返回 HTTP %d:%@"
    var chatStreamFormat = "生成中断:%@"
    var chatEmptyBody = "无响应内容"
    var marketInvalidSymbolFormat = "找不到代码 %@,请输入 6 位 A 股代码"
    var fuyaoMissingKey = "缺少同花顺数据 API Key,请在 设置 › 数据源 填写"
    var fuyaoAPIFormat = "数据接口错误 %d:%@"
    var fuyaoHTTPFormat = "数据服务返回 HTTP %d"
    var fuyaoDecodingFormat = "数据解析失败:%@"
    var fuyaoNetworkFormat = "网络请求失败:%@"
    var fuyaoUnauthorized = "同花顺数据 API Key 无效或已过期(2001),请在 设置 › 数据源 更新"
    var fuyaoForbidden = "当前 API Key 无权访问该数据(2003),请联系 fuyao 管理员开通"
    var fuyaoRateLimited = "数据接口频率超限(4001),稍后再试"
    var fuyaoNotReady = "该日期数据暂未就绪(3002),换个交易日试试"
    var quantTooShortFormat = "历史数据太短,至少需要 %d 根日线"
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
        s.appName = "A-Share Agent"
        s.appTagline = "Limit-up sentiment · Dragon-tiger flows · Heat radar · Market trend"
        s.search = "Search"
        s.newChat = "New conversation"
        s.newChatHelp = "New chat ⌘N"
        s.conversationsHeader = "Conversations"
        s.workspaceChat = "Chat"
        s.workspaceModules = "Market"
        s.modulesHeader = "Market modules"
        s.notSignedIn = "Not signed in"
        s.renameAlertTitle = "Rename Conversation"
        s.renameFieldPlaceholder = "Name"
        s.rename = "Rename"
        s.delete = "Delete"
        s.cancel = "Cancel"
        s.save = "Save"
        s.settingsHelp = "Settings ⌘,"
        s.helloTitle = "Hi, I'm A-Share Agent"
        s.helloSubtitle = "Ask about limit-up sentiment, dragon-tiger flows, sector trends, or just give me a ticker"
        s.suggestionLimitUp = "How is limit-up sentiment today?"
        s.suggestionDragonTiger = "Which hot-money seats were buying on yesterday's dragon-tiger list?"
        s.suggestionHeat = "Which stocks are hottest right now?"
        s.suggestionStock = "Analyze 600519"
        s.generating = "Generating"
        s.codeBlockFallback = "code"
        s.copy = "Copy"
        s.copied = "Copied"
        s.newChatMenu = "New Chat"
        s.contextAttachedFormat = "Live data attached: %@"
        s.askPlaceholder = "Ask A-Share Agent, or type a ticker…"
        s.attachHelp = "Attach an A-share quote"
        s.attachQuote = "Attach stock quote"
        s.attachModuleReport = "Attach module report"
        s.stopHelp = "Stop generating"
        s.sendHelp = "Send (Enter)"
        s.agentAutoContextLabel = "Agent auto-attaches live data"
        s.agentAutoContextHint = "Pulls limit-up / dragon-tiger / hot list / index and stock snapshots by intent and adds them to the message"
        s.attachSheetTitle = "Attach A-share quote"
        s.query = "Fetch"
        s.fetchingQuote = "Fetching quote…"
        s.attach = "Attach"
        s.highLowFormat = "High %@ / Low %@"
        s.aShareSymbolHint = "e.g. 600519, 000001, 300750"
        s.settingsGeneral = "General"
        s.settingsAccount = "Account"
        s.settingsModels = "Models"
        s.settingsData = "Data Source"
        s.languageLabel = "Language / 语言"
        s.modelSectionHeader = "Model"
        s.modelFooter = "AI chat is relayed through the official backend; the client stores no model API key."
        s.dataKeyHeader = "Tonghuashun financial data API key (fuyao.aicubes.cn)"
        s.dataKeyPlaceholder = "sk-fuyao-… (paste your key)"
        s.dataKeyUsingBuiltIn = "Using the built-in key; enter your own to override (stored in the Keychain)"
        s.dataKeyUsingCustom = "Using your custom key (Keychain)"
        s.dataKeyReset = "Restore built-in key"
        s.dataKeyTest = "Test connection"
        s.dataKeyTestOKFormat = "Connected: %d trading days in calendar"
        s.dataKeyFooter = "All market data (limit-up, dragon-tiger, hot lists, indices, K-lines) comes from the Tonghuashun data API; the local cache holds prices only, never keys."
        s.researchCacheFormat = "Local research cache %@"
        s.clearCache = "Clear cache"
        s.signInTitle = "Sign in to use AI chat"
        s.signInSubtitle = "One click with GitHub or Apple, or use an email account. Market modules work without signing in."
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
        s.signInRequired = "Sign in first (Settings › Account) to use AI chat"
        s.signInBanner = "Sign in to use AI chat; market modules need no account"
        s.openAccountSettings = "Sign in"
        s.passwordTooShort = "Password must be at least 8 characters"
        s.passwordMismatch = "The two passwords do not match"
        s.refresh = "Reload"
        s.modulesSubtitle = "Data from the Tonghuashun financial data API, analyzed locally; hand any result to AI in one click · Research only, not investment advice"
        s.backToModules = "Back to modules"
        s.loading = "Fetching data…"
        s.analyzeWithAI = "Ask AI to interpret"
        s.disclaimer = "For research only, not investment advice"
        s.previousDay = "Previous trading day"
        s.nextDay = "Next trading day"
        s.today = "Today"
        s.noData = "No data"
        s.updatedAtFormat = "Updated %@"
        s.stock = "Stock"
        s.name = "Name"
        s.price = "Price"
        s.change = "Change"
        s.reason = "Reason"
        s.concepts = "Concepts"
        s.netBuy = "Net buy"
        s.buy = "Buy"
        s.sell = "Sell"
        s.count = "Count"
        s.rank = "Rank"
        s.heat = "Heat"
        s.showMore = "Show all"
        s.showLess = "Show less"
        s.limitUpPulseName = "Limit-Up Sentiment Pulse"
        s.limitUpPulseSubtitle = "Limit-up / limit-down / broken pools and the streak ladder → sentiment score, seal rate, theme clusters, timing"
        s.sentimentScore = "Sentiment"
        s.limitUpCount = "Limit-up"
        s.limitDownCount = "Limit-down"
        s.breakCount = "Broken"
        s.sealRate = "Seal rate"
        s.firstBoard = "First board"
        s.consecutive = "Streaks"
        s.highestBoard = "Highest"
        s.earlySeal = "Sealed before 10:00"
        s.sealStrength = "Seal strength"
        s.totalSeal = "Total seal orders"
        s.boardDistribution = "Board distribution"
        s.timeDistribution = "Limit-up timing"
        s.themeClusters = "Theme clusters"
        s.leaders = "Streak leaders"
        s.topSeals = "Strongest seals"
        s.ladderTrend = "Streak ladder · last 30 days"
        s.ladderHeight = "Height"
        s.ladderCount = "Streak count"
        s.promotionRate = "Promotion rate"
        s.limitUpTime = "Sealed at"
        s.sealMoney = "Seal"
        s.openTimes = "Opens"
        s.boardsFormat = "%dB"
        s.limitUpPool = "Limit-up pool"
        s.limitBreakPool = "Broken pool"
        s.limitDownPool = "Limit-down pool"
        s.dragonTigerTopologyName = "Dragon-Tiger Flow Topology"
        s.dragonTigerTopologySubtitle = "Hot-money / institution seats → stocks → concepts; edge width = amount, red buy, green sell"
        s.topologyPlayers = "Seats (hot money / institutions)"
        s.topologyStocks = "Listed stocks"
        s.topologyConcepts = "Concept aggregation"
        s.topologyHint = "Click a node to highlight its flows; click again to clear"
        s.topologyNetIn = "Net inflow"
        s.topologyNetOut = "Net outflow"
        s.topologyNodeCountFormat = "%d seats · %d stocks · %d concepts"
        s.topologyEdges = "Largest flows"
        s.heatRadarName = "Heat & Surge Radar"
        s.heatRadarSubtitle = "Hot list × surge list × anomaly reasons: resonance stocks, climbers, keyword heat"
        s.periodDay = "Daily"
        s.periodHour = "Hourly"
        s.hotList = "Hot list"
        s.surgeList = "Surge list"
        s.resonance = "Resonance"
        s.resonanceHint = "On both the hot list and the surge list"
        s.climbers = "Rank climbers"
        s.anomalyTags = "Anomaly tags"
        s.anomalyKeywords = "Anomaly keyword heat"
        s.anomalyReasons = "Anomaly reasons"
        s.rankTrend = "Hot-list rank, last 30 days"
        s.radarHint = "Radar: hot-list rank spirals outward from #1; bigger dot = more heat; red rising, green falling; ringed = resonance; click for rank history"
        s.rankChange = "Rank change"
        s.marketTrendName = "Local Market Trend Research"
        s.marketTrendSubtitle = "5000+ stock snapshot and 300+ sector index K-lines cached locally; breadth, rotation and trend scores computed on-device"
        s.refreshIncremental = "Incremental refresh"
        s.rebuildAll = "Full rebuild"
        s.sectorIndustry = "Industries"
        s.sectorConcept = "Concepts"
        s.marketRegime = "Market regime"
        s.indicesHeader = "Major indices"
        s.breadthHeader = "Market breadth"
        s.breadthUp = "Advancing"
        s.breadthDown = "Declining"
        s.breadthFlat = "Unchanged"
        s.breadthMedian = "Median change"
        s.breadthTurnover = "Total turnover"
        s.breadthConcentration = "Top-100 turnover share"
        s.breadthDistribution = "Return distribution"
        s.breadthHistory = "Advancing share history"
        s.boardsHeader = "By board"
        s.strongestSectors = "Strongest sectors"
        s.weakestSectors = "Weakest sectors"
        s.rotationHeatmap = "Sector rotation heatmap · last 10 days"
        s.trendScore = "Trend score"
        s.ret20 = "20d"
        s.ret60 = "60d"
        s.maAlignment = "MA structure"
        s.bullishAlignment = "Bullish alignment"
        s.bearishAlignment = "Bearish alignment"
        s.mixedAlignment = "Mixed"
        s.stockResearch = "Single-stock trend research"
        s.stockResearchHint = "Enter a ticker to pull one year of forward-adjusted daily bars and run trend / risk / backtest / GBDT / factor analysis locally"
        s.research = "Research"
        s.dumpHeader = "Full-market Parquet dumps"
        s.dumpHint = "Download the whole-market export for offline backtests in Python / DuckDB"
        s.dump10y = "10-year daily K"
        s.dump10d = "Last 10 days daily K"
        s.dumpFactors = "Adjustment factors"
        s.cacheEmptyHint = "No local data yet. Click \"Incremental refresh\" to pull the market snapshot and sector K-lines (about 1–2 minutes the first time)."
        s.topGainers = "Top gainers"
        s.topLosers = "Top losers"
        s.topTurnover = "Top turnover"
        s.dragonTigerWatchName = "Institution & Hot-Money Watch"
        s.dragonTigerWatchSubtitle = "Multi-day dragon-tiger aggregation: institutional net flows, hot-money activity and preferences, repeat listings"
        s.watchWindow = "Window"
        s.watchDaysFormat = "%d trading days"
        s.orgNetTotal = "Institutional net buy"
        s.hotMoneyNetTotal = "Hot-money net buy"
        s.orgBuys = "Institutional buying"
        s.orgSells = "Institutional selling"
        s.activePlayers = "Active hot money"
        s.repeatedStocks = "Repeat listings"
        s.appearancesFormat = "%d listings"
        s.orgCountFormat = "%d buy / %d sell"
        s.playerPreference = "Preferred concepts"
        s.playerStocks = "Stocks traded"
        s.dailyRows = "Daily detail"
        s.date = "Date"
        s.player = "Seat"
        s.quantToolsHeader = "Quant Tools"
        s.sourcePicker = "Source"
        s.historyPicker = "History"
        s.daysFormat = "%d days"
        s.fastMAFormat = "Fast MA%d"
        s.slowMAFormat = "Slow MA%d"
        s.treesFormat = "Trees %d"
        s.depthFormat = "Depth %d"
        s.run = "Run"
        s.running = "Fetching data and computing…"
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
        s.gbdtName = "Gradient Boosted Trees"
        s.riskName = "Risk Model"
        s.factorToolName = "Factor Mining"
        s.backtestName = "Backtest"
        s.gbdtSubtitle = "Native GBDT predicts next-day direction with validation hit rate and feature importance"
        s.riskSubtitle = "Historical VaR, max drawdown, annualized volatility, Sharpe ratio"
        s.factorSubtitle = "IC test and long-short layering of 9 price factors, ranked by predictive power"
        s.backtestSubtitle = "Dual moving-average crossover vs buy & hold, with equity curves and win rate"
        s.freshConversationTitle = "New conversation"
        s.marketFallbackTitle = "Market analysis"
        s.analyzePromptPrefix = "Please interpret the following market data: key conclusions, money-flow and sentiment clues, and risks to track:"
        s.chatInvalidURL = "Invalid backend address — please update the app"
        s.chatHTTPFormat = "Server returned HTTP %d: %@"
        s.chatStreamFormat = "Generation interrupted: %@"
        s.chatEmptyBody = "empty response body"
        s.marketInvalidSymbolFormat = "Symbol %@ not found — enter a 6-digit A-share ticker"
        s.fuyaoMissingKey = "Missing Tonghuashun data API key — add one under Settings › Data Source"
        s.fuyaoAPIFormat = "Data API error %d: %@"
        s.fuyaoHTTPFormat = "Data service returned HTTP %d"
        s.fuyaoDecodingFormat = "Failed to parse data: %@"
        s.fuyaoNetworkFormat = "Network request failed: %@"
        s.fuyaoUnauthorized = "The Tonghuashun data API key is invalid or expired (2001) — update it under Settings › Data Source"
        s.fuyaoForbidden = "This API key has no access to that dataset (2003) — ask the fuyao admin to enable it"
        s.fuyaoRateLimited = "Data API rate limit hit (4001) — try again shortly"
        s.fuyaoNotReady = "Data for that date is not ready yet (3002) — try another trading day"
        s.quantTooShortFormat = "Not enough history — at least %d daily bars needed"
        s.quantInvalidParameter = "Fast MA period must be shorter than the slow one"
        s.accountNotSignedIn = "Not signed in yet — sign in under Settings › Account first"
        s.accountDecoding = "Could not parse the account response — please update the app"
        s.appleNeedsSignedBuild = "Sign in with Apple needs a properly signed build (unavailable in Debug builds) — use GitHub or email instead"
        s.appleSignInCanceled = "Apple sign-in canceled"
        s.appleMissingIdentityToken = "Apple returned no identity token — try again or sign in with GitHub"
        return s
    }()

    // MARK: - 派生文案

    func moduleName(_ module: AgentModule) -> String {
        switch module {
        case .limitUpPulse: limitUpPulseName
        case .dragonTigerTopology: dragonTigerTopologyName
        case .heatRadar: heatRadarName
        case .marketTrend: marketTrendName
        case .dragonTigerWatch: dragonTigerWatchName
        }
    }

    func moduleSubtitle(_ module: AgentModule) -> String {
        switch module {
        case .limitUpPulse: limitUpPulseSubtitle
        case .dragonTigerTopology: dragonTigerTopologySubtitle
        case .heatRadar: heatRadarSubtitle
        case .marketTrend: marketTrendSubtitle
        case .dragonTigerWatch: dragonTigerWatchSubtitle
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

    func alignment(_ metrics: TrendMetrics) -> String {
        metrics.bullishAlignment ? bullishAlignment : (metrics.bearishAlignment ? bearishAlignment : mixedAlignment)
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
        case let error as FuyaoError: describeFuyao(error)
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

    private func describeFuyao(_ error: FuyaoError) -> String {
        switch error {
        case .missingKey: fuyaoMissingKey
        case .api(2001, _): fuyaoUnauthorized
        case .api(2003, _): fuyaoForbidden
        case .api(4001, _): fuyaoRateLimited
        case .api(3002, _): fuyaoNotReady
        case .api(let code, let message): String(format: fuyaoAPIFormat, code, message)
        case .http(let status): String(format: fuyaoHTTPFormat, status)
        case .decoding(let detail): String(format: fuyaoDecodingFormat, detail)
        case .network(let message): String(format: fuyaoNetworkFormat, message)
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
