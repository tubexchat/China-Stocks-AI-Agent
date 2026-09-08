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

    func testRenderEmptyState() throws {
        try render(name: "01-empty-state", size: CGSize(width: 1120, height: 740)) {
            workspace(viewModel: Self.makeViewModel(seeded: false))
        }
    }

    func testRenderConversation() throws {
        try render(name: "02-conversation", size: CGSize(width: 1120, height: 740)) {
            workspace(viewModel: Self.makeViewModel(seeded: true))
        }
    }

    func testRenderConversationDark() throws {
        try render(name: "05-conversation-dark", size: CGSize(width: 1120, height: 740), appearance: .darkAqua) {
            workspace(viewModel: Self.makeViewModel(seeded: true))
        }
    }

    func testRenderErrorMessage() throws {
        try render(name: "03-error", size: CGSize(width: 1120, height: 740)) {
            workspace(viewModel: Self.makeViewModel(seeded: true, withError: true))
        }
    }

    func testRenderSettings() throws {
        try render(name: "04-settings", size: CGSize(width: 760, height: 500)) {
            SettingsView(viewModel: Self.makeViewModel(seeded: true))
        }
    }

    func testRenderAccountSignedOut() throws {
        try render(name: "06-account-signed-out", size: CGSize(width: 760, height: 500)) {
            AccountSettingsView(viewModel: Self.makeViewModel(seeded: false))
        }
    }

    /// 已登录仪表盘:额度条 / 权限芯片 / 设备列表都要有真数据才看得出布局。
    func testRenderAccountSignedIn() async throws {
        let viewModel = Self.makeViewModel(seeded: false, signedIn: true)
        await viewModel.refreshMe()
        await viewModel.refreshSessions()

        try render(name: "07-account-signed-in", size: CGSize(width: 760, height: 720)) {
            AccountSettingsView(viewModel: viewModel)
        }
    }

    func testRenderSourcesSettings() throws {
        try render(name: "08-sources", size: CGSize(width: 760, height: 500)) {
            SourcesSettingsView(viewModel: Self.makeViewModel(seeded: false))
        }
    }

    func testRenderComposerWithAttachmentChips() throws {
        let viewModel = Self.makeViewModel(seeded: false)
        viewModel.attach(Self.sampleSnapshot(symbol: "BTCUSDT", change: 2.31))
        viewModel.attach(Self.sampleSnapshot(symbol: "600519.SS", change: -0.82))
        try render(name: "09-composer-chips", size: CGSize(width: 1120, height: 740)) {
            workspace(viewModel: viewModel)
        }
    }

    func testRenderAttachmentPreviewCard() throws {
        try render(name: "10-preview-card", size: CGSize(width: 440, height: 200)) {
            SnapshotPreviewCard(snapshot: Self.sampleSnapshot(symbol: "AAPL", change: 1.6, closes: [301, 305, 299, 303, 308]))
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
        }
    }

    func testRenderToolsGrid() throws {
        let viewModel = Self.makeViewModel(seeded: false)
        viewModel.workspace = .tools
        try render(name: "11-tools-grid", size: CGSize(width: 1120, height: 740)) {
            workspace(viewModel: viewModel)
        }
    }

    func testRenderEnglishConversation() throws {
        let viewModel = Self.makeViewModel(seeded: true)
        viewModel.selectLanguage(.en)
        try render(name: "13-english-conversation", size: CGSize(width: 1120, height: 740)) {
            workspace(viewModel: viewModel)
                .environment(\.l10n, L10nStrings.en)
        }
    }

    func testRenderGeneralSettings() throws {
        try render(name: "14-general-settings", size: CGSize(width: 760, height: 500)) {
            GeneralSettingsView(viewModel: Self.makeViewModel(seeded: false))
        }
    }

    func testRenderBacktestResultPanel() throws {
        // 真内核跑一段合成行情,渲染指标 + 双净值曲线
        let closes: [Double] = (0..<250).map { (i: Int) -> Double in
            let x = Double(i)
            return 100 + x * 0.15 + 12 * sin(x / 11)
        }
        var result = try Backtester.run(closes: closes)
        result.symbol = "BTCUSDT"
        result.sourceName = "Binance"

        try render(name: "12-backtest-result", size: CGSize(width: 760, height: 520)) {
            VStack(alignment: .leading, spacing: 14) {
                Text("历史回测 · \(result.symbol)").font(.title2.weight(.semibold)).foregroundStyle(Theme.text)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    ForEach([
                        ("策略收益", RiskReport.percent(result.strategyReturn)),
                        ("买入持有", RiskReport.percent(result.holdReturn)),
                        ("最大回撤", RiskReport.percent(result.maxDrawdown)),
                        ("胜率", RiskReport.percent(result.winRate))
                    ], id: \.0) { label, value in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(label).font(.caption).foregroundStyle(Theme.muted)
                            Text(value).font(.title3.weight(.semibold)).foregroundStyle(Theme.text)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.background)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                SparkLine(values: result.equityCurve).frame(height: 60)
                SparkLine(values: result.holdCurve).frame(height: 60)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.surface)
        }
    }

    private static func sampleSnapshot(
        symbol: String, change: Double, closes: [Double] = [64100, 64900, 63800, 64038]
    ) -> MarketSnapshot {
        MarketSnapshot(
            source: .binance, symbol: symbol, name: nil,
            price: 64038, changePercent: change,
            high: 65379, low: 63806, volume: 13676, currency: nil,
            closes: closes, fetchedAt: Date(timeIntervalSince1970: 1_786_500_000)
        )
    }

    // MARK: -

    /// 与 RootView 相同的切换逻辑,保证快照所见即 app 所得。
    private func workspace(viewModel: AppViewModel) -> some View {
        HStack(spacing: 0) {
            SidebarView(viewModel: viewModel)
                .frame(width: 250)
            Divider().overlay(Theme.border)
            if viewModel.workspace == .tools {
                ToolsView(viewModel: viewModel)
            } else {
                ChatView(viewModel: viewModel)
            }
        }
        .background(Theme.background)
    }

    /// spec 1.5 的示例响应,给已登录仪表盘喂数据。
    private static let meJSON = """
    {"user":{"id":12,"email":"nick@example.com","display_name":"Nick","plan":"free","created_at":"2026-08-18T03:00:00Z","kind":"user"},
     "plan":{"name":"free","chat_requests_per_day":50,"market_requests_per_day":500},
     "quota":{"chat":{"limit":50,"used":12,"remaining":38,"reset_at":"2026-08-19T00:00:00Z"},
              "market":{"limit":500,"used":37,"remaining":463,"reset_at":"2026-08-19T00:00:00Z"}},
     "permissions":{"models":[{"alias":"deepseek","display_name":"DeepSeek-V4-Flash-0731"},
                              {"alias":"kimi","display_name":"Kimi-K2.7-Code"}],
                    "market_sources":[{"id":"binance","label":"Binance Spot","paths":["ticker/24hr","klines"]}]},
     "session":{"id":3,"client":"mac","created_at":"2026-08-18T03:00:00Z"}}
    """

    private static func makeViewModel(
        seeded: Bool, withError: Bool = false, signedIn: Bool = false
    ) -> AppViewModel {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AxbladeSnapshot-\(UUID().uuidString)", isDirectory: true)
        let store = ConversationStore(directory: directory)
        // 未登录快照不能受本机钥匙串影响,登录态显式给定。
        var accountService = AccountService(tokenProvider: { nil })
        if signedIn {
            try? store.saveAccount(UserAccount(
                email: "nick@example.com", displayName: "Nick", plan: "free"
            ))
            MockHTTPProtocol.install([
                ("/me/sessions", 200, """
                {"sessions":[{"id":3,"client":"mac","created_at":"2026-08-18 11:00","last_used_at":"2026-08-18 11:20","current":true},
                             {"id":4,"client":"web","created_at":"2026-08-17 09:30","last_used_at":"2026-08-17 21:02","current":false}]}
                """),
                ("/me", 200, meJSON)
            ])
            accountService = AccountService(
                session: MockHTTPProtocol.session(),
                baseURL: Backend.baseURL,
                tokenProvider: { "snapshot-token" }
            )
        }

        if seeded {
            // 两条会话的 updatedAt 必须拉开,否则同毫秒的排序由 UUID 决定,截图会飘。
            let now = Date()
            var conversation = Conversation(title: "BTC 短线均线与关键位", updatedAt: now)
            conversation.messages = [
                ChatMessage(role: .user, content: "看一下 BTC 的短期均线和上下关键价位"),
                ChatMessage(role: .assistant, content: """
                ## 3. 均线与关键位置
                粗略估算几个短期均线:

                - MA5 ≈ 63,567
                - MA10 ≈ 63,728
                - MA20 ≈ 63,892
                  - 与 MA10 距离很近,随时可能金叉
                - MA30 ≈ 64,214

                当前价格 **64,271** 站在这些均线上方,短线偏强;但均线还没有完全形成多头排列,\
                所以只能算反弹,还不能说是趋势反转。

                ### 上方阻力
                | 区间 | 说明 |
                |---|---|
                | 64,600–64,700 | 日内高点 / 短期压力 |
                | 65,000–65,400 | 前期密集成交区 |
                | 66,500 | 30 日收盘高点附近 |

                ### 下方支撑
                1. 63,800:MA20 附近
                2. 63,200:前低

                > 仅供研究参考,不构成投资建议。

                ```swift
                let bias = (price - ma20) / ma20   // +0.6%
                ```
                """, isError: false)
            ]
            if withError {
                conversation.messages.append(
                    ChatMessage(role: .assistant, content: "服务返回 HTTP 401:invalid api key", isError: true)
                )
            }
            var older = Conversation(title: "周末装修采购清单", updatedAt: now.addingTimeInterval(-3600))
            older.messages = [ChatMessage(role: .user, content: "帮我列个清单")]
            try? store.saveConversations([conversation, older])
        }

        let viewModel = AppViewModel(store: store, accountService: accountService)
        viewModel.accountTask?.cancel()
        return viewModel
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
