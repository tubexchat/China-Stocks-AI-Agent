import SwiftUI
import Charts

/// 横向条形图:类别 → 数值。
struct HorizontalBars: View {
    struct Item: Identifiable {
        var label: String
        var value: Double
        var color: Color?
        var id: String { label }
    }

    let items: [Item]
    var color: Color = Theme.accent
    var valueLabel: (Double) -> String = { MarketSnapshot.formatNumber($0) }

    var body: some View {
        Chart(items) { item in
            BarMark(x: .value("value", item.value), y: .value("label", item.label))
                .foregroundStyle(item.color ?? color)
                .cornerRadius(3)
                .annotation(position: .trailing, alignment: .leading, spacing: 4) {
                    Text(valueLabel(item.value))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.muted)
                }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(preset: .aligned) { _ in
                AxisValueLabel().font(.caption).foregroundStyle(Theme.text)
            }
        }
        .chartYScale(domain: items.map(\.label))
        .frame(height: CGFloat(items.count) * 22 + 10)
    }
}

/// 纵向柱状图(分布 / 时间桶)。
struct VerticalBars: View {
    let items: [HorizontalBars.Item]
    var color: Color = Theme.accent
    var height: CGFloat = 140

    var body: some View {
        Chart(items) { item in
            BarMark(x: .value("label", item.label), y: .value("value", item.value))
                .foregroundStyle(item.color ?? color)
                .cornerRadius(3)
                .annotation(position: .top, spacing: 2) {
                    Text(MarketSnapshot.formatNumber(item.value))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.muted)
                }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel().font(.caption2).foregroundStyle(Theme.muted)
            }
        }
        .chartXScale(domain: items.map(\.label))
        .frame(height: height)
    }
}

/// 折线(带日期标签)。
struct LineSeries: View {
    struct Point: Identifiable {
        var x: String
        var y: Double
        var id: String { x }
    }

    let points: [Point]
    var color: Color = Theme.accent
    var height: CGFloat = 120
    var yLabel: (Double) -> String = { MarketSnapshot.formatNumber($0) }
    var reversed = false

    /// 类别轴不会自动抽稀,最多留 5 个刻度。
    private var xTicks: [String] {
        guard points.count > 5 else { return points.map(\.x) }
        let step = max(1, points.count / 4)
        var ticks = stride(from: 0, to: points.count, by: step).map { points[$0].x }
        if let last = points.last?.x, ticks.last != last { ticks.append(last) }
        return ticks
    }

    var body: some View {
        Chart(points) { point in
            LineMark(x: .value("x", point.x), y: .value("y", point.y))
                .foregroundStyle(color)
                .interpolationMethod(.catmullRom)
            AreaMark(x: .value("x", point.x), y: .value("y", point.y))
                .foregroundStyle(LinearGradient(colors: [color.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.catmullRom)
        }
        .chartXScale(domain: points.map(\.x))
        .chartYScale(domain: .automatic(includesZero: false, reversed: reversed))
        .chartXAxis {
            AxisMarks(values: xTicks) { value in
                AxisValueLabel {
                    if let text = value.as(String.self) { Text(String(text.suffix(5))).font(.caption2) }
                }
                .foregroundStyle(Theme.muted)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Theme.border)
                AxisValueLabel {
                    if let y = value.as(Double.self) { Text(yLabel(y)).font(.caption2) }
                }
                .foregroundStyle(Theme.muted)
            }
        }
        .frame(height: height)
    }
}

/// 热力格:按值在红(正)/ 绿(负)之间着色。
struct HeatCell: View {
    let value: Double
    /// 满色对应的绝对值。
    var scale: Double = 0.05
    var text: String?

    var body: some View {
        let intensity = min(abs(value) / scale, 1)
        let base = value >= 0 ? Theme.up : Theme.down
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(base.opacity(0.12 + 0.75 * intensity))
            if let text {
                Text(text)
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(intensity > 0.55 ? Color.white : Theme.text)
            }
        }
    }
}

