import SwiftUI

/// Tools 工作区:工具卡列表 → 工具页。选中项存 ViewModel,与侧栏工具清单联动。
struct ToolsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Group {
            if let tool = viewModel.selectedTool {
                ToolRunnerView(viewModel: viewModel, tool: tool) {
                    viewModel.selectedTool = nil
                }
                .id(tool)   // 换工具时重置表单状态
            } else {
                toolGrid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    private var toolGrid: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.text.quantToolsHeader)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text(viewModel.text.quantToolsSubtitle)
                    .font(.callout)
                    .foregroundStyle(Theme.muted)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
                ForEach(QuantTool.allCases) { tool in
                    Button {
                        viewModel.selectedTool = tool
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: tool.icon)
                                .font(.system(size: 26))
                                .foregroundStyle(Theme.accent)
                            Text(viewModel.text.toolName(tool))
                                .font(.headline)
                                .foregroundStyle(Theme.text)
                            Text(viewModel.text.toolSubtitle(tool))
                                .font(.callout)
                                .foregroundStyle(Theme.muted)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: 900)
        .frame(maxWidth: .infinity)
    }
}

/// 单个工具页:配置表单 → 运行 → 结果面板 → AI 解读。
struct ToolRunnerView: View {
    @ObservedObject var viewModel: AppViewModel
    let tool: QuantTool
    let onBack: () -> Void

    @State private var source: MarketSourceKind = .binance
    @State private var symbol = ""
    @State private var days = 365
    // 回测参数
    @State private var fastMA = 5
    @State private var slowMA = 20
    // GBDT 参数
    @State private var trees = 120
    @State private var depth = 3

