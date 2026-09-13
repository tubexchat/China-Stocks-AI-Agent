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
    var appTagline = "涨停情绪 · 龙虎榜资金 · 热度雷达 · 行业强度 · 财务体检"
    var dataSourceBadge = "数据:同花顺金融数据 API"
    var copyReport = "复制报告"
    var moduleDefaultsHeader = "模块默认参数"
    var sectorScopeLabel = "板块口径"

    // 侧栏
    var modulesHeader = "盘面模块"
    var cancel = "取消"
    var save = "保存"
    var settingsHelp = "设置 ⌘,"

    var copied = "已复制"
    var aShareSymbolHint = "如 600519、000001、300750"

    // 设置
    var settingsGeneral = "通用"
    var settingsData = "数据源"
    var languageLabel = "语言 / Language"
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

    var refresh = "刷新"

    // 模块通用
    var modulesSubtitle = "数据来自同花顺金融数据 API,分析在本地完成;每个模块的报告可一键复制 · 仅供研究参考,不构成投资建议"
    var backToModules = "返回模块列表"
    var loading = "正在拉取数据…"
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
    var rankTrend = "热榜排名走势"
    var radarHint = "雷达:沿螺旋按热榜排名由内向外展开,点越大热度越高;红点上升,绿点下降;圈点 = 共振;点击看排名走势"
    var rankChange = "排名变化"
    var rankRange = "区间"
    var rankRangeDaysFormat = "近 %d 日"
    var heatRadarMethod = "热股榜与飙升榜含义不同,分别展示、不合成单一评分;日榜按自然日、小时榜按最近 1 小时统计;排名变化只是榜单位次差,不构成买卖信号;数据为上游最近一次榜单快照,页面不做实时推送,延迟以上游统计时刻为准"

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

    // 量化工具(个股研究)
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

    // 错误描述
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

    // 数据说明(新三个模块共用)
    var dataProvenance = "数据说明"
    var dataTime = "数据时间"
    var dataMode = "模式"
    var dataModeReal = "真实数据 · 同花顺金融数据 API(fuyao.aicubes.cn),全部计算在本地完成;API Key 只在本机请求头里,不进页面"
    var sourceEndpoints = "来源端点"
    var methodology = "计算口径"
    var notAdvice = "非投资建议:本页只做数据观察与视觉穿透,不含组合评价或交易执行"
    var generatedAtFormat = "生成于 %@"
    var fetchFailed = "取数失败"
    var noValue = "—"

    // 模块 6:行业强度作战矩阵
    var industryMatrixName = "行业强度作战矩阵"
    var industryMatrixSubtitle = "同花顺行业指数日 K → 5/20/60 日相对强度、成交额脉冲、排名变化与宽度;选中行业看成分股联动证据"
    var matrixHint = "气泡:横轴 20 日相对强度,纵轴 60 日相对强度,大小 = 成交额脉冲;红 = 5 日跑赢基准,绿 = 跑输;悬停看数值,点击看成分"
    var benchmarkLabel = "基准"
    var rs5 = "5 日相对强度"
    var rs20 = "20 日相对强度"
    var rs60 = "60 日相对强度"
    var turnoverPulse = "成交额脉冲"
    var turnoverPulseHint = "5 日均额 / 20 日均额"
    var strengthScore = "强度分"
    var rankNow = "名次"
    var rankShift = "名次变化(5 日)"
    var industryBreadth = "行业宽度"
    var breadthPositive20 = "20 日上涨"
    var breadthOutperform = "跑赢基准"
    var breadthAboveMA20 = "站上 MA20"
    var breadthPulse = "脉冲 > 1"
    var heatBand = "近 20 日热力带"
    var heatBandHint = "最强 12 + 最弱 8 个行业的逐日涨跌"
    var strongestIndustries = "最强行业"
    var weakestIndustries = "最弱行业"
    var rankClimbers = "名次上升"
    var rankFallers = "名次下降"
    var constituentEvidence = "行业—个股联动证据"
    var constituentHint = "点击气泡或行业行,拉取当前成分与实时快照"
    var constituentCount = "当前成分"
    var equalWeightProxy = "等权涨跌代理"
    var equalWeightCaveat = "基于当前成分清单与等权口径,不是指数贡献拆解"
    var indexChange = "指数涨跌"
    var weightGap = "指数 − 等权(百分点)"
    var dispersion = "离散度"
    var turnoverActivity = "成交额合计"
    var top5Share = "前 5 只成交占比"
    var industryMatrixMethod = "相对强度 = (1+行业区间涨跌)/(1+基准区间涨跌)−1;成交额脉冲 = 5 日均额/20 日均额;强度分 = RS5/RS20/RS60 百分位 ×0.2/0.5/0.3;名次按 RS20,5 个交易日前同口径重算;宽度按行业个数计"
    var industryCacheEmptyHint = "还没有行业指数缓存。点「增量刷新」拉取 300+ 个同花顺行业指数日 K(首次约 1 分钟);与「本地全市场趋势研究」共用缓存。"

    // 模块 7:现金流质量稽核台
    var cashFlowAuditName = "现金流质量稽核台"
    var cashFlowAuditSubtitle = "≤20 只观察池 × 5 年年报三表:现金转化率、自由现金流率、应计利润率、应收压力、净现金比例与字段完整度审计"
    var watchPool = "观察池"
    var watchPoolHint = "最多 20 只,逗号 / 空格分隔;每只单独请求三张年报(period=annual&limit=5),代码表只用来限定范围"
    var applyPool = "应用"
    var asOfLabel = "披露截止"
    var asOfHint = "只保留 report_date_ms 不晚于该日的报告期"
    var screeningTable = "公司筛查表"
    var sortBy = "排序"
    var cashConversion = "现金转化率"
    var fcfMargin = "自由现金流率"
    var accrualRatio = "应计利润率"
    var receivablePressure = "应收压力"
    var netCashRatio = "净现金比例"
    var fiveYearAverage = "5 年均值"
    var cashCoveredYears = "现金覆盖利润年数"
    var profitCashBridge = "利润—经营现金流桥"
    var bridgeNetProfit = "净利润"
    var bridgeAccruals = "应计项(利润 − 经营现金流)"
    var bridgeOCF = "经营现金流净额"
    var bridgeCapex = "购建固定资产等支付"
    var bridgeAccrualsShort = "应计项"
    var bridgeCapexShort = "购建支出"
    var bridgeFCF = "自由现金流"
    var cashEvidence = "5 年现金证据"
    var cashEvidenceHint = "净利润 vs 经营现金流 vs 自由现金流(年报)"
    var fieldAudit = "字段完整度审计"
    var fieldAuditHint = "8 个计算字段在全部公司 × 报告期里的非空次数"
    var periodsLoaded = "报告期"
    var reportDate = "披露日"
    var completeness = "完整度"
    var cashFlowMethod = "现金转化率=经营现金流净额/净利润;自由现金流率=(经营现金流净额−购建固定资产等支付现金)/营业收入;应计利润率=(净利润−经营现金流净额)/资产总计;应收压力=应收账款/营业收入;净现金比例=(货币资金−负债合计)/资产总计;分母为 0 或缺失时留空;三表按 period_end_ms 对齐,披露时点按 report_date_ms"
    var loadPool = "拉取观察池"
    var missingFieldsFormat = "缺失 %d/%d 字段"

    // 模块 8:单股财务体检
    var financialHealthName = "单股财务体检"
    var financialHealthSubtitle = "搜索消歧 → 最近 8 期季度三表按报告期对齐 + 最新期财务指标:增长、盈利、现金流、杠杆的事实性归纳"
    var searchPlaceholder = "股票名称或代码,如 同花顺 / 300033"
    var searchAction = "体检"
    var disambiguate = "多只匹配,请选择"
    var latestPeriod = "最新报告期"
    var cumulativeNote = "累计"
    var singleQuarterNote = "单季推算"
    var growthSection = "增长"
    var profitabilitySection = "盈利"
    var cashFlowSection = "现金流"
    var leverageSection = "杠杆"
    var revenue = "营业收入"
    var netProfit = "净利润"
    var parentNetProfit = "归母净利润"
    var operatingProfit = "营业利润"
    var grossMargin = "毛利率"
    var netMargin = "净利率"
    var eps = "基本每股收益"
    var rdExpenses = "研发费用"
    var ocf = "经营现金流净额"
    var capex = "购建固定资产等支付现金"
    var fcf = "自由现金流"
    var ocfToProfit = "经营现金流 / 净利润"
    var totalAssets = "资产总计"
    var totalDebt = "负债合计"
    var cashHoldings = "货币资金"
    var equity = "股东权益"
    var debtRatio = "资产负债率"
    var cashToDebt = "货币资金 / 负债合计"
    var receivables = "应收账款"
    var yoy = "同比"
    var vsPrevious = "环比上期"
    var yearAgoSame = "上年同期"
    var seriesRevenue = "收入"
    var seriesProfit = "利润"
    var seriesCashFlow = "现金流"
    var seriesToggleHint = "累计 / 单季切换;悬停或用 ← → 查看各报告期"
    var periodsTable = "8 期明细"
    var indicatorsHeader = "财务指标(同花顺口径)"
    var financialHealthMethod = "季度利润表 / 现金流量表为年初至今累计值,资产负债表为期末时点值;单季值 = 本期累计 − 同财年上期累计(上期缺失则留空);同比 = 与上一财年同一报告期比;null 保持缺失不补零;不计算估值、行业均值与评分"
    var currencyLabel = "币种"
    var statementsComplete = "三表齐全期数"

    // MARK: - 两张表

    static let zh = L10nStrings()

    static let en: L10nStrings = {
        var s = L10nStrings()
        s.appName = "A-Share Agent"
        s.appTagline = "Limit-up sentiment · Dragon-tiger flows · Heat radar · Industry strength · Financial check-up"
        s.dataSourceBadge = "Data: Tonghuashun financial data API"
        s.copyReport = "Copy report"
        s.moduleDefaultsHeader = "Module defaults"
        s.sectorScopeLabel = "Sector scope"
        s.modulesHeader = "Market modules"
        s.cancel = "Cancel"
        s.save = "Save"
        s.settingsHelp = "Settings ⌘,"
        s.copied = "Copied"
        s.aShareSymbolHint = "e.g. 600519, 000001, 300750"
        s.settingsGeneral = "General"
        s.settingsData = "Data Source"
        s.languageLabel = "Language / 语言"
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
        s.refresh = "Reload"
        s.modulesSubtitle = "Data from the Tonghuashun financial data API, analyzed locally; every module report can be copied in one click · Research only, not investment advice"
        s.backToModules = "Back to modules"
        s.loading = "Fetching data…"
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
        s.rankTrend = "Hot-list rank history"
        s.radarHint = "Radar: hot-list rank spirals outward from #1; bigger dot = more heat; red rising, green falling; ringed = resonance; click for rank history"
        s.rankChange = "Rank change"
        s.rankRange = "Range"
        s.rankRangeDaysFormat = "Last %d days"
        s.heatRadarMethod = "The hot list and the surge list measure different things and are shown separately, never merged into one score; the daily list is per calendar day, the hourly list covers the last hour; rank change is only a positional difference, not a trading signal; data is the upstream's latest list snapshot with no live push, so latency follows the upstream's statistics time"
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
        s.dataProvenance = "Data provenance"
        s.dataTime = "Data as of"
        s.dataMode = "Mode"
        s.dataModeReal = "Live data · Tonghuashun financial data API (fuyao.aicubes.cn), all computation on-device; the API key stays in this machine's request header and never enters the page"
        s.sourceEndpoints = "Source endpoints"
        s.methodology = "Methodology"
        s.notAdvice = "Not investment advice: this page is observation and visual drill-down only, with no portfolio scoring or trade execution"
        s.generatedAtFormat = "Generated %@"
        s.fetchFailed = "Fetch failed"
        s.noValue = "n/a"
        s.industryMatrixName = "Industry Strength Matrix"
        s.industryMatrixSubtitle = "Tonghuashun industry index K-lines → 5/20/60-day relative strength, turnover pulse, rank shifts and breadth; select an industry for constituent evidence"
        s.matrixHint = "Bubbles: x = 20d relative strength, y = 60d relative strength, size = turnover pulse; red = beating the benchmark over 5d, green = lagging; hover for values, click for constituents"
        s.benchmarkLabel = "Benchmark"
        s.rs5 = "RS 5d"
        s.rs20 = "RS 20d"
        s.rs60 = "RS 60d"
        s.turnoverPulse = "Turnover pulse"
        s.turnoverPulseHint = "5d avg / 20d avg turnover"
        s.strengthScore = "Strength"
        s.rankNow = "Rank"
        s.rankShift = "Rank shift (5d)"
        s.industryBreadth = "Industry breadth"
        s.breadthPositive20 = "Up over 20d"
        s.breadthOutperform = "Beating benchmark"
        s.breadthAboveMA20 = "Above MA20"
        s.breadthPulse = "Pulse > 1"
        s.heatBand = "20-day heat band"
        s.heatBandHint = "Daily returns of the 12 strongest and 8 weakest industries"
        s.strongestIndustries = "Strongest industries"
        s.weakestIndustries = "Weakest industries"
        s.rankClimbers = "Rank climbers"
        s.rankFallers = "Rank fallers"
        s.constituentEvidence = "Industry–stock linkage evidence"
        s.constituentHint = "Click a bubble or a row to pull current constituents and live quotes"
        s.constituentCount = "Constituents"
        s.equalWeightProxy = "Equal-weight change proxy"
        s.equalWeightCaveat = "Based on the current constituent list, equal-weighted; not an index contribution breakdown"
        s.indexChange = "Index change"
        s.weightGap = "Index − equal-weight (pp)"
        s.dispersion = "Dispersion"
        s.turnoverActivity = "Total turnover"
        s.top5Share = "Top-5 turnover share"
        s.industryMatrixMethod = "Relative strength = (1+industry return)/(1+benchmark return)−1; turnover pulse = 5d avg / 20d avg; score = percentile of RS5/RS20/RS60 weighted 0.2/0.5/0.3; rank by RS20, recomputed as of 5 sessions ago; breadth counts industries"
        s.industryCacheEmptyHint = "No industry index cache yet. Click \"Incremental refresh\" to pull 300+ Tonghuashun industry index K-lines (about a minute the first time); the cache is shared with Local Market Trend Research."
        s.cashFlowAuditName = "Cash-Flow Quality Audit"
        s.cashFlowAuditSubtitle = "Watch pool of up to 20 stocks × 5 annual reports: cash conversion, FCF margin, accrual ratio, receivable pressure, net-cash ratio and a field-completeness audit"
        s.watchPool = "Watch pool"
        s.watchPoolHint = "Up to 20 codes, comma or space separated; each stock fetches three annual statements separately (period=annual&limit=5) — the code list only bounds the pool"
        s.applyPool = "Apply"
        s.asOfLabel = "Disclosed by"
        s.asOfHint = "Only periods whose report_date_ms is on or before this date"
        s.screeningTable = "Screening table"
        s.sortBy = "Sort by"
        s.cashConversion = "Cash conversion"
        s.fcfMargin = "FCF margin"
        s.accrualRatio = "Accrual ratio"
        s.receivablePressure = "Receivable pressure"
        s.netCashRatio = "Net-cash ratio"
        s.fiveYearAverage = "5-yr avg"
        s.cashCoveredYears = "Years OCF ≥ profit"
        s.profitCashBridge = "Profit → operating cash-flow bridge"
        s.bridgeNetProfit = "Net profit"
        s.bridgeAccruals = "Accruals (profit − OCF)"
        s.bridgeOCF = "Operating cash flow"
        s.bridgeCapex = "Capex paid"
        s.bridgeAccrualsShort = "Accruals"
        s.bridgeCapexShort = "Capex"
        s.bridgeFCF = "Free cash flow"
        s.cashEvidence = "5-year cash evidence"
        s.cashEvidenceHint = "Net profit vs operating cash flow vs free cash flow (annual)"
        s.fieldAudit = "Field-completeness audit"
        s.fieldAuditHint = "Non-null counts of the 8 input fields across all companies × periods"
        s.periodsLoaded = "Periods"
        s.reportDate = "Report date"
        s.completeness = "Completeness"
        s.cashFlowMethod = "Cash conversion = OCF / net profit; FCF margin = (OCF − capex) / revenue; accrual ratio = (net profit − OCF) / total assets; receivable pressure = receivables / revenue; net-cash ratio = (cash − total liabilities) / total assets; blank when the denominator is 0 or missing; statements aligned on period_end_ms, disclosure gated by report_date_ms"
        s.loadPool = "Load pool"
        s.missingFieldsFormat = "%d/%d fields missing"
        s.financialHealthName = "Single-Stock Financial Check-up"
        s.financialHealthSubtitle = "Search and disambiguate → last 8 quarterly statements aligned by period plus latest indicators: a factual summary of growth, profitability, cash flow and leverage"
        s.searchPlaceholder = "Stock name or code, e.g. 300033"
        s.searchAction = "Check up"
        s.disambiguate = "Multiple matches — pick one"
        s.latestPeriod = "Latest period"
        s.cumulativeNote = "YTD"
        s.singleQuarterNote = "Single quarter (derived)"
        s.growthSection = "Growth"
        s.profitabilitySection = "Profitability"
        s.cashFlowSection = "Cash flow"
        s.leverageSection = "Leverage"
        s.revenue = "Revenue"
        s.netProfit = "Net profit"
        s.parentNetProfit = "Net profit to parent"
        s.operatingProfit = "Operating profit"
        s.grossMargin = "Gross margin"
        s.netMargin = "Net margin"
        s.eps = "Basic EPS"
        s.rdExpenses = "R&D expenses"
        s.ocf = "Operating cash flow"
        s.capex = "Capex paid"
        s.fcf = "Free cash flow"
        s.ocfToProfit = "OCF / net profit"
        s.totalAssets = "Total assets"
        s.totalDebt = "Total liabilities"
        s.cashHoldings = "Cash"
        s.equity = "Shareholders' equity"
        s.debtRatio = "Debt-to-assets"
        s.cashToDebt = "Cash / liabilities"
        s.receivables = "Receivables"
        s.yoy = "YoY"
        s.vsPrevious = "vs prior period"
        s.yearAgoSame = "Same period last year"
        s.seriesRevenue = "Revenue"
        s.seriesProfit = "Profit"
        s.seriesCashFlow = "Cash flow"
        s.seriesToggleHint = "Toggle YTD / single quarter; hover or use ← → to inspect periods"
        s.periodsTable = "8-period detail"
        s.indicatorsHeader = "Financial indicators (Tonghuashun)"
        s.financialHealthMethod = "Quarterly income and cash-flow statements are year-to-date; the balance sheet is point-in-time; single quarter = this YTD − prior YTD in the same fiscal year (blank if missing); YoY compares the same period a year earlier; null stays null; no valuation, peer averages or scores are computed"
        s.currencyLabel = "Currency"
        s.statementsComplete = "Periods with all 3 statements"
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
        case .industryMatrix: industryMatrixName
        case .cashFlowAudit: cashFlowAuditName
        case .financialHealth: financialHealthName
        }
    }

    func moduleSubtitle(_ module: AgentModule) -> String {
        switch module {
        case .limitUpPulse: limitUpPulseSubtitle
        case .dragonTigerTopology: dragonTigerTopologySubtitle
        case .heatRadar: heatRadarSubtitle
        case .marketTrend: marketTrendSubtitle
        case .dragonTigerWatch: dragonTigerWatchSubtitle
        case .industryMatrix: industryMatrixSubtitle
        case .cashFlowAudit: cashFlowAuditSubtitle
        case .financialHealth: financialHealthSubtitle
        }
    }

    func seriesName(_ kind: FinancialSeriesKind) -> String {
        switch kind {
        case .revenue: seriesRevenue
        case .profit: seriesProfit
        case .cashFlow: seriesCashFlow
        }
    }

    func sortKeyName(_ key: CashFlowAuditSortKey) -> String {
        switch key {
        case .cashConversion: cashConversion
        case .fcfMargin: fcfMargin
        case .accrualRatio: accrualRatio
        case .receivablePressure: receivablePressure
        case .netCashRatio: netCashRatio
        case .averageCashConversion: fiveYearAverage
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
        case let error as FuyaoError: describeFuyao(error)
        case let error as QuantError: describeQuant(error)
        default: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
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
}