/// 热度雷达:沿螺旋按排名展开(角度与半径都随排名增加),点大小 = 热度(对数),红升绿降,圈点 = 共振。
struct RadarCanvas: View {
    let points: [HeatRadarReport.RadarPoint]
    var selected: String?
    var onSelect: (String?) -> Void = { _ in }

    private var placed: [(HeatRadarReport.RadarPoint, angle: Double, radius: Double, size: Double)] {
        let ranked = points.filter { $0.hotRank != nil }.sorted { ($0.hotRank ?? 0) < ($1.hotRank ?? 0) }
        let maxHeat = log10(max(ranked.map(\.heat).max() ?? 1, 1) + 1)
        let minHeat = log10(max(ranked.map(\.heat).min() ?? 1, 1) + 1)
        let span = max(maxHeat - minHeat, 0.0001)
        return ranked.enumerated().map { index, point in
            let rank = Double(point.hotRank ?? index + 1)
            // 两圈螺旋:每 15 名转一圈,半径随排名外推,相邻点既错角又错半径,不重叠。
            let angle = (rank - 1) / 15 * 2 * .pi - .pi / 2
            let radius = 0.22 + 0.74 * (rank - 1) / 29
            let size = (log10(point.heat + 1) - minHeat) / span
            return (point, angle, radius, size)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let maxR = size / 2 - 24
            ZStack {
                Canvas { context, _ in
                    for ring in [0.25, 0.5, 0.75, 1.0] {
                        let r = maxR * ring
                        context.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)), with: .color(Theme.border), lineWidth: 1)
                    }
                    for spoke in 0..<6 {
                        let angle = Double(spoke) / 6 * 2 * .pi - .pi / 2
                        var path = Path()
                        path.move(to: center)
                        path.addLine(to: CGPoint(x: center.x + maxR * cos(angle), y: center.y + maxR * sin(angle)))
                        context.stroke(path, with: .color(Theme.border.opacity(0.7)), lineWidth: 1)
                    }
                    context.draw(Text("#1").font(.caption2).foregroundStyle(Theme.muted), at: CGPoint(x: center.x, y: center.y - maxR * 0.1))
                    context.draw(Text("#30").font(.caption2).foregroundStyle(Theme.muted), at: CGPoint(x: center.x, y: center.y - maxR - 12))
                }
                ForEach(placed, id: \.0.id) { entry in
                    let (point, angle, radius, size) = entry
                    let position = CGPoint(x: center.x + maxR * radius * cos(angle), y: center.y + maxR * radius * sin(angle))
                    let dotColor: Color = point.trend == "up" ? Theme.up : (point.trend == "down" ? Theme.down : Theme.muted)
                    let dot = 6 + 12 * size
                    let isSelected = point.id == selected
                    Button {
                        onSelect(isSelected ? nil : point.id)
                    } label: {
                        ZStack {
                            if point.resonance {
                                Circle().stroke(Theme.accent, lineWidth: 2).frame(width: dot + 8, height: dot + 8)
                            }
                            Circle().fill(dotColor).frame(width: dot, height: dot)
                                .overlay(Circle().stroke(isSelected ? Theme.text : .clear, lineWidth: 2))
                            Text(point.name)
                                .font(.system(size: 9))
                                .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                                .offset(y: dot / 2 + 8)
                        }
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .position(position)
                    .help("\(point.name) 热度 \(MarketSnapshot.formatNumber(point.heat))\(point.anomalyTag.map { " · \($0)" } ?? "")")
                }
            }
        }
    }
}

/// 资金流拓扑:三列(席位 / 股票 / 概念),贝塞尔边,线宽 ∝ 金额,红买绿卖。
struct TopologyCanvas: View {
    let graph: FlowGraph
    var selected: String?
    var onSelect: (String?) -> Void = { _ in }
    var maxStocks = 40
    /// 股票列每行高度;外层按它算画布高度。
    static let rowHeight: CGFloat = 24

