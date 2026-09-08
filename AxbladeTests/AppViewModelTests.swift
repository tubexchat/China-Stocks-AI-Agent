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
