import SwiftUI

/// 模块 2:龙虎榜资金流拓扑图。
struct DragonTigerTopologyView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var model: DragonTigerTopologyModel

    private var text: L10nStrings { viewModel.text }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ModuleHeader(viewModel: viewModel, module: .dragonTigerTopology) {
                    DateNavigator(
                        date: model.displayDate.isEmpty ? "—" : model.displayDate,
                        onPrevious: { model.stepDay(-1) },
                        onNext: { model.stepDay(1) },
                        onToday: { model.load(date: nil) }
                    )
                    Button { model.load() } label: { Image(systemName: "arrow.clockwise") }
                        .controlSize(.small)
                        .help(text.refresh)
                }
                ModuleStatusBar(model: model)

                if let graph = model.graph {
                    summaryRow(graph)
                    SectionCard(title: text.dragonTigerTopologyName, subtitle: text.topologyHint) {
                        TopologyCanvas(graph: graph, selected: model.selectedNodeID) { model.selectedNodeID = $0 }
                            .frame(height: max(420, CGFloat(min(graph.nodes(of: .stock).count, 40)) * TopologyCanvas.rowHeight + 40))
                    }
                    if let selectedID = model.selectedNodeID, let node = graph.node(selectedID) {
                        selectionCard(graph, node)
                    }
                    HStack(alignment: .top, spacing: 14) {
                        playersCard(graph)
                        conceptsCard(graph)
                    }
                    edgesCard(graph)
                    AnalyzeBar(viewModel: viewModel, report: graph.promptText)
                }
                Spacer(minLength: 20)
            }
            .padding(24)
            .frame(maxWidth: 1200, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear { if model.graph == nil && !model.isLoading { model.load() } }
    }

    private func summaryRow(_ graph: FlowGraph) -> some View {
        let players = graph.nodes(of: .player)
        let stocks = graph.nodes(of: .stock)
        let inflow = stocks.map(\.net).filter { $0 > 0 }.reduce(0, +)
        let outflow = stocks.map(\.net).filter { $0 < 0 }.reduce(0, +)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
            KPITile(label: text.topologyNetIn, value: MoneyFormat.yuan(inflow), color: Theme.up)
            KPITile(label: text.topologyNetOut, value: MoneyFormat.yuan(outflow), color: Theme.down)
            KPITile(label: text.orgNetTotal, value: MoneyFormat.yuan(graph.node(FlowGraph.institutionID)?.net ?? 0), color: Theme.changeColor(graph.node(FlowGraph.institutionID)?.net))
            KPITile(label: String(format: text.topologyNodeCountFormat, players.count, stocks.count, graph.nodes(of: .concept).count), value: graph.date)
        }
    }

    private func selectionCard(_ graph: FlowGraph, _ node: FlowGraph.Node) -> some View {
        let edges = graph.edges.filter { $0.from == node.id || $0.to == node.id }.sorted { abs($0.value) > abs($1.value) }
        return SectionCard(title: node.label, subtitle: node.reason) {
            HStack(spacing: 14) {
                KPITile(label: text.netBuy, value: MoneyFormat.yuan(node.net), color: Theme.changeColor(node.net))
                if let change = node.change {
                    KPITile(label: text.change, value: MarketSnapshot.formatPercent(change * 100), color: Theme.changeColor(change))
                }
            }
            ForEach(edges.prefix(20)) { edge in
                let otherID = edge.from == node.id ? edge.to : edge.from
                HStack(spacing: 8) {
                    Image(systemName: edge.from == node.id ? "arrow.right" : "arrow.left").font(.caption).foregroundStyle(Theme.muted)
                    Text(graph.node(otherID)?.label ?? otherID).font(.callout).foregroundStyle(Theme.text)
                    Spacer()
                    MoneyText(value: edge.value).font(.callout)
                }
            }
        }
    }

    private func playersCard(_ graph: FlowGraph) -> some View {
        SectionCard(title: text.topologyPlayers) {
            let players = graph.nodes(of: .player)
            HorizontalBars(
                items: players.prefix(14).map { .init(label: $0.label, value: $0.net / 1e4, color: Theme.changeColor($0.net)) },
                valueLabel: { MoneyFormat.yuan($0 * 1e4) }
            )
        }
    }

    private func conceptsCard(_ graph: FlowGraph) -> some View {
        SectionCard(title: text.topologyConcepts) {
            let concepts = graph.nodes(of: .concept).sorted { $0.net > $1.net }
            HorizontalBars(
                items: concepts.prefix(14).map { .init(label: $0.label, value: $0.net / 1e4, color: Theme.changeColor($0.net)) },
                valueLabel: { MoneyFormat.yuan($0 * 1e4) }
            )
        }
    }

    private func edgesCard(_ graph: FlowGraph) -> some View {
        SectionCard(title: text.topologyEdges) {
            CollapsibleList(items: Array(graph.edges.prefix(30)), limit: 10) { edge in
                HStack(spacing: 8) {
                    Text(graph.node(edge.from)?.label ?? edge.from).font(.callout).foregroundStyle(Theme.text).frame(width: 110, alignment: .leading).lineLimit(1)
                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(Theme.muted)
                    Text(graph.node(edge.to)?.label ?? edge.to).font(.callout).foregroundStyle(Theme.text).frame(width: 110, alignment: .leading).lineLimit(1)
                    Spacer()
                    MoneyText(value: edge.value).font(.callout)
                }
            }
        }
    }
}