    private struct Layout {
        var positions: [String: CGPoint]
        var sizes: [String: CGFloat]
    }

    private func layout(in size: CGSize) -> Layout {
        let players = graph.nodes(of: .player)
        let stocks = Array(graph.nodes(of: .stock).prefix(maxStocks))
        let concepts = graph.nodes(of: .concept)
        let columns: [(CGFloat, [FlowGraph.Node])] = [(0.12, players), (0.5, stocks), (0.88, concepts)]
        var positions: [String: CGPoint] = [:]
        var sizes: [String: CGFloat] = [:]
        let maxGross = max(graph.nodes.map(\.gross).max() ?? 1, 1)
        for (xRatio, nodes) in columns {
            let count = max(nodes.count, 1)
            let step = (size.height - 40) / CGFloat(count)
            for (index, node) in nodes.enumerated() {
                positions[node.id] = CGPoint(x: size.width * xRatio, y: 20 + step * (CGFloat(index) + 0.5))
                sizes[node.id] = 6 + 14 * CGFloat(sqrt(node.gross / maxGross))
            }
        }
        return Layout(positions: positions, sizes: sizes)
    }

    var body: some View {
        GeometryReader { geo in
            let layout = layout(in: geo.size)
            let highlighted: Set<String>? = selected.map { graph.neighbors(of: $0).union([$0]) }
            let maxEdge = max(graph.edges.map { abs($0.value) }.max() ?? 1, 1)
            ZStack {
                Canvas { context, _ in
                    for edge in graph.edges {
                        guard let from = layout.positions[edge.from], let to = layout.positions[edge.to] else { continue }
                        let active = highlighted.map { $0.contains(edge.from) && $0.contains(edge.to) } ?? true
                        var path = Path()
                        path.move(to: from)
                        let dx = (to.x - from.x) * 0.5
                        path.addCurve(to: to, control1: CGPoint(x: from.x + dx, y: from.y), control2: CGPoint(x: to.x - dx, y: to.y))
                        let width = 1 + 7 * CGFloat(sqrt(abs(edge.value) / maxEdge))
                        let color = (edge.value >= 0 ? Theme.up : Theme.down).opacity(active ? 0.75 : 0.08)
                        context.stroke(path, with: .color(color), lineWidth: width)
                    }
                }
                ForEach(graph.nodes.filter { layout.positions[$0.id] != nil }) { node in
                    let position = layout.positions[node.id] ?? .zero
                    let radius = layout.sizes[node.id] ?? 6
                    let active = highlighted?.contains(node.id) ?? true
                    let fill: Color = node.kind == .stock ? Theme.changeColor(node.net) : (node.kind == .player ? Theme.accent : Theme.muted)
                    Button {
                        onSelect(selected == node.id ? nil : node.id)
                    } label: {
                        HStack(spacing: 4) {
                            if node.kind == .concept { label(node, active: active) }
                            Circle()
                                .fill(fill.opacity(active ? 1 : 0.25))
                                .frame(width: radius * 2, height: radius * 2)
                                .overlay(Circle().stroke(selected == node.id ? Theme.text : .clear, lineWidth: 2))
                            if node.kind != .concept { label(node, active: active) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .position(position)
                    .help("\(node.label) \(MoneyFormat.yuan(node.net))\(node.reason.map { " · \($0)" } ?? "")")
                }
            }
        }
    }

    private func label(_ node: FlowGraph.Node, active: Bool) -> some View {
        VStack(alignment: node.kind == .concept ? .trailing : .leading, spacing: 0) {
            Text(node.label)
                .font(.system(size: 10, weight: node.kind == .stock ? .regular : .medium))
                .foregroundStyle(active ? Theme.text : Theme.disabled)
                .lineLimit(1)
            Text(MoneyFormat.yuan(node.net))
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(active ? Theme.changeColor(node.net) : Theme.disabled)
        }
        .fixedSize()
    }
}
