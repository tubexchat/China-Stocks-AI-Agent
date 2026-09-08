import SwiftUI

/// 模块 1:涨停情绪市场脉冲。
struct LimitUpPulseView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var model: LimitUpPulseModel

    private var text: L10nStrings { viewModel.text }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ModuleHeader(viewModel: viewModel, module: .limitUpPulse) {
                    DateNavigator(
                        date: model.displayDate,
                        onPrevious: { model.stepDay(-1) },
                        onNext: { model.stepDay(1) },
                        onToday: { model.load(date: ShanghaiDate.string(Date())) }
                    )
                    Button { model.load() } label: { Image(systemName: "arrow.clockwise") }
                        .controlSize(.small)
                        .help(text.refresh)
                }
                ModuleStatusBar(model: model)

                if let report = model.report {
                    scoreRow(report)
                    kpiGrid(report)
                    HStack(alignment: .top, spacing: 14) {
                        SectionCard(title: text.boardDistribution) {
                            VerticalBars(items: report.boardDistribution.keys.sorted().map {
                                .init(label: String(format: text.boardsFormat, $0), value: Double(report.boardDistribution[$0] ?? 0), color: Theme.up.opacity(0.5 + 0.1 * Double(min($0, 5))))
                            }, height: 130)
                        }
                        SectionCard(title: text.timeDistribution) {
                            VerticalBars(items: report.timeBuckets.map { .init(label: $0.label, value: Double($0.count)) }, color: Theme.accent, height: 130)
                        }
                    }
                    ladderCard(report)
                    HStack(alignment: .top, spacing: 14) {
                        themeCard(report)
                        leadersCard(report)
                    }
                    poolsCard
                    ReportBar(report: report.promptText)
                }
                Spacer(minLength: 20)
            }
            .padding(24)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear { if model.report == nil && !model.isLoading { model.load() } }
    }

    private func scoreRow(_ report: LimitUpPulseReport) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Theme.border, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(report.score) / 100)
                    .stroke(scoreColor(report.score), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(report.score)").font(.title.weight(.bold)).monospacedDigit().foregroundStyle(Theme.text)
                    Text(report.regime).font(.caption).foregroundStyle(Theme.muted)
                }
            }
            .frame(width: 96, height: 96)

            VStack(alignment: .leading, spacing: 6) {
                Text(text.sentimentScore).font(.caption).foregroundStyle(Theme.muted)
                HStack(spacing: 14) {
                    stat(text.limitUpCount, "\(report.limitUpCount)", Theme.up)
                    stat(text.limitDownCount, "\(report.limitDownCount)", Theme.down)
                    stat(text.breakCount, "\(report.breakCount)", Theme.muted)
                    stat(text.sealRate, RiskReport.percent(report.sealRate), Theme.text)
                    stat(text.highestBoard, String(format: text.boardsFormat, report.highestBoard), Theme.accentStrong)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(Theme.muted)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(color)
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        score >= 60 ? Theme.up : (score < 40 ? Theme.down : Theme.accent)
    }

    private func kpiGrid(_ report: LimitUpPulseReport) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            KPITile(label: text.firstBoard, value: "\(report.firstBoardCount)")
            KPITile(label: text.consecutive, value: "\(report.consecutiveCount)", color: Theme.up)
            KPITile(label: text.earlySeal, value: RiskReport.percent(report.earlySealRatio))
            KPITile(label: text.sealStrength, value: RiskReport.percent(report.sealStrength))
            KPITile(label: text.totalSeal, value: MoneyFormat.yuan(report.totalSealMoney))
            if let last = report.ladder.last(where: { $0.promotionRate != nil }), let rate = last.promotionRate {
                KPITile(label: text.promotionRate, value: RiskReport.percent(rate), caption: last.date)
            }
        }
    }

    private func ladderCard(_ report: LimitUpPulseReport) -> some View {
        SectionCard(title: text.ladderTrend) {
            let points = report.ladder
            if points.isEmpty {
                Text(text.noData).font(.caption).foregroundStyle(Theme.muted)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(text.ladderHeight).font(.caption).foregroundStyle(Theme.muted)
                        LineSeries(points: points.map { .init(x: $0.date, y: Double($0.highestBoard)) }, color: Theme.up, height: 100, yLabel: { String(format: text.boardsFormat, Int($0)) })
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(text.ladderCount).font(.caption).foregroundStyle(Theme.muted)
                        LineSeries(points: points.map { .init(x: $0.date, y: Double($0.consecutiveCount)) }, color: Theme.accent, height: 100)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(text.promotionRate).font(.caption).foregroundStyle(Theme.muted)
                        LineSeries(points: points.compactMap { p in p.promotionRate.map { .init(x: p.date, y: $0 * 100) } }, color: Theme.accentStrong, height: 100, yLabel: { NumberFormat.number($0) + "%" })
                    }
                }
                if let ladder = model.ladder, let latest = ladder.item.first {
                    ladderMatrix(latest)
                }
            }
        }
    }

    /// 最近一天的板位矩阵。
    private func ladderMatrix(_ day: LadderDay) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(day.boards.tiers, id: \.boards) { tier in
                VStack(alignment: .leading, spacing: 3) {
                    Text(tier.boards >= 7 ? "7板+" : String(format: text.boardsFormat, tier.boards))
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                    ForEach(tier.stocks) { stock in
                        HStack(spacing: 3) {
                            Text(stock.name).font(.caption).foregroundStyle(Theme.text).lineLimit(1)
                            if let sealed = stock.seal_nextday {
                                Image(systemName: sealed ? "arrow.up.circle.fill" : "xmark.circle")
                                    .font(.system(size: 9))
                                    .foregroundStyle(sealed ? Theme.up : Theme.down)
                            }
                        }
                    }
                    if tier.stocks.isEmpty { Text("—").font(.caption).foregroundStyle(Theme.disabled) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 6)
    }

    private func themeCard(_ report: LimitUpPulseReport) -> some View {
        SectionCard(title: text.themeClusters) {
            CollapsibleList(items: report.themes, limit: 10) { theme in
                HStack(alignment: .top, spacing: 8) {
                    Text(theme.name).font(.callout.weight(.medium)).foregroundStyle(Theme.text).frame(width: 120, alignment: .leading).lineLimit(1)
                    Chip(text: "\(theme.count)", color: Theme.up.opacity(0.15), foreground: Theme.up)
                    Chip(text: String(format: text.boardsFormat, theme.maxBoards))
                    Text(theme.stocks.prefix(6).map(\.name).joined(separator: " ")).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func leadersCard(_ report: LimitUpPulseReport) -> some View {
        SectionCard(title: text.leaders) {
            CollapsibleList(items: report.leaders, limit: 10) { item in
                HStack(spacing: 8) {
                    Text(item.name).font(.callout).foregroundStyle(Theme.text).frame(width: 80, alignment: .leading).lineLimit(1)
                    Chip(text: item.continue_day_text ?? String(format: text.boardsFormat, item.boards), color: Theme.up.opacity(0.15), foreground: Theme.up)
                    Text(item.limit_up_time ?? "").font(.caption.monospacedDigit()).foregroundStyle(Theme.muted)
                    Text(MoneyFormat.yuan(item.seal_money ?? 0)).font(.caption.monospacedDigit()).foregroundStyle(Theme.muted)
                    Text(item.limit_up_reason ?? "").font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var poolsCard: some View {
        HStack(alignment: .top, spacing: 14) {
            SectionCard(title: "\(text.limitUpPool) · \(model.limitUp.count)") {
                CollapsibleList(items: model.limitUp, limit: 12) { item in
                    HStack(spacing: 8) {
                        Text(item.name).font(.callout).foregroundStyle(Theme.text).frame(width: 84, alignment: .leading).lineLimit(1)
                        Text(item.continue_day_text ?? "").font(.caption).foregroundStyle(Theme.up).frame(width: 44, alignment: .leading)
                        Text(item.limit_up_time ?? "").font(.caption.monospacedDigit()).foregroundStyle(Theme.muted)
                        Text(MoneyFormat.yuan(item.seal_money ?? 0)).font(.caption.monospacedDigit()).foregroundStyle(Theme.muted).frame(width: 60, alignment: .trailing)
                        Text(item.limit_up_reason ?? "").font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
            VStack(spacing: 14) {
                SectionCard(title: "\(text.limitBreakPool) · \(model.limitBreak.count)") {
                    CollapsibleList(items: model.limitBreak, limit: 8) { item in
                        HStack(spacing: 8) {
                            Text(item.name).font(.callout).foregroundStyle(Theme.text).frame(width: 84, alignment: .leading).lineLimit(1)
                            ChangeText(value: item.price_change_ratio_pct).font(.caption)
                            Text("\(text.openTimes) \(item.open_times ?? 0)").font(.caption).foregroundStyle(Theme.muted)
                            Spacer(minLength: 0)
                        }
                    }
                }
                SectionCard(title: "\(text.limitDownPool) · \(model.limitDown.count)") {
                    CollapsibleList(items: model.limitDown, limit: 8) { item in
                        HStack(spacing: 8) {
                            Text(item.name).font(.callout).foregroundStyle(Theme.text).frame(width: 84, alignment: .leading).lineLimit(1)
                            ChangeText(value: item.price_change_ratio_pct).font(.caption)
                            Text(item.last_limit_time ?? "").font(.caption.monospacedDigit()).foregroundStyle(Theme.muted)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }
}