    @State private var isRunning = false
    @State private var errorText: String?
    @State private var resultLines: [(String, String)] = []
    @State private var resultCurves: [(String, [Double])] = []
    @State private var reportText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                configForm
                if isRunning {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(viewModel.text.running).font(.callout).foregroundStyle(Theme.muted)
                    }
                }
                if let errorText {
                    Text(errorText)
                        .font(.callout)
                        .foregroundStyle(Theme.down)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if reportText != nil {
                    resultPanel
                }
                Spacer(minLength: 20)
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            // 默认选第一个启用的源,避免选中一个被禁用的源
            if !viewModel.enabledSources.contains(source), let first = viewModel.enabledSources.first {
                source = first
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .foregroundStyle(Theme.muted)
            }
            .buttonStyle(.plain)
            .help(viewModel.text.backToTools)
            Image(systemName: tool.icon)
                .foregroundStyle(Theme.accent)
            Text(viewModel.text.toolName(tool))
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.text)
        }
    }

    private var configForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Picker(viewModel.text.sourcePicker, selection: $source) {
                    ForEach(viewModel.enabledSources) { kind in
                        Text(viewModel.text.sourceName(kind)).tag(kind)
                    }
                }
                .fixedSize()

                TextField(viewModel.text.symbolHint(source), text: $symbol)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .onSubmit(run)

                Picker(viewModel.text.historyPicker, selection: $days) {
                    Text(String(format: viewModel.text.daysFormat, 90)).tag(90)
                    Text(String(format: viewModel.text.daysFormat, 180)).tag(180)
                    Text(String(format: viewModel.text.daysFormat, 365)).tag(365)
                }
                .fixedSize()
            }

            HStack(spacing: 10) {
                switch tool {
                case .backtest:
                    Stepper(String(format: viewModel.text.fastMAFormat, fastMA), value: $fastMA, in: 2...60)
                    Stepper(String(format: viewModel.text.slowMAFormat, slowMA), value: $slowMA, in: 3...120)
                case .gbdt:
                    Stepper(String(format: viewModel.text.treesFormat, trees), value: $trees, in: 20...400, step: 20)
                    Stepper(String(format: viewModel.text.depthFormat, depth), value: $depth, in: 2...6)
                case .risk, .factor:
                    EmptyView()
                }

                Button(viewModel.text.run, action: run)
                    .keyboardShortcut(.defaultAction)
                    .disabled(symbol.trimmingCharacters(in: .whitespaces).isEmpty || isRunning)
            }
        }
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var resultPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                ForEach(resultLines, id: \.0) { label, value in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(label).font(.caption).foregroundStyle(Theme.muted)
                        Text(value)
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(valueColor(value))
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            ForEach(resultCurves, id: \.0) { label, values in
                VStack(alignment: .leading, spacing: 6) {
                    Text(label).font(.caption).foregroundStyle(Theme.muted)
                    SparkLine(values: values)
                        .frame(height: 60)
                }
            }

            HStack {
                Button {
                    if let reportText { viewModel.analyze(report: reportText) }
                } label: {
                    Label(viewModel.text.analyzeWithAI, systemImage: "sparkles")
                }
                Text(viewModel.text.disclaimer)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// 结果数字按方向着色:跌/负数用 down,涨/正数用 up,其余保持正文色。
    private func valueColor(_ value: String) -> Color {
        if value.hasPrefix("-") { return Theme.down }
        if value.hasPrefix("+") { return Theme.up }
        if value == viewModel.text.bullish { return Theme.up }
        if value == viewModel.text.bearish { return Theme.down }
        return Theme.text
    }

    private func run() {
        let text = symbol.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isRunning else { return }
        isRunning = true
        errorText = nil
        reportText = nil

        let tool = tool
        let source = source
        let days = days
        let fast = fastMA, slow = slowMA, trees = trees, depth = depth

        Task { @MainActor in
            do {
                var closes = try await viewModel.fetchDailyCloses(source: source, symbol: text, days: days)
                closes = Array(closes.suffix(days))
                let sourceName = source.displayName
                let strings = viewModel.text

                switch tool {
                case .risk:
                    var report = try RiskAnalyzer.run(closes: closes)
                    report.symbol = text.uppercased()
                    report.sourceName = sourceName
                    resultLines = [
                        (strings.var95, RiskReport.percent(report.var95)),
                        (strings.var99, RiskReport.percent(report.var99)),
                        (strings.maxDrawdown, RiskReport.percent(report.maxDrawdown)),
                        (strings.annualVol, RiskReport.percent(report.annualVol)),
                        (strings.sharpe, MarketSnapshot.formatNumber(report.sharpe))
                    ]
                    resultCurves = [(String(format: strings.closesCurveFormat, closes.count), closes)]
                    reportText = report.promptText
                case .backtest:
                    var result = try Backtester.run(closes: closes, fast: fast, slow: slow)
                    result.symbol = text.uppercased()
                    result.sourceName = sourceName
                    resultLines = [
                        (strings.strategyReturn, RiskReport.percent(result.strategyReturn)),
                        (strings.holdReturn, RiskReport.percent(result.holdReturn)),
                        (strings.annualized, RiskReport.percent(result.annualized)),
                        (strings.maxDrawdown, RiskReport.percent(result.maxDrawdown)),
                        (strings.tradeCount, "\(result.trades)"),
                        (strings.winRate, RiskReport.percent(result.winRate))
                    ]
                    resultCurves = [
                        (strings.strategyCurve, result.equityCurve),
                        (strings.holdCurve, result.holdCurve)
                    ]
                    reportText = result.promptText
                case .factor:
                    var report = try FactorMiner.run(closes: closes)
                    report.symbol = text.uppercased()
                    report.sourceName = sourceName
                    resultLines = report.rankings.map { ranking in
                        (
                            ranking.name,
                            "IC \(MarketSnapshot.formatNumber(ranking.ic)) · \(strings.layeredPrefix) \(RiskReport.percent(ranking.spread))"
                        )
                    }
                    resultCurves = [(String(format: strings.closesCurveFormat, closes.count), closes)]
                    reportText = report.promptText
                case .gbdt:
                    var forecast = try GBDTForecaster.run(closes: closes, trees: trees, depth: depth)
                    forecast.symbol = text.uppercased()
                    forecast.sourceName = sourceName
                    let topFeatures = forecast.featureImportance
                        .sorted { $0.1 > $1.1 }.prefix(3)
                        .map { "\($0.0) \(RiskReport.percent($0.1))" }
                        .joined(separator: " · ")
                    resultLines = [
                        (strings.nextDayDirection, strings.direction(forecast.direction)),
                        (strings.predictedReturn, RiskReport.percent(forecast.predictedReturn)),
                        (strings.hitRate, RiskReport.percent(forecast.validationHitRate)),
                        (strings.sampleSplit, "\(forecast.trainSamples) / \(forecast.validationSamples)"),
                        (strings.keyFeatures, topFeatures)
                    ]
                    resultCurves = [(String(format: strings.closesCurveFormat, closes.count), closes)]
                    reportText = forecast.promptText
                }
            } catch {
                errorText = viewModel.text.describe(error)
            }
            isRunning = false
        }
    }
}
