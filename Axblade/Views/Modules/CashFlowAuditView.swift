import SwiftUI

/// 模块 7:现金流质量稽核台。
struct CashFlowAuditView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var model: CashFlowAuditModel
    @State private var poolText = ""

    private var text: L10nStrings { viewModel.text }

    static let endpoints = [
        "GET /api/meta/tickers/search?q=…(逐只取名称)",
        "GET /api/a-share/financials/income-statements?thscode=…&period=annual&limit=5(单只)",
        "GET /api/a-share/financials/balance-sheets?thscode=…&period=annual&limit=5(单只)",
        "GET /api/a-share/financials/cash-flow-statements?thscode=…&period=annual&limit=5(单只)"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ModuleHeader(viewModel: viewModel, module: .cashFlowAudit) {
                    DatePicker(text.asOfLabel, selection: $model.asOf, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .help(text.asOfHint)
                        .onChange(of: model.asOf) { _, _ in model.reanalyze() }
                    Button { model.load(force: true) } label: { Image(systemName: "arrow.clockwise") }
                        .help(text.refresh)
                        .disabled(model.isLoading)
                    if model.isLoading { Button(text.cancel) { model.cancel() } }
                }
                .controlSize(.small)
                poolCard
                ModuleStatusBar(model: model)

                if let report = model.report {
                    kpiRow(report)
                    screeningCard(report)
                    HStack(alignment: .top, spacing: 14) {
                        bridgeCard
                        evidenceCard
                    }
                    fieldAuditCard(report)
                    ReportBar(report: report.promptText)
                    ProvenanceCard(
                        dataTime: "\(text.periodsLoaded) \(report.latestPeriodLabels.joined(separator: " / ")) · \(text.asOfLabel) \(ShanghaiDate.dayFormatter.string(from: report.asOf)) · " + String(format: text.generatedAtFormat, ShanghaiDate.dayFormatter.string(from: report.generatedAt)),
                        endpoints: Self.endpoints,
                        methodology: text.cashFlowMethod
                    )
                }
                Spacer(minLength: 20)
            }
            .padding(24)
            .frame(maxWidth: 1240, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            if poolText.isEmpty { poolText = model.pool.joined(separator: ", ") }
            if model.report == nil && !model.isLoading { model.load() }
        }
    }

    // MARK: 观察池

    private var poolCard: some View {
        SectionCard(title: "\(text.watchPool) · \(model.pool.count)/\(AppSettings.cashFlowPoolLimit)", subtitle: text.watchPoolHint) {
            HStack(spacing: 8) {
                TextField(text.aShareSymbolHint, text: $poolText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                    .onSubmit(applyPool)
                Button(text.applyPool, action: applyPool)
                    .disabled(model.isLoading)
                Button(text.loadPool) { model.load() }
                    .disabled(model.isLoading)
            }
            .controlSize(.small)
        }
    }

    private func applyPool() {
        viewModel.setCashFlowPool(text: poolText)
        poolText = model.pool.joined(separator: ", ")
        model.load()
    }

    // MARK: 概览

    private func kpiRow(_ report: CashFlowAuditReport) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            KPITile(label: text.watchPool, value: "\(report.loaded.count) / \(report.companies.count)", caption: report.failed.isEmpty ? nil : "\(text.fetchFailed) \(report.failed.count)")
            KPITile(label: text.periodsLoaded, value: "\(report.totalPeriods)", caption: report.latestPeriodLabels.joined(separator: " / "))
            KPITile(label: text.completeness, value: RiskReport.percent(report.overallCompleteness), color: report.overallCompleteness >= 0.95 ? Theme.success : Theme.accentStrong, caption: text.fieldAuditHint)
            KPITile(label: text.asOfLabel, value: ShanghaiDate.dayFormatter.string(from: report.asOf), caption: text.asOfHint)
        }
    }

    // MARK: 筛查表

    private func screeningCard(_ report: CashFlowAuditReport) -> some View {
        SectionCard(title: text.screeningTable) {
            Picker(text.sortBy, selection: $model.sortKey) {
                ForEach(CashFlowAuditSortKey.allCases) { key in
                    Text(text.sortKeyName(key)).tag(key)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 4) {
                    ScreeningHeader()
                    ForEach(report.sorted(by: model.sortKey)) { company in
                        ScreeningRow(company: company, isSelected: model.selectedCompany?.thscode == company.thscode) {
                            model.selectedCode = company.thscode
                        }
                    }
                }
            }
        }
    }

    // MARK: 桥与证据

    private var bridgeCard: some View {
        let company = model.selectedCompany
        let period = company?.latest
        let title = company.map { "\(text.profitCashBridge) · \($0.name) \(period?.label ?? "")" } ?? text.profitCashBridge
        let subtitle = [period.flatMap { RatioFormat.day($0.reportDateMs) }.map { "\(text.reportDate) \($0)" }, "\(text.bridgeAccrualsShort) = \(text.bridgeAccruals) · \(text.bridgeCapexShort) = \(text.bridgeCapex)"].compactMap { $0 }.joined(separator: " · ")
        return SectionCard(title: title, subtitle: subtitle) {
            if let period {
                WaterfallChart(steps: [
                    .init(label: text.bridgeNetProfit, amount: period.netProfit, kind: .total),
                    .init(label: text.bridgeAccrualsShort, amount: period.accruals.map { -$0 }, kind: .delta),
                    .init(label: text.bridgeOCF, amount: period.ocf, kind: .total),
                    .init(label: text.bridgeCapexShort, amount: period.capex.map { -$0 }, kind: .delta),
                    .init(label: text.bridgeFCF, amount: period.fcf, kind: .total)
                ], height: 220)
                HStack(spacing: 10) {
                    KPITile(label: text.cashConversion, value: RatioFormat.times(period.metrics.cashConversion) ?? "—")
                    KPITile(label: text.fcfMargin, value: RatioFormat.percent(period.metrics.fcfMargin) ?? "—")
                    KPITile(label: text.accrualRatio, value: RatioFormat.percent(period.metrics.accrualRatio) ?? "—")
                }
            } else {
                Text(text.noData).font(.caption).foregroundStyle(Theme.muted)
            }
        }
    }

    private var evidenceCard: some View {
        let company = model.selectedCompany
        return SectionCard(title: company.map { "\(text.cashEvidence) · \($0.name)" } ?? text.cashEvidence, subtitle: text.cashEvidenceHint) {
            if let company, !company.periods.isEmpty {
                PeriodBarChart(
                    series: [.init(name: text.bridgeNetProfit, color: Theme.accent), .init(name: text.bridgeOCF, color: Theme.up), .init(name: text.bridgeFCF, color: Theme.muted)],
                    points: company.periods.map { .init(id: $0.periodEndMs, label: $0.label, values: [$0.netProfit, $0.ocf, $0.fcf]) },
                    hovered: .constant(nil), height: 220
                )
                HStack(spacing: 10) {
                    KPITile(label: text.fiveYearAverage, value: RatioFormat.times(company.averageCashConversion) ?? "—", caption: text.cashConversion)
                    KPITile(label: text.cashCoveredYears, value: "\(company.yearsCashCovered) / \(company.yearsComparable)")
                    KPITile(label: text.netCashRatio, value: RatioFormat.percent(company.latest?.metrics.netCashRatio) ?? "—")
                    KPITile(label: text.receivablePressure, value: RatioFormat.percent(company.latest?.metrics.receivablePressure) ?? "—")
                }
            } else {
                Text(text.noData).font(.caption).foregroundStyle(Theme.muted)
            }
        }
    }

    // MARK: 字段完整度

    private func fieldAuditCard(_ report: CashFlowAuditReport) -> some View {
        SectionCard(title: text.fieldAudit, subtitle: text.fieldAuditHint) {
            HStack(alignment: .top, spacing: 14) {
                HorizontalBars(
                    items: report.fields.map { .init(label: "\($0.field) · \($0.statement)", value: $0.ratio * 100, color: $0.ratio >= 0.999 ? Theme.success : Theme.accentStrong) },
                    valueLabel: { value in
                        let field = report.fields.first { abs($0.ratio * 100 - value) < 1e-9 }
                        return field.map { "\($0.present)/\($0.expected)" } ?? NumberFormat.number(value) + "%"
                    }
                )
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(report.companies) { company in
                        HStack(spacing: 8) {
                            Text(company.name).font(.caption).foregroundStyle(Theme.text).frame(width: 84, alignment: .leading).lineLimit(1)
                            if let error = company.error {
                                Text(error).font(.caption2).foregroundStyle(Theme.danger).lineLimit(1)
                            } else {
                                Text("\(company.periods.count) \(text.periodsLoaded)").font(.caption2).foregroundStyle(Theme.muted)
                                Text(String(format: text.missingFieldsFormat, company.missingFields, company.expectedFields))
                                    .font(.caption2).foregroundStyle(company.missingFields == 0 ? Theme.success : Theme.accentStrong)
                                Text(company.latest.flatMap { RatioFormat.day($0.reportDateMs) } ?? "—").font(.caption2.monospacedDigit()).foregroundStyle(Theme.muted)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(width: 360)
            }
        }
    }
}

// MARK: - 筛查表行

private enum ScreeningColumns {
    static let name: CGFloat = 130
    static let period: CGFloat = 70
    static let metric: CGFloat = 92
}

private struct ScreeningHeader: View {
    @Environment(\.l10n) private var l10n

    var body: some View {
        HStack(spacing: 8) {
            Text(l10n.stock).frame(width: ScreeningColumns.name, alignment: .leading)
            Text(l10n.latestPeriod).frame(width: ScreeningColumns.period, alignment: .leading)
            ForEach([l10n.cashConversion, l10n.fcfMargin, l10n.accrualRatio, l10n.receivablePressure, l10n.netCashRatio, l10n.fiveYearAverage, l10n.cashCoveredYears], id: \.self) { title in
                Text(title).frame(width: ScreeningColumns.metric, alignment: .trailing).lineLimit(1)
            }
            Text(l10n.completeness).frame(width: ScreeningColumns.metric, alignment: .trailing)
        }
        .font(.caption2)
        .foregroundStyle(Theme.muted)
    }
}

private struct ScreeningRow: View {
    let company: CashFlowAuditReport.Company
    let isSelected: Bool
    let onTap: () -> Void
    @Environment(\.l10n) private var l10n

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(company.name).font(.callout).foregroundStyle(isSelected ? Theme.accentStrong : Theme.text).lineLimit(1)
                    Text(company.thscode).font(.caption2.monospacedDigit()).foregroundStyle(Theme.muted)
                }
                .frame(width: ScreeningColumns.name, alignment: .leading)
                if let error = company.error {
                    Text("\(l10n.fetchFailed):\(error)").font(.caption).foregroundStyle(Theme.danger).lineLimit(1)
                } else {
                    let m = company.latest?.metrics
                    Text(company.latest?.label ?? "—").font(.caption.monospacedDigit()).foregroundStyle(Theme.muted).frame(width: ScreeningColumns.period, alignment: .leading)
                    cell(RatioFormat.times(m?.cashConversion), tone: m?.cashConversion.map { $0 >= 1 ? Theme.up : ($0 < 0.5 ? Theme.down : Theme.text) })
                    cell(RatioFormat.percent(m?.fcfMargin), tone: m?.fcfMargin.map(Theme.changeColor))
                    cell(RatioFormat.percent(m?.accrualRatio), tone: m?.accrualRatio.map { $0 > 0 ? Theme.down : Theme.up })
                    cell(RatioFormat.percent(m?.receivablePressure))
                    cell(RatioFormat.percent(m?.netCashRatio), tone: m?.netCashRatio.map(Theme.changeColor))
                    cell(RatioFormat.times(company.averageCashConversion))
                    cell("\(company.yearsCashCovered) / \(company.yearsComparable)")
                    cell(String(format: l10n.missingFieldsFormat, company.missingFields, company.expectedFields), tone: company.missingFields == 0 ? Theme.muted : Theme.accentStrong)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func cell(_ value: String?, tone: Color? = nil) -> some View {
        ValueText(text: value, color: tone ?? Theme.text)
            .font(.caption)
            .frame(width: ScreeningColumns.metric, alignment: .trailing)
    }
}
