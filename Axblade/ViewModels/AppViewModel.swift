import Foundation

/// 串起设置、数据源与五个模块模型。视图只跟它打交道。
@MainActor
final class AppViewModel: ObservableObject {
    /// 当前打开的模块;nil = 模块卡列表。侧栏与内容区共用。
    @Published var selectedModule: AgentModule? {
        didSet { settings.lastModule = selectedModule }
    }
    @Published var settings: AppSettings { didSet { persistSettings() } }

    /// A 股数据源(fuyao)。测试注入内存实现。
    let data: any AShareDataProvider
    let calendar: TradingCalendar
    let limitUpPulse: LimitUpPulseModel
    let dragonTigerTopology: DragonTigerTopologyModel
    let heatRadar: HeatRadarModel
    let marketTrend: MarketTrendModel
    let dragonTigerWatch: DragonTigerWatchModel
    let industryMatrix: IndustryMatrixModel
    let cashFlowAudit: CashFlowAuditModel
    let financialHealth: FinancialHealthModel

    private let store: SettingsStore

    init(
        store: SettingsStore,
        data: any AShareDataProvider = FuyaoDataService(),
        researchStore: MarketResearchStore = MarketResearchStore(directory: MarketResearchStore.defaultDirectory())
    ) {
        self.store = store
        self.data = data
        let calendar = TradingCalendar(data: data)
        self.calendar = calendar
        self.limitUpPulse = LimitUpPulseModel(data: data, calendar: calendar)
        self.dragonTigerTopology = DragonTigerTopologyModel(data: data, calendar: calendar)
        self.heatRadar = HeatRadarModel(data: data, calendar: calendar)
        self.marketTrend = MarketTrendModel(data: data, calendar: calendar, store: researchStore)
        self.dragonTigerWatch = DragonTigerWatchModel(data: data, calendar: calendar)
        self.industryMatrix = IndustryMatrixModel(data: data, calendar: calendar, store: researchStore)
        self.cashFlowAudit = CashFlowAuditModel(data: data, calendar: calendar)
        self.financialHealth = FinancialHealthModel(data: data, calendar: calendar)
        let loadedSettings = store.loadSettings()
        self.settings = loadedSettings
        self.selectedModule = loadedSettings.lastModule

        for module in modules { module.describe = { [weak self] in self?.text.describe($0) ?? $0.localizedDescription } }
        marketTrend.sectorTag = loadedSettings.sectorTag
        dragonTigerWatch.days = loadedSettings.watchDays
        cashFlowAudit.pool = loadedSettings.cashFlowPool
    }

    convenience init() {
        self.init(store: SettingsStore(directory: SettingsStore.defaultDirectory()))
    }

    var modules: [ModuleModel] {
        [limitUpPulse, dragonTigerTopology, heatRadar, marketTrend, dragonTigerWatch, industryMatrix, cashFlowAudit, financialHealth]
    }

    /// 某个模块当前的报告文本(没算出来为 nil)。
    func moduleReport(_ module: AgentModule) -> String? {
        switch module {
        case .limitUpPulse: limitUpPulse.report?.promptText
        case .dragonTigerTopology: dragonTigerTopology.graph?.promptText
        case .heatRadar: heatRadar.report?.promptText
        case .marketTrend: marketTrend.report?.promptText
        case .dragonTigerWatch: dragonTigerWatch.report?.promptText
        case .industryMatrix: industryMatrix.report?.promptText
        case .cashFlowAudit: cashFlowAudit.report?.promptText
        case .financialHealth: financialHealth.report?.promptText
        }
    }

    func openModule(_ module: AgentModule) {
        selectedModule = module
    }

    // MARK: - 语言

    /// 当前语言的整张文案表;settings 是 @Published,切语言时视图自动刷新。
    var text: L10nStrings {
        settings.language.strings
    }

    func selectLanguage(_ language: AppLanguage) {
        settings.language = language
    }

    // MARK: - 模块参数

    func setSectorTag(_ tag: String) {
        guard AppSettings.sectorTags.contains(tag) else { return }
        settings.sectorTag = tag
        marketTrend.sectorTag = tag
    }

    func setWatchDays(_ days: Int) {
        guard AppSettings.watchDayOptions.contains(days) else { return }
        settings.watchDays = days
        dragonTigerWatch.days = days
    }

    /// 现金流稽核观察池:归一化 / 去重 / 截到 20 只后同时写入设置与模型。
    func setCashFlowPool(_ codes: [String]) {
        let pool = AppSettings.sanitizePool(codes)
        settings.cashFlowPool = pool
        cashFlowAudit.pool = pool
    }

    /// 从自由文本(逗号 / 空格 / 换行分隔)解析观察池。
    func setCashFlowPool(text: String) {
        setCashFlowPool(AShareSymbol.codes(in: text))
    }

    private func persistSettings() {
        try? store.saveSettings(settings)
    }
}
