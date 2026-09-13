import SwiftUI

/// 模块 8:单股财务体检。
struct FinancialHealthView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var model: FinancialHealthModel

    private var text: L10nStrings { viewModel.text }

    static let endpoints = [
        "GET /api/meta/tickers/search?q=…(消歧为唯一 A 股 thscode;请求头 X-api-key)",
        "GET /api/a-share/financials/income-statements?thscode=…&period=quarterly&limit=8",
        "GET /api/a-share/financials/balance-sheets?thscode=…&period=quarterly&limit=8",
        "GET /api/a-share/financials/cash-flow-statements?thscode=…&period=quarterly&limit=8",
        "GET /api/a-share/financials/indicators?thscode=…&report=yyyy-N(最新报告期)"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ModuleHeader(viewModel: viewModel, module: .financialHealth) {
                    TextField(text.searchPlaceholder, text: $model.query)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                        .onSubmit { model.search() }
                    Button(text.searchAction) { model.search() }
                        .disabled(model.isLoading || model.query.trimmingCharacters(in: .whitespaces).isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                }
                .controlSize(.small)
                ModuleStatusBar(model: model)

                if !model.candidates.isEmpty {
                    SectionCard(title: text.disambiguate) {
                        ForEach(model.candidates) { item in
                            Button { model.choose(item) } label: {
                                HStack(spacing: 8) {
                                    Text(item.name ?? "").font(.callout).foregroundStyle(Theme.text)
                                    Text(item.thscode).font(.caption.monospacedDigit()).foregroundStyle(Theme.muted)
                                    Text(AShareSymbol.board(of: item.thscode)).font(.caption2).foregroundStyle(Theme.muted)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let report = model.report {
                    headline(report)
                    if let latest = report.latest {
                        factGrid(report, latest)
                    }
                    seriesCard(report)
                    periodsCard(report)
                    if let indicators = report.indicators, !indicators.isEmpty {
                        indicatorsCard(indicators, report: report.indicatorReport)
                    }
                    ReportBar(report: report.promptText)
                    ProvenanceCard(
                        dataTime: "\(text.latestPeriod) \(report.latest?.label ?? "—")(\(text.cumulativeNote))· \(text.reportDate) \(report.latest.flatMap { RatioFormat.day($0.reportDateMs) } ?? "—") · \(text.currencyLabel) \(report.currency) · " + String(format: text.generatedAtFormat, ShanghaiDate.dayFormatter.string(from: report.generatedAt)),
                        endpoints: Self.endpoints,
                        methodology: text.financialHealthMethod
                    )
                }
                Spacer(minLength: 20)
            }
            .padding(24)
            .frame(maxWidth: 1200, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear { if model.report == nil && !model.isLoading && model.candidates.isEmpty { model.search() } }
    }

    // MARK: 头部事实

    private func headline(_ report: FinancialHealthReport) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
            KPITile(label: text.stock, value: report.name, color: Theme.accentStrong, caption: "\(report.thscode) · \(AShareSymbol.board(of: report.thscode))")
            KPITile(label: text.latestPeriod, value: report.latest?.label ?? "—", caption: "\(text.cumulativeNote) · \(text.reportDate) \(report.latest.flatMap { RatioFormat.day($0.reportDateMs) } ?? "—")")
            KPITile(label: text.yearAgoSame, value: report.yearAgo?.label ?? "—", caption: report.yearAgo.flatMap { RatioFormat.day($0.reportDateMs) })
            KPITile(label: text.statementsComplete, value: "\(report.completePeriods) / \(report.periods.count)", caption: "\(text.currencyLabel) \(report.currency)")
        }
    }

    private func factGrid(_ report: FinancialHealthReport, _ latest: FinancialHealthReport.Period) -> some View {
        let previous = report.previous
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], alignment: .leading, spacing: 14) {
            factCard(text.growthSection, [
                fact(text.revenue, RatioFormat.yuan(latest.revenue), yoy: latest.revenueYoY, previous: previous?.revenue, current: latest.revenue),
                fact(text.netProfit, RatioFormat.yuan(latest.netProfit), yoy: latest.netProfitYoY, previous: previous?.netProfit, current: latest.netProfit),
                fact(text.ocf, RatioFormat.yuan(latest.ocf), yoy: latest.ocfYoY, previous: previous?.ocf, current: latest.ocf),
                fact("\(text.revenue)(\(text.singleQuarterNote))", RatioFormat.yuan(latest.revenueQ)),
                fact("\(text.netProfit)(\(text.singleQuarterNote))", RatioFormat.yuan(latest.netProfitQ))
            ])
            factCard(text.profitabilitySection, [
                fact(text.grossMargin, RatioFormat.percent(latest.grossMargin), compare: previous?.grossMargin, current: latest.grossMargin, asPercent: true),
                fact(text.netMargin, RatioFormat.percent(latest.netMargin), compare: previous?.netMargin, current: latest.netMargin, asPercent: true),
                fact(text.parentNetProfit, RatioFormat.yuan(latest.parentNetProfit)),
                fact(text.operatingProfit, RatioFormat.yuan(latest.operatingProfit)),
                fact(text.eps, RatioFormat.number(latest.eps).map { "\($0) \(report.currency)" }),
                fact(text.rdExpenses, RatioFormat.yuan(latest.rdExpenses))
            ])
            factCard(text.cashFlowSection, [
                fact(text.ocf, RatioFormat.yuan(latest.ocf)),
                fact(text.capex, RatioFormat.yuan(latest.capex)),
                fact(text.fcf, RatioFormat.yuan(latest.fcf)),
                fact(text.ocfToProfit, RatioFormat.times(latest.cashConversion)),
                fact("\(text.ocf)(\(text.singleQuarterNote))", RatioFormat.yuan(latest.ocfQ))
            ])
            factCard(text.leverageSection, [
                fact(text.debtRatio, RatioFormat.percent(latest.debtRatio), compare: previous?.debtRatio, current: latest.debtRatio, asPercent: true),
                fact(text.cashToDebt, RatioFormat.times(latest.cashToDebt)),
                fact(text.totalAssets, RatioFormat.yuan(latest.assets)),
                fact(text.totalDebt, RatioFormat.yuan(latest.debt)),
                fact(text.cashHoldings, RatioFormat.yuan(latest.cash)),
                fact(text.equity, RatioFormat.yuan(latest.equity)),
                fact(text.receivables, RatioFormat.yuan(latest.receivables))
            ])
        }
    }

    private struct Fact: Identifiable {
        var label: String
        var value: String?
        var caption: String?
        var tone: Color?
        var id: String { label }
    }

    /// 金额类事实:同比 + 环比上期。
    private func fact(_ label: String, _ value: String?, yoy: Double? = nil, previous: Double? = nil, current: Double? = nil) -> Fact {
        var parts: [String] = []
        if let yoy { parts.append("\(text.yoy) \(RiskReport.percent(yoy))") }
        if let previous, let current, previous != 0 { parts.append("\(text.vsPrevious) \(RiskReport.percent((current - previous) / abs(previous)))") }
        return Fact(label: label, value: value, caption: parts.isEmpty ? nil : parts.joined(separator: " · "), tone: yoy.map(Theme.changeColor))
    }

    /// 比率类事实:与上期的百分点差。
    private func fact(_ label: String, _ value: String?, compare previous: Double?, current: Double?, asPercent: Bool) -> Fact {
        guard let previous, let current else { return Fact(label: label, value: value, caption: nil, tone: nil) }
        let delta = (current - previous) * (asPercent ? 100 : 1)
        return Fact(label: label, value: value, caption: "\(text.vsPrevious) \(delta >= 0 ? "+" : "")\(NumberFormat.number(delta))\(asPercent ? " pp" : "")", tone: nil)
    }

    private func factCard(_ title: String, _ facts: [Fact]) -> some View {
        SectionCard(title: title) {
            ForEach(facts) { fact in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(fact.label).font(.caption).foregroundStyle(Theme.muted).frame(width: 150, alignment: .leading).lineLimit(2)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 1) {
                        ValueText(text: fact.value, color: fact.tone ?? Theme.text).font(.callout.weight(.medium))
                        if let caption = fact.caption {
                            Text(caption).font(.caption2.monospacedDigit()).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
        }
    }

    // MARK: 序列图

    private func seriesPoints(_ report: FinancialHealthReport) -> (series: [PeriodBarChart.Series], points: [PeriodBarChart.Point]) {
        let single = model.showSingleQuarter
        switch model.seriesKind {
        case .revenue:
            return ([.init(name: single ? "\(text.revenue)(\(text.singleQuarterNote))" : "\(text.revenue)(\(text.cumulativeNote))", color: Theme.accent)],
                    report.periods.map { .init(id: $0.periodEndMs, label: $0.label, values: [single ? $0.revenueQ : $0.revenue]) })
        case .profit:
            if single {
                return ([.init(name: "\(text.netProfit)(\(text.singleQuarterNote))", color: Theme.up)],
                        report.periods.map { .init(id: $0.periodEndMs, label: $0.label, values: [$0.netProfitQ]) })
            }
            return ([.init(name: "\(text.netProfit)(\(text.cumulativeNote))", color: Theme.up), .init(name: text.parentNetProfit, color: Theme.accent)],
                    report.periods.map { .init(id: $0.periodEndMs, label: $0.label, values: [$0.netProfit, $0.parentNetProfit]) })
        case .cashFlow:
            if single {
                return ([.init(name: "\(text.ocf)(\(text.singleQuarterNote))", color: Theme.up)],
                        report.periods.map { .init(id: $0.periodEndMs, label: $0.label, values: [$0.ocfQ]) })
            }
            return ([.init(name: text.ocf, color: Theme.up), .init(name: text.capex, color: Theme.down), .init(name: text.fcf, color: Theme.accent)],
                    report.periods.map { .init(id: $0.periodEndMs, label: $0.label, values: [$0.ocf, $0.capex, $0.fcf]) })
        }
    }

    private func seriesCard(_ report: FinancialHealthReport) -> some View {
        let data = seriesPoints(report)
        return SectionCard(title: "\(text.seriesName(model.seriesKind)) · \(model.showSingleQuarter ? text.singleQuarterNote : text.cumulativeNote)", subtitle: text.seriesToggleHint) {
            HStack(spacing: 12) {
                Picker("", selection: $model.seriesKind) {
                    ForEach(FinancialSeriesKind.allCases) { kind in
                        Text(text.seriesName(kind)).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Toggle(text.singleQuarterNote, isOn: $model.showSingleQuarter)
                    .toggleStyle(.switch)
                Spacer()
                if let hovered = model.hoveredPeriodID, let period = report.periods.first(where: { $0.periodEndMs == hovered }) {
                    Text("\(period.label) · \(text.reportDate) \(RatioFormat.day(period.reportDateMs) ?? "—")").font(.caption.monospacedDigit()).foregroundStyle(Theme.muted)
                }
            }
            .controlSize(.small)
            PeriodBarChart(series: data.series, points: data.points, hovered: $model.hoveredPeriodID, height: 220)
                .focusable()
                .onKeyPress(.leftArrow) { stepHovered(report, -1); return .handled }
                .onKeyPress(.rightArrow) { stepHovered(report, 1); return .handled }
        }
    }

    private func stepHovered(_ report: FinancialHealthReport, _ delta: Int) {
        let ids = report.periods.map(\.periodEndMs)
        guard !ids.isEmpty else { return }
        let index = model.hoveredPeriodID.flatMap { ids.firstIndex(of: $0) } ?? (delta > 0 ? -1 : ids.count)
        model.hoveredPeriodID = ids[max(0, min(ids.count - 1, index + delta))]
    }

    // MARK: 8 期明细

    private func periodsCard(_ report: FinancialHealthReport) -> some View {
        SectionCard(title: text.periodsTable) {
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(text.periodsLoaded).frame(width: 70, alignment: .leading)
                        Text(text.reportDate).frame(width: 80, alignment: .leading)
                        ForEach([text.revenue, text.yoy, text.netProfit, text.yoy, text.ocf, text.fcf, text.grossMargin, text.debtRatio], id: \.self) { title in
                            Text(title).frame(width: 84, alignment: .trailing).lineLimit(1)
                        }
                    }
                    .font(.caption2).foregroundStyle(Theme.muted)
                    ForEach(report.periods.reversed()) { period in
                        HStack(spacing: 8) {
                            Text(period.label).font(.caption.monospacedDigit()).foregroundStyle(model.hoveredPeriodID == period.periodEndMs ? Theme.accentStrong : Theme.text).frame(width: 70, alignment: .leading)
                            Text(RatioFormat.day(period.reportDateMs) ?? "—").font(.caption2.monospacedDigit()).foregroundStyle(Theme.muted).frame(width: 80, alignment: .leading)
                            cell(RatioFormat.yuan(period.revenue))
                            cell(RatioFormat.percent(period.revenueYoY), tone: period.revenueYoY.map(Theme.changeColor))
                            cell(RatioFormat.yuan(period.netProfit))
                            cell(RatioFormat.percent(period.netProfitYoY), tone: period.netProfitYoY.map(Theme.changeColor))
                            cell(RatioFormat.yuan(period.ocf))
                            cell(RatioFormat.yuan(period.fcf))
                            cell(RatioFormat.percent(period.grossMargin))
                            cell(RatioFormat.percent(period.debtRatio))
                            if !period.isComplete { Chip(text: text.fetchFailed, color: Theme.accentSoft, foreground: Theme.accentStrong) }
                        }
                        .contentShape(Rectangle())
                        .onHover { inside in if inside { model.hoveredPeriodID = period.periodEndMs } }
                    }
                }
            }
        }
    }

    private func cell(_ value: String?, tone: Color? = nil) -> some View {
        ValueText(text: value, color: tone ?? Theme.text).font(.caption).frame(width: 84, alignment: .trailing)
    }

    // MARK: 财务指标

    private func indicatorsCard(_ indicators: FinancialIndicatorsData, report: String?) -> some View {
        SectionCard(title: "\(text.indicatorsHeader) · \(report ?? "")") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(indicators.abilities) { ability in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(FinancialIndicatorCatalog.abilityName(ability.ability)).font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                        ForEach(ability.indicators) { indicator in
                            HStack(spacing: 6) {
                                Text(FinancialIndicatorCatalog.name(indicator.index_id)).font(.caption).foregroundStyle(Theme.text).lineLimit(1)
                                Spacer(minLength: 4)
                                ValueText(text: indicator.value == nil ? nil : FinancialIndicatorCatalog.display(indicator)).font(.caption)
                            }
                        }
                    }
                    .padding(10)
                    .background(Theme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}
