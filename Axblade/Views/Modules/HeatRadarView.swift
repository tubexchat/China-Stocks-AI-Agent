import SwiftUI

/// 模块 3:市场热度与飙升雷达。
struct HeatRadarView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var model: HeatRadarModel

    private var text: L10nStrings { viewModel.text }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ModuleHeader(viewModel: viewModel, module: .heatRadar) {
                    Picker("", selection: $model.period) {
                        Text(text.periodDay).tag(HotListPeriod.day)
                        Text(text.periodHour).tag(HotListPeriod.hour)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .onChange(of: model.period) { _, _ in model.load() }
                    Button { model.load() } label: { Image(systemName: "arrow.clockwise") }
                        .controlSize(.small)
                        .help(text.refresh)
                }
                ModuleStatusBar(model: model)

                if let report = model.report {
                    HStack(alignment: .top, spacing: 14) {
                        SectionCard(title: text.heatRadarName, subtitle: text.radarHint) {
                            RadarCanvas(points: report.points, selected: model.selectedCode) { model.select($0) }
                                .frame(height: 440)
                        }
                        .frame(maxWidth: .infinity)
                        VStack(spacing: 14) {
                            resonanceCard(report)
                            climbersCard(report)
                            trendCard
                        }
                        .frame(width: 320)
                    }
                    HStack(alignment: .top, spacing: 14) {
                        listCard(text.hotList, report.points.filter { $0.hotRank != nil }.sorted { ($0.hotRank ?? 0) < ($1.hotRank ?? 0) }, rank: { $0.hotRank })
                        listCard(text.surgeList, report.points.filter { $0.surgeRank != nil }.sorted { ($0.surgeRank ?? 0) < ($1.surgeRank ?? 0) }, rank: { $0.surgeRank })
                    }
                    HStack(alignment: .top, spacing: 14) {
                        SectionCard(title: text.anomalyTags) {
                            VerticalBars(items: report.tags.map { .init(label: $0.tag, value: Double($0.count), color: $0.tag.contains("涨") ? Theme.up : ($0.tag.contains("跌") ? Theme.down : Theme.accent)) }, height: 120)
                        }
                        SectionCard(title: text.anomalyKeywords) {
                            HorizontalBars(items: report.keywords.prefix(14).map { .init(label: $0.keyword, value: Double($0.count)) })
                        }
                    }
                    anomaliesCard(report)
                    ReportBar(report: report.promptText)
                }
                Spacer(minLength: 20)
            }
            .padding(24)
            .frame(maxWidth: 1200, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear { if model.report == nil && !model.isLoading { model.load() } }
    }

    private func resonanceCard(_ report: HeatRadarReport) -> some View {
        SectionCard(title: text.resonance, subtitle: text.resonanceHint) {
            if report.resonance.isEmpty {
                Text(text.noData).font(.caption).foregroundStyle(Theme.muted)
            }
            ForEach(report.resonance.prefix(8)) { point in
                row(point, rank: point.hotRank)
            }
        }
    }

    private func climbersCard(_ report: HeatRadarReport) -> some View {
        SectionCard(title: text.climbers) {
            ForEach(report.climbers.prefix(8)) { point in
                row(point, rank: point.hotRank ?? point.surgeRank)
            }
        }
    }

    private var trendCard: some View {
        SectionCard(title: text.rankTrend, subtitle: model.selectedCode.flatMap { code in model.report?.points.first { $0.id == code }?.name }) {
            if model.isLoadingTrend {
                ProgressView().controlSize(.small)
            } else if model.rankTrend.isEmpty {
                Text(text.noData).font(.caption).foregroundStyle(Theme.muted)
            } else {
                LineSeries(points: model.rankTrend.map { .init(x: $0.date, y: Double($0.rank)) }, color: Theme.accent, height: 110, yLabel: { "#\(Int($0))" }, reversed: true)
            }
        }
    }

    private func row(_ point: HeatRadarReport.RadarPoint, rank: Int?) -> some View {
        Button { model.select(model.selectedCode == point.id ? nil : point.id) } label: {
            HStack(spacing: 8) {
                Text(rank.map { "#\($0)" } ?? "").font(.caption.monospacedDigit()).foregroundStyle(Theme.muted).frame(width: 30, alignment: .leading)
                Text(point.name).font(.callout).foregroundStyle(model.selectedCode == point.id ? Theme.accentStrong : Theme.text)
                if let change = point.rankChange, change != 0 {
                    Text(change > 0 ? "↑\(change)" : "↓\(-change)").font(.caption.monospacedDigit()).foregroundStyle(change > 0 ? Theme.up : Theme.down)
                }
                if let tag = point.anomalyTag { Chip(text: tag) }
                Spacer()
                Text(NumberFormat.number(point.heat)).font(.caption.monospacedDigit()).foregroundStyle(Theme.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func listCard(_ title: String, _ points: [HeatRadarReport.RadarPoint], rank: @escaping (HeatRadarReport.RadarPoint) -> Int?) -> some View {
        SectionCard(title: title) {
            CollapsibleList(items: points, limit: 15) { point in
                row(point, rank: rank(point))
            }
        }
    }

    private func anomaliesCard(_ report: HeatRadarReport) -> some View {
        SectionCard(title: "\(text.anomalyReasons) · \(report.anomalies.count)") {
            CollapsibleList(items: report.anomalies, limit: 8) { item in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.stock_name).font(.callout.weight(.medium)).foregroundStyle(Theme.text)
                        Chip(text: item.tag_name, color: item.tag_name.contains("涨") ? Theme.up.opacity(0.15) : (item.tag_name.contains("跌") ? Theme.down.opacity(0.15) : Theme.accentSoft), foreground: item.tag_name.contains("涨") ? Theme.up : (item.tag_name.contains("跌") ? Theme.down : Theme.text))
                        ForEach(item.keyword_list.prefix(4), id: \.self) { Chip(text: $0, color: Theme.surface2, foreground: Theme.muted) }
                    }
                    Text(item.analysis_content.split(separator: "\n").first.map(String.init) ?? item.analysis_content)
                        .font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
                }
                .padding(.vertical, 2)
            }
        }
    }
}
