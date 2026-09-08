import XCTest
@testable import Axblade

/// 打真实公共端点的冒烟测试,默认跳过,套件保持离线。
/// 手动验证:`xcodebuild test ... TEST_RUNNER_AXBLADE_LIVE=1 -only-testing:AxbladeTests/LiveNetworkSmokeTests`
final class LiveNetworkSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        // 沙盒宿主可能收不到 TEST_RUNNER_ 环境变量,容器 tmp 里放个标记文件也能开。
        let markerExists = FileManager.default.fileExists(atPath: NSTemporaryDirectory() + "AXBLADE_LIVE")
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["AXBLADE_LIVE"] != "1" && !markerExists,
            "未设置 AXBLADE_LIVE=1(或容器 tmp 标记文件),跳过真网冒烟"
        )
    }

    func testBinanceLive() async throws {
        let snapshot = try await BinanceMarketService().snapshot(rawSymbol: "btc")
        XCTAssertEqual(snapshot.symbol, "BTCUSDT")
        XCTAssertGreaterThan(snapshot.price, 0)
        XCTAssertFalse(snapshot.closes.isEmpty)
        print("LIVE Binance:", snapshot.chipText)
    }

    func testOKXLive() async throws {
        let snapshot = try await OKXMarketService().snapshot(rawSymbol: "ethusdt")
        XCTAssertEqual(snapshot.symbol, "ETH-USDT")
        XCTAssertGreaterThan(snapshot.price, 0)
        XCTAssertFalse(snapshot.closes.isEmpty)
        print("LIVE OKX:", snapshot.chipText)
    }

    func testMEXCLive() async throws {
        let snapshot = try await MEXCMarketService().snapshot(rawSymbol: "SOL")
        XCTAssertEqual(snapshot.symbol, "SOLUSDT")
        XCTAssertGreaterThan(snapshot.price, 0)
        print("LIVE MEXC:", snapshot.chipText)
    }

    func testYahooFourMarketsLive() async throws {
        let cases: [(MarketSourceKind, String, String)] = [
            (.usStock, "AAPL", "AAPL"),
            (.krStock, "005930", "005930.KS"),
            (.hkStock, "700", "0700.HK"),
            (.aShare, "600519", "600519.SS")
        ]
        for (market, input, expected) in cases {
            let snapshot = try await YahooFinanceService(market: market).snapshot(rawSymbol: input)
            XCTAssertEqual(snapshot.symbol, expected)
            XCTAssertGreaterThan(snapshot.price, 0)
            print("LIVE Yahoo \(market.displayName):", snapshot.chipText, snapshot.name ?? "")
        }
    }

    /// Tools 工作区的完整链路:7 个数据源逐一拉真实日线,把四个量化引擎都跑一遍。
    /// 与 ToolRunnerView.run() 同一条代码路径(dailyCloses → 引擎 → 报告)。
    func testQuantToolsPipelineLiveOnAllSources() async throws {
        let cases: [(MarketSourceKind, String)] = [
            (.binance, "BTC"), (.okx, "ethusdt"), (.mexc, "SOL"),
            (.usStock, "AAPL"), (.krStock, "005930"), (.hkStock, "700"), (.aShare, "600519")
        ]
        let services = MarketServiceRegistry.services()

        for (source, symbol) in cases {
            let service = try XCTUnwrap(services[source])
            let closes = try await service.dailyCloses(rawSymbol: symbol, days: 365)
            XCTAssertGreaterThan(closes.count, 60, "\(source) 日线太少,四个工具没法跑")

            let risk = try RiskAnalyzer.run(closes: closes)
            XCTAssertTrue(risk.annualVol.isFinite && risk.maxDrawdown.isFinite)

            let backtest = try Backtester.run(closes: closes, fast: 5, slow: 20)
            XCTAssertEqual(backtest.equityCurve.count, backtest.holdCurve.count)

            let factors = try FactorMiner.run(closes: closes)
            XCTAssertFalse(factors.rankings.isEmpty)

            let forecast = try GBDTForecaster.run(closes: closes, trees: 40, depth: 3)
            XCTAssertTrue(["看涨", "看跌"].contains(forecast.direction))
            XCTAssertFalse(forecast.promptText.isEmpty)

            print("LIVE tools \(source.displayName): \(closes.count) 根日线,四个引擎全部通过")
        }
    }

    /// 「让 AI 解读」完整回路:真实回测报告 → AppViewModel.analyze → 官方后端 → AI 回复。
    /// 需要钥匙串里已有登录令牌(客户端不再内置令牌),没有就跳过。
    @MainActor
    func testAnalyzeReportThroughBackendLive() async throws {
        try XCTSkipIf(TokenStore.token() == nil, "钥匙串里没有登录令牌,跳过后端 AI 回路冒烟")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AxbladeLive-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let closes = try await BinanceMarketService().dailyCloses(rawSymbol: "BTC", days: 180)
        var result = try Backtester.run(closes: closes, fast: 5, slow: 20)
        result.symbol = "BTCUSDT"
        result.sourceName = "Binance"

        let viewModel = AppViewModel(store: ConversationStore(directory: directory))
        viewModel.analyze(report: result.promptText)
        await viewModel.streamingTask?.value

        let reply = try XCTUnwrap(viewModel.current?.messages.last)
        XCTAssertEqual(reply.role, .assistant)
        XCTAssertFalse(reply.isError, "AI 解读失败:\(reply.content)")
        XCTAssertGreaterThan(reply.content.count, 20)
        print("LIVE analyze: AI 回复 \(reply.content.count) 字,开头:\(reply.content.prefix(60))")
    }
}
