import XCTest
import SwiftUI
import AppKit
@testable import Axblade

/// 主要界面能不能渲染出东西来。断言「渲出来了且不是一整块纯色」,
/// 同时把 PNG 落到宿主容器的 tmp 里,方便肉眼验收布局。
/// 输出路径会打印成 `AXBLADE_SNAPSHOT_OUTPUT=...`。
@MainActor
final class SnapshotTests: XCTestCase {
    private var outputDirectory: URL!

    override func setUpWithError() throws {
        outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AxbladeSnapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        print("AXBLADE_SNAPSHOT_OUTPUT=\(outputDirectory.path)")
    }

    func testRenderModulesGrid() throws {
        try render(name: "01-modules-grid", size: CGSize(width: 1120, height: 740)) {
            workspace(viewModel: Self.makeViewModel())
        }
    }

    func testRenderModulesGridEnglishDark() throws {
        let viewModel = Self.makeViewModel()
        viewModel.selectLanguage(.en)
        try render(name: "02-modules-grid-en-dark", size: CGSize(width: 1120, height: 740), appearance: .darkAqua) {
            workspace(viewModel: viewModel)
                .environment(\.l10n, L10nStrings.en)
        }
    }

    func testRenderSettings() throws {
        try render(name: "03-settings", size: CGSize(width: 760, height: 520)) {
            SettingsView(viewModel: Self.makeViewModel())
        }
    }

    func testRenderDataSettings() throws {
        try render(name: "04-data-settings", size: CGSize(width: 760, height: 520)) {
            DataSettingsView(viewModel: Self.makeViewModel())
        }
    }

    func testRenderModuleError() async throws {
        let stub = StubDataProvider()
        stub.failing = ["hotStocks"]
        let viewModel = Self.makeViewModel(data: stub)
        viewModel.openModule(.heatRadar)
        viewModel.heatRadar.load()
        await viewModel.heatRadar.task?.value
        XCTAssertNotNil(viewModel.heatRadar.errorText)
        try render(name: "05-module-error", size: CGSize(width: 1120, height: 740)) {
            workspace(viewModel: viewModel)
        }
    }

    // MARK: - 五个盘面模块(喂真实夹具)

    func testRenderLimitUpPulse() async throws {
        let viewModel = Self.makeViewModel()
        viewModel.openModule(.limitUpPulse)
        viewModel.limitUpPulse.load(date: "2026-09-08")
        await viewModel.limitUpPulse.task?.value
        XCTAssertNotNil(viewModel.limitUpPulse.report)
        try render(name: "20-limit-up-pulse", size: CGSize(width: 1240, height: 1500)) {
            workspace(viewModel: viewModel)
        }
    }

    func testRenderDragonTigerTopology() async throws {
        let viewModel = Self.makeViewModel()
        viewModel.openModule(.dragonTigerTopology)
        viewModel.dragonTigerTopology.load()
        await viewModel.dragonTigerTopology.task?.value
        XCTAssertNotNil(viewModel.dragonTigerTopology.graph)
        viewModel.dragonTigerTopology.selectedNodeID = "player:低位挖掘"
        try render(name: "21-dragon-tiger-topology", size: CGSize(width: 1240, height: 1500), appearance: .darkAqua) {
            workspace(viewModel: viewModel)
        }
    }

    func testRenderHeatRadar() async throws {
        let viewModel = Self.makeViewModel()
        viewModel.openModule(.heatRadar)
        viewModel.heatRadar.load()
        await viewModel.heatRadar.task?.value
        XCTAssertNotNil(viewModel.heatRadar.report)
        try render(name: "22-heat-radar", size: CGSize(width: 1240, height: 1500)) {
            workspace(viewModel: viewModel)
        }
    }

