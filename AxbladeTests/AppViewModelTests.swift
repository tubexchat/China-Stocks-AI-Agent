import XCTest
@testable import Axblade

@MainActor
final class AppViewModelTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AxbladeVM-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func makeViewModel(data: StubDataProvider = StubDataProvider()) -> AppViewModel {
        AppViewModel(
            store: SettingsStore(directory: directory),
            data: data,
            researchStore: MarketResearchStore(directory: directory.appendingPathComponent("research"))
        )
    }

    func testOpeningModuleIsRememberedAcrossLaunches() {
        let viewModel = makeViewModel()
        XCTAssertNil(viewModel.selectedModule)

        viewModel.openModule(.heatRadar)

        XCTAssertEqual(viewModel.selectedModule, .heatRadar)
        XCTAssertEqual(SettingsStore(directory: directory).loadSettings().lastModule, .heatRadar)
        XCTAssertEqual(makeViewModel().selectedModule, .heatRadar)
    }

    func testSectorTagAndWatchDaysPropagateToModelsAndPersist() {
        let viewModel = makeViewModel()

        viewModel.setSectorTag("cn_concept")
        viewModel.setWatchDays(10)
        viewModel.setSectorTag("nope")
        viewModel.setWatchDays(42)

        XCTAssertEqual(viewModel.marketTrend.sectorTag, "cn_concept")
        XCTAssertEqual(viewModel.dragonTigerWatch.days, 10)
        let reloaded = makeViewModel()
        XCTAssertEqual(reloaded.settings.sectorTag, "cn_concept")
        XCTAssertEqual(reloaded.marketTrend.sectorTag, "cn_concept")
        XCTAssertEqual(reloaded.dragonTigerWatch.days, 10)
    }

    func testCashFlowPoolIsSanitizedAndPersisted() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.cashFlowAudit.pool, AppSettings.defaultCashFlowPool)

        viewModel.setCashFlowPool(text: "600519, sz000001 300033.SZ 600519 垃圾 1234567")
        XCTAssertEqual(viewModel.cashFlowAudit.pool, ["600519.SH", "000001.SZ", "300033.SZ"])
        XCTAssertEqual(makeViewModel().settings.cashFlowPool, ["600519.SH", "000001.SZ", "300033.SZ"])

        let many = (0..<30).map { String(format: "60%04d", $0) }
        viewModel.setCashFlowPool(many)
        XCTAssertEqual(viewModel.cashFlowAudit.pool.count, AppSettings.cashFlowPoolLimit, "观察池最多 20 只")

        viewModel.setCashFlowPool(text: "")
        XCTAssertEqual(viewModel.cashFlowAudit.pool, AppSettings.defaultCashFlowPool, "空池落回默认")
    }

    func testFinancialModulesLoadFromStub() async {
        let viewModel = makeViewModel()
        viewModel.financialHealth.query = "同花顺"
        viewModel.financialHealth.search()
        await viewModel.financialHealth.task?.value
        XCTAssertNil(viewModel.financialHealth.errorText)
        XCTAssertEqual(viewModel.financialHealth.report?.name, "同花顺")
        XCTAssertTrue(viewModel.moduleReport(.financialHealth)?.hasPrefix("【单股财务体检 · 同花顺 300033.SZ") == true)

        viewModel.setCashFlowPool(["600519.SH", "300033.SZ"])
        viewModel.cashFlowAudit.load()
        await viewModel.cashFlowAudit.task?.value
        XCTAssertNil(viewModel.cashFlowAudit.errorText)
        XCTAssertEqual(viewModel.cashFlowAudit.report?.companies.map(\.thscode), ["600519.SH", "300033.SZ"])
        XCTAssertEqual(viewModel.cashFlowAudit.report?.companies.first?.name, "贵州茅台")
        XCTAssertNotNil(viewModel.moduleReport(.cashFlowAudit))

        viewModel.industryMatrix.refresh()
        await viewModel.industryMatrix.task?.value
        XCTAssertNil(viewModel.industryMatrix.errorText)
        XCTAssertEqual(viewModel.industryMatrix.report?.rows.count, 12)
        XCTAssertEqual(viewModel.industryMatrix.report?.benchmarkName, "沪深300")
        XCTAssertNotNil(viewModel.moduleReport(.industryMatrix))
        // 行业缓存与全市场趋势共用:刷新后趋势模块也能直接从缓存出报告
        viewModel.marketTrend.loadFromCache()
        XCTAssertNotNil(viewModel.marketTrend.report)
    }

    func testSelectingLanguagePersistsAndSwitchesStrings() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.settings.language, .zh)
        XCTAssertEqual(viewModel.text.modulesHeader, L10nStrings.zh.modulesHeader)

        viewModel.selectLanguage(.en)

        XCTAssertEqual(viewModel.text.modulesHeader, L10nStrings.en.modulesHeader)
        XCTAssertEqual(SettingsStore(directory: directory).loadSettings().language, .en)
    }

    func testLegacySettingsJSONStillDecodes() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacy = """
        {"modelAlias":"kimi","language":"en","agentAutoContext":false,"disabledSources":["okx"],"sectorTag":"cn_concept","watchDays":3}
        """
        try Data(legacy.utf8).write(to: directory.appendingPathComponent("settings.json"))

        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.settings.language, .en)
        XCTAssertEqual(viewModel.settings.sectorTag, "cn_concept")
        XCTAssertEqual(viewModel.settings.watchDays, 3)
        XCTAssertNil(viewModel.settings.lastModule)
    }

    func testCorruptSettingsFileFallsBackToDefaults() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: directory.appendingPathComponent("settings.json"))

        XCTAssertEqual(makeViewModel().settings, AppSettings())
    }

    func testModuleErrorsAreDescribedInTheActiveLanguage() async {
        let stub = StubDataProvider()
        stub.failing = ["limitUpPool"]
        let viewModel = makeViewModel(data: stub)
        viewModel.selectLanguage(.en)

        viewModel.limitUpPulse.load()
        await viewModel.limitUpPulse.task?.value

        XCTAssertEqual(viewModel.limitUpPulse.errorText, L10nStrings.en.describe(FuyaoError.api(code: 5003, message: "stub failure")))
        XCTAssertNil(viewModel.limitUpPulse.report)
    }

    func testModuleReportsBecomeAvailableAfterLoading() async {
        let viewModel = makeViewModel()
        XCTAssertNil(viewModel.moduleReport(.limitUpPulse))

        viewModel.limitUpPulse.load(date: "2026-09-08")
        await viewModel.limitUpPulse.task?.value

        XCTAssertTrue(viewModel.moduleReport(.limitUpPulse)?.hasPrefix("【涨停情绪市场脉冲 · 2026-09-08】") == true)
    }

    func testNumberFormatting() {
        XCTAssertEqual(NumberFormat.number(64038.0), "64038")
        XCTAssertEqual(NumberFormat.number(2.31), "2.31")
        XCTAssertEqual(NumberFormat.number(0.001234), "0.001234")
        XCTAssertEqual(NumberFormat.percent(-0.509875), "-0.51%")
        XCTAssertEqual(NumberFormat.percent(2.309), "+2.31%")
    }
}
