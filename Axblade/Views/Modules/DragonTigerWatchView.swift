import SwiftUI

/// 模块 5:龙虎榜机构与游资观察(多日聚合)。
struct DragonTigerWatchView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var model: DragonTigerWatchModel

    private var text: L10nStrings { viewModel.text }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ModuleHeader(viewModel: viewModel, module: .dragonTigerWatch) {
                    Picker(text.watchWindow, selection: Binding(get: { model.days }, set: { viewModel.setWatchDays($0) })) {
                        ForEach([1, 3, 5, 10], id: \.self) { days in
                            Text(String(format: text.watchDaysFormat, days)).tag(days)
                        }
                    }
                    .fixedSize()
                    .onChange(of: model.days) { _, _ in model.load() }
                    Button { model.load() } label: { Image(systemName: "arrow.clockwise") }
                        .help(text.refresh)
                }
                .controlSize(.small)
                ModuleStatusBar(model: model)

                if let report = model.report {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                        KPITile(label: text.orgNetTotal, value: MoneyFormat.yuan(report.orgNetTotal), color: Theme.changeColor(report.orgNetTotal), caption: report.dates.isEmpty ? nil : "\(report.dates.first!) ~ \(report.dates.last!)")
                        KPITile(label: text.hotMoneyNetTotal, value: MoneyFormat.yuan(report.hotMoneyNetTotal), color: Theme.changeColor(report.hotMoneyNetTotal))
                        KPITile(label: text.activePlayers, value: "\(report.players.count)")
                        KPITile(label: text.repeatedStocks, value: "\(report.repeated.count)")
                    }
                    HStack(alignment: .top, spacing: 14) {
                        stockList(text.orgBuys, report.orgBuys, value: { $0.orgNetTotal }, showOrg: true)
                        stockList(text.orgSells, report.orgSells, value: { $0.orgNetTotal }, showOrg: true)
                    }
                    HStack(alignment: .top, spacing: 14) {
                        playersCard(report)
                        if let selected = model.selectedPlayer, let player = report.players.first(where: { $0.name == selected }) {
                            playerDetail(player, report)
                        } else {
                            stockList(text.repeatedStocks, report.repeated, value: { $0.netTotal }, showOrg: false)
                        }
                    }
                    if let selected = model.selectedStock, let stock = report.stocks.first(where: { $0.thscode == selected }) {
                        stockDetail(stock, report)
                    }
                    rowsCard(report)
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

    private func stockList(_ title: String, _ stocks: [DragonTigerWatchReport.StockRecord], value: @escaping (DragonTigerWatchReport.StockRecord) -> Double, showOrg: Bool) -> some View {
        SectionCard(title: title) {
            CollapsibleList(items: stocks, limit: 10) { stock in
                Button { model.selectedStock = model.selectedStock == stock.thscode ? nil : stock.thscode } label: {
                    HStack(spacing: 8) {
                        Text(stock.name).font(.callout).foregroundStyle(model.selectedStock == stock.thscode ? Theme.accentStrong : Theme.text).frame(width: 84, alignment: .leading).lineLimit(1)
                        MoneyText(value: value(stock)).font(.callout).frame(width: 84, alignment: .trailing)
                        if showOrg {
                            Text(String(format: text.orgCountFormat, stock.orgBuyCount, stock.orgSellCount)).font(.caption).foregroundStyle(Theme.muted)
                        }
                        Chip(text: String(format: text.appearancesFormat, stock.appearances))
                        ChangeText(value: stock.latestChange, isPercent: false).font(.caption)
                        Text(stock.reason ?? stock.concepts.prefix(2).joined(separator: " / ")).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func playersCard(_ report: DragonTigerWatchReport) -> some View {
        SectionCard(title: text.activePlayers) {
            CollapsibleList(items: report.players, limit: 12) { player in
                Button { model.selectedPlayer = model.selectedPlayer == player.name ? nil : player.name } label: {
                    HStack(spacing: 8) {
                        Text(player.name).font(.callout.weight(.medium)).foregroundStyle(model.selectedPlayer == player.name ? Theme.accentStrong : Theme.text).frame(width: 100, alignment: .leading).lineLimit(1)
                        MoneyText(value: player.netTotal).font(.callout).frame(width: 84, alignment: .trailing)
                        Chip(text: String(format: text.appearancesFormat, player.appearances))
                        Text(player.conceptCounts.prefix(2).map(\.0).joined(separator: " / ")).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func playerDetail(_ player: DragonTigerWatchReport.PlayerRecord, _ report: DragonTigerWatchReport) -> some View {
        SectionCard(title: player.name, subtitle: player.days.joined(separator: " · ")) {
            HStack(spacing: 10) {
                KPITile(label: text.netBuy, value: MoneyFormat.yuan(player.netTotal), color: Theme.changeColor(player.netTotal))
                KPITile(label: text.buy, value: MoneyFormat.yuan(player.buyTotal), color: Theme.up)
                KPITile(label: text.sell, value: MoneyFormat.yuan(player.sellTotal), color: Theme.down)
            }
            Text(text.playerPreference).font(.caption).foregroundStyle(Theme.muted)
            HStack(spacing: 6) {
                ForEach(player.conceptCounts.prefix(6), id: \.0) { concept, count in
                    Chip(text: "\(concept) ×\(count)")
                }
            }
            Text(text.playerStocks).font(.caption).foregroundStyle(Theme.muted)
            ForEach(report.rows.filter { $0.player == player.name }) { row in
                HStack(spacing: 8) {
                    Text(row.date).font(.caption.monospacedDigit()).foregroundStyle(Theme.muted)
                    Text(row.stock).font(.callout).foregroundStyle(Theme.text)
                    ChangeText(value: row.change, isPercent: false).font(.caption)
                    Spacer()
                    MoneyText(value: row.net).font(.callout)
                }
            }
        }
    }

    private func stockDetail(_ stock: DragonTigerWatchReport.StockRecord, _ report: DragonTigerWatchReport) -> some View {
        SectionCard(title: "\(stock.name) \(stock.thscode)", subtitle: stock.reason ?? stock.concepts.joined(separator: " / ")) {
            HStack(spacing: 10) {
                KPITile(label: text.netBuy, value: MoneyFormat.yuan(stock.netTotal), color: Theme.changeColor(stock.netTotal))
                KPITile(label: text.orgBuys, value: MoneyFormat.yuan(stock.orgNetTotal), color: Theme.changeColor(stock.orgNetTotal), caption: String(format: text.orgCountFormat, stock.orgBuyCount, stock.orgSellCount))
                KPITile(label: text.hotMoneyNetTotal, value: MoneyFormat.yuan(stock.hotMoneyNetTotal), color: Theme.changeColor(stock.hotMoneyNetTotal))
                KPITile(label: text.date, value: stock.days.joined(separator: ", "))
            }
            ForEach(report.rows.filter { $0.thscode == stock.thscode }) { row in
                HStack(spacing: 8) {
                    Text(row.date).font(.caption.monospacedDigit()).foregroundStyle(Theme.muted)
                    Text(row.player).font(.callout).foregroundStyle(Theme.text)
                    Spacer()
                    MoneyText(value: row.net).font(.callout)
                }
            }
        }
    }

    private func rowsCard(_ report: DragonTigerWatchReport) -> some View {
        SectionCard(title: text.dailyRows) {
            CollapsibleList(items: report.rows, limit: 12) { row in
                HStack(spacing: 8) {
                    Text(row.date).font(.caption.monospacedDigit()).foregroundStyle(Theme.muted).frame(width: 78, alignment: .leading)
                    Text(row.player).font(.callout).foregroundStyle(Theme.text).frame(width: 100, alignment: .leading).lineLimit(1)
                    Text(row.stock).font(.callout).foregroundStyle(Theme.text).frame(width: 84, alignment: .leading).lineLimit(1)
                    ChangeText(value: row.change, isPercent: false).font(.caption).frame(width: 60, alignment: .trailing)
                    Spacer()
                    MoneyText(value: row.net).font(.callout)
                }
            }
        }
    }
}
