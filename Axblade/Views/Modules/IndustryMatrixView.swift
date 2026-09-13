import SwiftUI

/// 模块 6:行业强度作战矩阵。
struct IndustryMatrixView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var model: IndustryMatrixModel

    private var text: L10nStrings { viewModel.text }

    static let endpoints = [
        "GET /api/a-share-index/catalog/ths-index-list?tag=industry",
        "GET /api/a-share-index/prices/historical?thscode=…&interval=1d&start=…&end=…(基准 000300.SH 同源)",
        "GET /api/a-share-index/constituents/ths-stock-list?thscode=…(选中行业时)",
        "GET /api/a-share/prices/snapshot?thscodes=…(成分快照)· GET /api/a-share-index/prices/snapshot?thscodes=…(指数快照)"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ModuleHeader(viewModel: viewModel, module: .industryMatrix) {
                    Button(text.refreshIncremental) { model.refresh() }
                        .disabled(model.isLoading)
                    Button(text.rebuildAll) { model.refresh(fullRebuild: true) }
                        .disabled(model.isLoading)
                    if model.isLoading {
                        Button(text.cancel) { model.cancel() }
                    }
                }
                .controlSize(.small)
                ModuleStatusBar(model: model)

                if let report = model.report {
                    kpiRow(report)
                    HStack(alignment: .top, spacing: 14) {
                        SectionCard(title: text.industryMatrixName, subtitle: text.matrixHint) {
                            BubbleChart(items: bubbles(report), selected: model.selectedCode, xLabel: text.rs20, yLabel: text.rs60) { model.select($0) }
                        }
                        .frame(maxWidth: .infinity)
                        VStack(spacing: 14) {
                            industryList(text.strongestIndustries, Array(report.strongest.prefix(12)))
                            industryList(text.rankClimbers, Array(report.climbers.prefix(8)))
                        }
                        .frame(width: 400)
                    }
                    heatBandCard(report)
                    HStack(alignment: .top, spacing: 14) {
                        industryList(text.weakestIndustries, Array(report.weakest.prefix(10)))
                        industryList(text.rankFallers, Array(report.fallers.prefix(10)))
                    }
                    evidenceCard
                    ReportBar(report: report.promptText)
                    ProvenanceCard(
                        dataTime: "\(report.dataDate) · " + String(format: text.generatedAtFormat, ShanghaiDate.dayFormatter.string(from: report.generatedAt)),
                        endpoints: Self.endpoints,
                        methodology: text.industryMatrixMethod
                    )
                } else if !model.isLoading {
                    Text(text.industryCacheEmptyHint).font(.callout).foregroundStyle(Theme.muted)
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Spacer(minLength: 20)
            }
            .padding(24)
            .frame(maxWidth: 1240, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear { if model.report == nil { model.loadFromCache() } }
    }

    // MARK: 顶部

    private func kpiRow(_ report: IndustryStrengthReport) -> some View {
        let b = report.breadth
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            KPITile(label: text.benchmarkLabel, value: report.benchmarkName ?? "—", color: Theme.accentStrong,
                    caption: "\(text.ret20) \(RatioFormat.percent(report.benchmarkRet20) ?? "—") · \(text.ret60) \(RatioFormat.percent(report.benchmarkRet60) ?? "—")")
            KPITile(label: text.breadthPositive20, value: "\(b.positive20) / \(b.total)", color: Theme.changeColor(b.ratio(b.positive20) - 0.5), caption: RiskReport.percent(b.ratio(b.positive20)))
            KPITile(label: text.breadthOutperform, value: "\(b.outperform20) / \(b.total)", caption: RiskReport.percent(b.ratio(b.outperform20)))
            KPITile(label: text.breadthAboveMA20, value: "\(b.aboveMA20) / \(b.total)", caption: RiskReport.percent(b.ratio(b.aboveMA20)))
            KPITile(label: text.breadthPulse, value: "\(b.pulseAbove1) / \(b.total)", caption: text.turnoverPulseHint)
            KPITile(label: text.dataTime, value: report.dataDate, caption: model.lastUpdated.map { String(format: text.updatedAtFormat, ShanghaiDate.dayFormatter.string(from: $0)) })
        }
    }

    private func bubbles(_ report: IndustryStrengthReport) -> [BubbleChart.Item] {
        report.rows.compactMap { row in
            guard let rs20 = row.rs20, let rs60 = row.rs60 else { return nil }
            let detail = [
                "\(text.rs5) \(RatioFormat.percent(row.rs5) ?? "—")",
                "\(text.rs20) \(RiskReport.percent(rs20))",
                "\(text.rs60) \(RiskReport.percent(rs60))",
                "\(text.turnoverPulse) \(RatioFormat.number(row.turnoverPulse) ?? "—")",
                "\(text.strengthScore) \(row.score) · \(text.rankNow) #\(row.rank)"
            ].joined(separator: "\n")
            return .init(id: row.thscode, label: row.name, x: rs20 * 100, y: rs60 * 100, size: row.turnoverPulse ?? 1,
                         color: (row.rs5 ?? 0) >= 0 ? Theme.up : Theme.down, detail: detail)
        }
    }

    // MARK: 列表

    private func industryList(_ title: String, _ rows: [IndustryStrengthReport.Row]) -> some View {
        SectionCard(title: title) {
            if rows.isEmpty { Text(text.noData).font(.caption).foregroundStyle(Theme.muted) }
            ForEach(rows) { row in
                IndustryRowView(row: row, isSelected: model.selectedCode == row.thscode) {
                    model.select(model.selectedCode == row.thscode ? nil : row.thscode)
                }
            }
        }
    }

    // MARK: 热力带

    private func heatBandCard(_ report: IndustryStrengthReport) -> some View {
        SectionCard(title: text.heatBand, subtitle: text.heatBandHint) {
            var seen = Set<String>()
            let rows = (Array(report.strongest.prefix(12)) + Array(report.weakest.prefix(8).reversed())).filter { seen.insert($0.thscode).inserted }
            let dates = report.recentDates
            VStack(spacing: 3) {
                HStack(spacing: 3) {
                    Text("").frame(width: 110)
                    ForEach(dates, id: \.self) { date in
                        Text(String(date.suffix(5))).font(.system(size: 8)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
                    }
                }
                ForEach(rows) { row in
                    HStack(spacing: 3) {
                        Text(row.name).font(.caption).foregroundStyle(model.selectedCode == row.thscode ? Theme.accentStrong : Theme.text).frame(width: 110, alignment: .leading).lineLimit(1)
                        let values = Array(row.recentReturns.suffix(dates.count))
                        ForEach(0..<dates.count, id: \.self) { index in
                            let offset = index - (dates.count - values.count)
                            if offset >= 0 {
                                HeatCell(value: values[offset], scale: 0.04, text: NumberFormat.percent(values[offset] * 100)).frame(height: 18)
                            } else {
                                RoundedRectangle(cornerRadius: 3).fill(Theme.surface2).frame(height: 18)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: 联动证据

    private var evidenceCard: some View {
        let title = model.evidence.map { "\(text.constituentEvidence) · \($0.name)" } ?? text.constituentEvidence
        return SectionCard(title: title, subtitle: text.constituentHint) {
            if model.isLoadingEvidence {
                ProgressView().controlSize(.small)
            } else if let error = model.evidenceError {
                Text(error).font(.callout).foregroundStyle(Theme.danger)
            } else if let evidence = model.evidence {
                EvidenceBody(evidence: evidence)
            } else {
                Text(text.noData).font(.caption).foregroundStyle(Theme.muted)
            }
        }
    }
}

/// 一行行业:名称 · 强度分 · RS20 · 脉冲 · 名次变化。
private struct IndustryRowView: View {
    let row: IndustryStrengthReport.Row
    let isSelected: Bool
    let onTap: () -> Void
    @Environment(\.l10n) private var l10n

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Text("#\(row.rank)").font(.caption.monospacedDigit()).foregroundStyle(Theme.muted).frame(width: 34, alignment: .leading)
                Text(row.name).font(.callout).foregroundStyle(isSelected ? Theme.accentStrong : Theme.text).frame(width: 96, alignment: .leading).lineLimit(1)
                Chip(text: "\(row.score)", color: Theme.scoreColor(row.score, neutral: Theme.muted).opacity(0.15), foreground: Theme.scoreColor(row.score))
                ChangeText(value: row.rs20.map { $0 * 100 }).font(.caption).frame(width: 60, alignment: .trailing)
                Text(row.turnoverPulse.map { NumberFormat.number($0) + "×" } ?? "—").font(.caption.monospacedDigit()).foregroundStyle(Theme.muted).frame(width: 44, alignment: .trailing)
                if let change = row.rankChange, change != 0 {
                    Text(change > 0 ? "↑\(change)" : "↓\(-change)").font(.caption.monospacedDigit()).foregroundStyle(change > 0 ? Theme.up : Theme.down)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(l10n.rs5) \(RatioFormat.percent(row.rs5) ?? "—") · \(l10n.rs60) \(RatioFormat.percent(row.rs60) ?? "—")")
    }
}

/// 成分股联动证据正文。
private struct EvidenceBody: View {
    let evidence: IndustryConstituentEvidence
    @Environment(\.l10n) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                KPITile(label: l10n.constituentCount, value: "\(evidence.total)", caption: "\(l10n.breadthUp) \(evidence.up) / \(l10n.breadthDown) \(evidence.down) / \(l10n.breadthFlat) \(evidence.flat)")
                KPITile(label: "\(l10n.breadthUp) / \(l10n.breadthDown)", value: "\(evidence.up) / \(evidence.down)", color: evidence.up >= evidence.down ? Theme.up : Theme.down, caption: "≥9.5% \(evidence.limitUpLike) · ≤-9.5% \(evidence.limitDownLike)")
                KPITile(label: l10n.equalWeightProxy, value: RatioFormat.percentPoints(evidence.equalWeightChange), color: Theme.changeColor(evidence.equalWeightChange), caption: l10n.equalWeightCaveat)
                KPITile(label: l10n.indexChange, value: RatioFormat.percentPoints(evidence.indexChange), color: Theme.changeColor(evidence.indexChange), caption: "\(l10n.weightGap) \(RatioFormat.number(evidence.weightGap) ?? "—")")
                KPITile(label: l10n.dispersion, value: RatioFormat.number(evidence.dispersion).map { $0 + " pp" } ?? "—", caption: "\(l10n.breadthMedian) \(RatioFormat.percentPoints(evidence.medianChange))")
                KPITile(label: l10n.turnoverActivity, value: MoneyFormat.yuan(evidence.totalTurnover), caption: "\(l10n.top5Share) \(RatioFormat.percent(evidence.top5TurnoverShare) ?? "—")")
            }
            Text(l10n.equalWeightCaveat).font(.caption).foregroundStyle(Theme.accentStrong)
            HStack(alignment: .top, spacing: 14) {
                memberList(l10n.topGainers, evidence.topGainers)
                memberList(l10n.topLosers, evidence.topLosers)
                memberList(l10n.topTurnover, evidence.topTurnover)
            }
        }
    }

    private func memberList(_ title: String, _ members: [IndustryConstituentEvidence.Member]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Theme.muted)
            ForEach(members) { member in
                HStack(spacing: 8) {
                    Text(member.name).font(.caption).foregroundStyle(Theme.text).lineLimit(1)
                    Spacer()
                    ChangeText(value: member.change).font(.caption)
                    Text(member.turnover.map(MoneyFormat.yuan) ?? "—").font(.caption.monospacedDigit()).foregroundStyle(Theme.muted).frame(width: 56, alignment: .trailing)
                }
            }
            if members.isEmpty { Text(l10n.noData).font(.caption).foregroundStyle(Theme.muted) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension RatioFormat {
    /// 已是百分数的涨跌幅(10.0 = +10%);nil → 「—」。
    static func percentPoints(_ value: Double?) -> String { value.map(NumberFormat.percent) ?? "—" }
}
