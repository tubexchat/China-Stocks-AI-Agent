import SwiftUI

/// 模块 4:本地全市场趋势研究。
struct MarketTrendView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var model: MarketTrendModel

    private var text: L10nStrings { viewModel.text }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ModuleHeader(viewModel: viewModel, module: .marketTrend) {
                    Picker("", selection: Binding(get: { model.sectorTag }, set: { viewModel.setSectorTag($0) })) {
                        Text(text.sectorIndustry).tag("industry")
                        Text(text.sectorConcept).tag("cn_concept")
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .onChange(of: model.sectorTag) { _, _ in model.loadFromCache() }
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
                    regimeRow(report)
                    indicesCard(report)
                    if let breadth = report.breadth { breadthCards(breadth, history: report.breadthHistory) }
                    HStack(alignment: .top, spacing: 14) {
                        sectorList(text.strongestSectors, report.strongest.prefix(15).map { $0 })
                        sectorList(text.weakestSectors, report.weakest.prefix(15).map { $0 })
                    }
                    rotationCard(report)
                    ReportBar(report: report.promptText)
                } else if !model.isLoading {
                    Text(text.cacheEmptyHint).font(.callout).foregroundStyle(Theme.muted)
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: 8))
                }

                stockResearchCard
                dumpCard
                Spacer(minLength: 20)
            }
            .padding(24)
            .frame(maxWidth: 1200, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear { if model.report == nil { model.loadFromCache() } }
    }

    private func regimeRow(_ report: MarketTrendReport) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
            KPITile(label: text.marketRegime, value: report.regime, color: Theme.accentStrong, caption: String(format: text.updatedAtFormat, ShanghaiDate.dayFormatter.string(from: report.generatedAt)))
            KPITile(label: text.bullishAlignment, value: "\(report.bullishCount) / \(report.sectors.count)", color: Theme.up)
            KPITile(label: text.bearishAlignment, value: "\(report.bearishCount) / \(report.sectors.count)", color: Theme.down)
            if let breadth = report.breadth {
                KPITile(label: "\(text.breadthUp) / \(text.breadthDown)", value: "\(breadth.up) / \(breadth.down)", color: breadth.up >= breadth.down ? Theme.up : Theme.down, caption: breadth.date)
            }
        }
    }

    private func indicesCard(_ report: MarketTrendReport) -> some View {
        SectionCard(title: text.indicesHeader) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                ForEach(report.indices) { index in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(index.name).font(.callout.weight(.medium)).foregroundStyle(Theme.text)
                            Spacer()
                            Text(NumberFormat.number(index.metrics.last)).font(.callout.monospacedDigit()).foregroundStyle(Theme.text)
                        }
                        SparkLine(values: index.closes.suffix(60).map { $0 }, color: Theme.changeColor(index.metrics.ret20)).frame(height: 34)
                        HStack(spacing: 8) {
                            Text(text.ret20).font(.caption2).foregroundStyle(Theme.muted)
                            ChangeText(value: index.metrics.ret20 * 100).font(.caption)
                            Text(text.ret60).font(.caption2).foregroundStyle(Theme.muted)
                            ChangeText(value: index.metrics.ret60 * 100).font(.caption)
                            Spacer()
                            Text(text.alignment(index.metrics)).font(.caption2).foregroundStyle(index.metrics.bullishAlignment ? Theme.up : (index.metrics.bearishAlignment ? Theme.down : Theme.muted))
                        }
                    }
                    .padding(10)
                    .background(Theme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func breadthCards(_ breadth: MarketBreadth, history: [MarketBreadth]) -> some View {
        VStack(spacing: 14) {
            SectionCard(title: "\(text.breadthHeader) · \(breadth.date)") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                    KPITile(label: text.breadthUp, value: "\(breadth.up)", color: Theme.up, caption: "≥9.5%: \(breadth.limitUpLike)")
                    KPITile(label: text.breadthDown, value: "\(breadth.down)", color: Theme.down, caption: "≤-9.5%: \(breadth.limitDownLike)")
                    KPITile(label: text.breadthFlat, value: "\(breadth.flat)")
                    KPITile(label: text.breadthMedian, value: NumberFormat.percent(breadth.medianChange), color: Theme.changeColor(breadth.medianChange))
                    KPITile(label: text.breadthTurnover, value: MoneyFormat.yuan(breadth.totalTurnover))
                    KPITile(label: text.breadthConcentration, value: RiskReport.percent(breadth.top100TurnoverShare))
                }
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(text.breadthDistribution).font(.caption).foregroundStyle(Theme.muted)
                        VerticalBars(items: breadth.buckets.map { bucket in
                            .init(label: bucket.label, value: Double(bucket.count), color: bucket.label.hasPrefix("-") || bucket.label.hasPrefix("≤") ? Theme.down : (bucket.label == "0" ? Theme.muted : Theme.up))
                        }, height: 150)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(text.boardsHeader).font(.caption).foregroundStyle(Theme.muted)
                        ForEach(breadth.boards) { board in
                            HStack(spacing: 8) {
                                Text(board.board).font(.callout).foregroundStyle(Theme.text).frame(width: 56, alignment: .leading)
                                Text("\(board.up)").font(.callout.monospacedDigit()).foregroundStyle(Theme.up).frame(width: 44, alignment: .trailing)
                                Text("\(board.down)").font(.callout.monospacedDigit()).foregroundStyle(Theme.down).frame(width: 44, alignment: .trailing)
                                ChangeText(value: board.medianChange).font(.callout).frame(width: 64, alignment: .trailing)
                                Text(MoneyFormat.yuan(board.turnover)).font(.caption.monospacedDigit()).foregroundStyle(Theme.muted)
                                Spacer()
                            }
                        }
                        if history.count >= 2 {
                            Text(text.breadthHistory).font(.caption).foregroundStyle(Theme.muted).padding(.top, 6)
                            LineSeries(points: history.suffix(60).map { .init(x: $0.date, y: $0.upRatio * 100) }, color: Theme.accent, height: 80, yLabel: { NumberFormat.number($0) + "%" })
                        }
                    }
                    .frame(width: 360)
                }
            }
            HStack(alignment: .top, spacing: 14) {
                snapshotList(text.topGainers, breadth.topGainers)
                snapshotList(text.topLosers, breadth.topLosers)
                snapshotList(text.topTurnover, breadth.topTurnover)
            }
        }
    }

    private func snapshotList(_ title: String, _ items: [PriceSnapshotItem]) -> some View {
        SectionCard(title: title) {
            ForEach(items) { item in
                HStack(spacing: 8) {
                    Text(item.thscode).font(.caption.monospacedDigit()).foregroundStyle(Theme.text)
                    Spacer()
                    ChangeText(value: item.price_change_ratio_pct).font(.caption)
                    Text(MoneyFormat.yuan(item.turnover ?? 0)).font(.caption.monospacedDigit()).foregroundStyle(Theme.muted).frame(width: 56, alignment: .trailing)
                }
            }
        }
    }

    private func sectorList(_ title: String, _ sectors: [SectorTrend]) -> some View {
        SectionCard(title: title) {
            ForEach(sectors) { sector in
                HStack(spacing: 8) {
                    Text(sector.name).font(.callout).foregroundStyle(Theme.text).frame(width: 110, alignment: .leading).lineLimit(1)
                    Chip(text: "\(sector.score)", color: (sector.score >= 60 ? Theme.up : (sector.score < 40 ? Theme.down : Theme.muted)).opacity(0.15), foreground: sector.score >= 60 ? Theme.up : (sector.score < 40 ? Theme.down : Theme.text))
                    SparkLine(values: sector.closes.suffix(60).map { $0 }, color: Theme.changeColor(sector.metrics.ret20)).frame(width: 70, height: 20)
                    ChangeText(value: sector.metrics.ret20 * 100).font(.caption).frame(width: 60, alignment: .trailing)
                    ChangeText(value: sector.metrics.ret60 * 100).font(.caption).frame(width: 60, alignment: .trailing)
                    Text(text.alignment(sector.metrics)).font(.caption2).foregroundStyle(sector.metrics.bullishAlignment ? Theme.up : (sector.metrics.bearishAlignment ? Theme.down : Theme.muted))
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func rotationCard(_ report: MarketTrendReport) -> some View {
        SectionCard(title: text.rotationHeatmap) {
            let sectors = Array(report.strongest.prefix(12)) + Array(report.weakest.prefix(8).reversed())
            let dates = report.recentDates
            VStack(spacing: 3) {
                HStack(spacing: 3) {
                    Text("").frame(width: 100)
                    ForEach(dates, id: \.self) { date in
                        Text(String(date.suffix(5))).font(.system(size: 9)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
                    }
                }
                ForEach(sectors) { sector in
                    HStack(spacing: 3) {
                        Text(sector.name).font(.caption).foregroundStyle(Theme.text).frame(width: 100, alignment: .leading).lineLimit(1)
                        ForEach(Array(sector.recentReturns.suffix(dates.count).enumerated()), id: \.offset) { _, value in
                            HeatCell(value: value, scale: 0.04, text: NumberFormat.percent(value * 100))
                                .frame(height: 20)
                        }
                    }
                }
            }
        }
    }

    private var stockResearchCard: some View {
        SectionCard(title: text.stockResearch, subtitle: text.stockResearchHint) {
            HStack(spacing: 8) {
                TextField(text.aShareSymbolHint, text: $model.stockSymbol)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .onSubmit { model.researchStock() }
                Button(text.research) { model.researchStock() }
                    .disabled(model.isLoadingStock || model.stockSymbol.trimmingCharacters(in: .whitespaces).isEmpty)
                if model.isLoadingStock { ProgressView().controlSize(.small) }
                if let name = model.stockName { Text(name).font(.callout).foregroundStyle(Theme.muted) }
                Spacer()
            }
            if let error = model.stockError {
                Text(error).font(.callout).foregroundStyle(Theme.danger)
            }
            if let metrics = model.stockMetrics {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                    KPITile(label: text.price, value: NumberFormat.number(metrics.last))
                    KPITile(label: text.trendScore, value: "\(metrics.score)", color: metrics.score >= 60 ? Theme.up : (metrics.score < 40 ? Theme.down : Theme.text))
                    KPITile(label: text.ret20, value: RiskReport.percent(metrics.ret20), color: Theme.changeColor(metrics.ret20))
                    KPITile(label: text.ret60, value: RiskReport.percent(metrics.ret60), color: Theme.changeColor(metrics.ret60))
                    KPITile(label: text.maAlignment, value: text.alignment(metrics), color: metrics.bullishAlignment ? Theme.up : (metrics.bearishAlignment ? Theme.down : Theme.text))
                    KPITile(label: text.annualVol, value: RiskReport.percent(metrics.annualVol))
                    KPITile(label: text.maxDrawdown, value: RiskReport.percent(metrics.maxDrawdown60))
                    if let risk = model.stockRisk {
                        KPITile(label: text.var95, value: RiskReport.percent(risk.var95))
                        KPITile(label: text.sharpe, value: NumberFormat.number(risk.sharpe))
                    }
                    if let backtest = model.stockBacktest {
                        KPITile(label: "\(text.backtestName) MA5/20", value: RiskReport.percent(backtest.strategyReturn), color: Theme.changeColor(backtest.strategyReturn), caption: "\(text.holdReturn) \(RiskReport.percent(backtest.holdReturn))")
                        KPITile(label: text.winRate, value: RiskReport.percent(backtest.winRate), caption: "\(text.tradeCount) \(backtest.trades)")
                    }
                    if let forecast = model.stockForecast {
                        KPITile(label: text.nextDayDirection, value: text.direction(forecast.direction), color: forecast.direction == "看涨" ? Theme.up : Theme.down, caption: "\(text.hitRate) \(RiskReport.percent(forecast.validationHitRate))")
                    }
                }
                LineSeries(points: model.stockBars.suffix(120).map { .init(x: ShanghaiDate.string($0.date), y: $0.close) }, color: Theme.changeColor(metrics.ret20), height: 140)
                if let factors = model.stockFactors {
                    HStack(spacing: 6) {
                        Text(text.factorToolName).font(.caption).foregroundStyle(Theme.muted)
                        ForEach(factors.rankings.prefix(5), id: \.name) { ranking in
                            Chip(text: "\(ranking.name) IC \(NumberFormat.number(ranking.ic))")
                        }
                    }
                }
                ReportBar(report: model.stockPromptText)
            }
        }
    }

    private var dumpCard: some View {
        SectionCard(title: text.dumpHeader, subtitle: text.dumpHint) {
            HStack(spacing: 8) {
                Button(text.dump10y) { model.downloadDump(kind: .dailyK) }
                Button(text.dump10d) { model.downloadDump(kind: .dailyK10d) }
                Button(text.dumpFactors) { model.downloadDump(kind: .adjustmentFactors) }
                if let status = model.dumpStatus {
                    Text(status).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer()
            }
            .controlSize(.small)
        }
    }
}