    func testRenderMarketTrend() async throws {
        let viewModel = Self.makeViewModel()
        viewModel.openModule(.marketTrend)
        viewModel.marketTrend.refresh()
        await viewModel.marketTrend.task?.value
        XCTAssertNotNil(viewModel.marketTrend.report)
        viewModel.marketTrend.stockSymbol = "600519"
        viewModel.marketTrend.researchStock()
        for _ in 0..<50 where viewModel.marketTrend.isLoadingStock {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertNotNil(viewModel.marketTrend.stockMetrics)
        try render(name: "23-market-trend", size: CGSize(width: 1240, height: 2000), appearance: .darkAqua) {
            workspace(viewModel: viewModel)
        }
    }

    func testRenderDragonTigerWatch() async throws {
        let viewModel = Self.makeViewModel()
        viewModel.openModule(.dragonTigerWatch)
        viewModel.dragonTigerWatch.load()
        await viewModel.dragonTigerWatch.task?.value
        XCTAssertNotNil(viewModel.dragonTigerWatch.report)
        viewModel.dragonTigerWatch.selectedPlayer = "低位挖掘"
        try render(name: "24-dragon-tiger-watch", size: CGSize(width: 1240, height: 1500)) {
            workspace(viewModel: viewModel)
        }
    }

    // MARK: - 财务 / 行业三模块

    func testRenderIndustryMatrix() async throws {
        let viewModel = Self.makeViewModel()
        viewModel.openModule(.industryMatrix)
        viewModel.industryMatrix.refresh()
        await viewModel.industryMatrix.task?.value
        XCTAssertNil(viewModel.industryMatrix.errorText)
        let report = try XCTUnwrap(viewModel.industryMatrix.report)
        viewModel.industryMatrix.select(report.rows.first?.thscode)
        for _ in 0..<50 where viewModel.industryMatrix.isLoadingEvidence {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertNotNil(viewModel.industryMatrix.evidence)
        try render(name: "25-industry-matrix", size: CGSize(width: 1240, height: 2000)) {
            workspace(viewModel: viewModel)
        }
    }

    func testRenderCashFlowAudit() async throws {
        let viewModel = Self.makeViewModel()
        viewModel.openModule(.cashFlowAudit)
        viewModel.cashFlowAudit.load()
        await viewModel.cashFlowAudit.task?.value
        XCTAssertNil(viewModel.cashFlowAudit.errorText)
        XCTAssertEqual(viewModel.cashFlowAudit.report?.companies.count, AppSettings.defaultCashFlowPool.count)
        try render(name: "26-cash-flow-audit", size: CGSize(width: 1240, height: 1800), appearance: .darkAqua) {
            workspace(viewModel: viewModel)
        }
    }

    func testRenderFinancialHealth() async throws {
        let viewModel = Self.makeViewModel()
        viewModel.openModule(.financialHealth)
        viewModel.financialHealth.search()
        await viewModel.financialHealth.task?.value
        XCTAssertNil(viewModel.financialHealth.errorText)
        XCTAssertEqual(viewModel.financialHealth.report?.thscode, "300033.SZ")
        viewModel.financialHealth.hoveredPeriodID = viewModel.financialHealth.report?.latest?.periodEndMs
        try render(name: "27-financial-health", size: CGSize(width: 1240, height: 2000)) {
            workspace(viewModel: viewModel)
        }
    }

    // MARK: -

    /// 与 RootView 相同的布局,保证快照所见即 app 所得。
    private func workspace(viewModel: AppViewModel) -> some View {
        HStack(spacing: 0) {
            SidebarView(viewModel: viewModel)
                .frame(width: 250)
            Divider().overlay(Theme.border)
            ModulesView(viewModel: viewModel)
        }
        .background(Theme.background)
    }

    private static func makeViewModel(data: StubDataProvider = StubDataProvider()) -> AppViewModel {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AxbladeSnapshot-\(UUID().uuidString)", isDirectory: true)
        return AppViewModel(
            store: SettingsStore(directory: directory), data: data,
            researchStore: MarketResearchStore(directory: directory.appendingPathComponent("research"))
        )
    }

    /// 走真实 AppKit 渲染路径(离屏窗口 + `cacheDisplay`)。
    /// `ImageRenderer` 画不了 List / TextField / Picker 这类由 AppKit 承载的控件,
    /// 会在原地留一块黄色占位,拿它验收界面等于什么都没验。
    private func render(
        name: String,
        size: CGSize,
        appearance: NSAppearance.Name = .aqua,
        @ViewBuilder content: () -> some View
    ) throws {
        let hosting = NSHostingView(rootView: AnyView(content()))
        // 不让宿主按内容的理想尺寸伸展:CI runner 的字体略宽,某行固定元素多 3px 就会把位图撑宽,
        // 快照要验的是「给定尺寸下画得出来」,尺寸本身必须固定。
        hosting.sizingOptions = []
        hosting.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        window.layoutIfNeeded()
        // 给 SwiftUI 一次布局 + 文字排版的机会,否则截到的是半成品。
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        hosting.displayIfNeeded()

        let bitmap = try XCTUnwrap(
            hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds),
            "\(name) 拿不到位图"
        )
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)

        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: outputDirectory.appendingPathComponent("\(name).png"))

        XCTAssertEqual(Double(bitmap.size.width), size.width, accuracy: 1, "\(name) 宽度不对")
        XCTAssertEqual(Double(bitmap.size.height), size.height, accuracy: 1, "\(name) 高度不对")
        // 纯色/空白渲染只有 1–2 种颜色;稀疏设置页在无头 CI runner 上只采到 7 种,阈值别定太高
        XCTAssertGreaterThan(distinctColorCount(in: bitmap), 3, "\(name) 渲染成了一整块纯色")
    }

    /// 稀疏采样看颜色够不够杂 —— 纯色图说明界面根本没画出来。
    private func distinctColorCount(in bitmap: NSBitmapImageRep) -> Int {
        var colors = Set<UInt32>()
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 17) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 17) {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                let packed = UInt32(color.redComponent * 255) << 16
                    | UInt32(color.greenComponent * 255) << 8
                    | UInt32(color.blueComponent * 255)
                colors.insert(packed)
            }
        }
        return colors.count
    }
}
