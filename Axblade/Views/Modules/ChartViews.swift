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
    var valueLabel: (Double) -> String = { NumberFormat.number($0) }

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
                    Text(NumberFormat.number(item.value))
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
    var yLabel: (Double) -> String = { NumberFormat.number($0) }
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

    /// 已算好极坐标的一个点。拆成具名结构体而不是元组:CI 上的编译器对元组 + 大闭包会类型推断超时。
    struct PlacedPoint: Identifiable {
        var point: HeatRadarReport.RadarPoint
        var angle: Double
        var radius: Double
        var size: Double
        var id: String { point.id }
    }

    private var placed: [PlacedPoint] {
        let ranked = points.filter { $0.hotRank != nil }.sorted { ($0.hotRank ?? 0) < ($1.hotRank ?? 0) }
        let heats = ranked.map(\.heat)
        let maxHeat = log10(max(heats.max() ?? 1, 1) + 1)
        let minHeat = log10(max(heats.min() ?? 1, 1) + 1)
        let span = max(maxHeat - minHeat, 0.0001)
        var result: [PlacedPoint] = []
        for (index, point) in ranked.enumerated() {
            let rank = Double(point.hotRank ?? index + 1)
            // 两圈螺旋:每 15 名转一圈,半径随排名外推,相邻点既错角又错半径,不重叠。
            let angle: Double = (rank - 1) / 15 * 2 * Double.pi - Double.pi / 2
            let radius: Double = 0.22 + 0.74 * (rank - 1) / 29
            let size: Double = (log10(point.heat + 1) - minHeat) / span
            result.append(PlacedPoint(point: point, angle: angle, radius: radius, size: size))
        }
        return result
    }

    var body: some View {
        GeometryReader { geo in
            let side: CGFloat = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let maxR: CGFloat = side / 2 - 24
            ZStack {
                RadarGrid(center: center, maxR: maxR)
                ForEach(placed) { entry in
                    RadarDot(entry: entry, center: center, maxR: maxR, isSelected: entry.id == selected) {
                        onSelect(entry.id == selected ? nil : entry.id)
                    }
                }
            }
        }
    }
}

/// 雷达底图:同心圆 + 六根辐条 + 排名标注。
private struct RadarGrid: View {
    let center: CGPoint
    let maxR: CGFloat

    var body: some View {
        Canvas { context, _ in
            for ring in [0.25, 0.5, 0.75, 1.0] {
                let r = maxR * CGFloat(ring)
                let rect = CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)
                context.stroke(Path(ellipseIn: rect), with: .color(Theme.border), lineWidth: 1)
            }
            for spoke in 0..<6 {
                let angle = Double(spoke) / 6 * 2 * Double.pi - Double.pi / 2
                var path = Path()
                path.move(to: center)
                path.addLine(to: CGPoint(x: center.x + maxR * CGFloat(cos(angle)), y: center.y + maxR * CGFloat(sin(angle))))
                context.stroke(path, with: .color(Theme.border.opacity(0.7)), lineWidth: 1)
            }
            let inner = Text("#1").font(.caption2).foregroundStyle(Theme.muted)
            context.draw(inner, at: CGPoint(x: center.x, y: center.y - maxR * 0.1))
            let outer = Text("#30").font(.caption2).foregroundStyle(Theme.muted)
            context.draw(outer, at: CGPoint(x: center.x, y: center.y - maxR - 12))
        }
    }
}

/// 雷达上的一个点(可点击)。
private struct RadarDot: View {
    let entry: RadarCanvas.PlacedPoint
    let center: CGPoint
    let maxR: CGFloat
    let isSelected: Bool
    let onTap: () -> Void

    private var point: HeatRadarReport.RadarPoint { entry.point }

    private var position: CGPoint {
        let r = maxR * CGFloat(entry.radius)
        return CGPoint(x: center.x + r * CGFloat(cos(entry.angle)), y: center.y + r * CGFloat(sin(entry.angle)))
    }

    private var dotColor: Color {
        if point.trend == "up" { return Theme.up }
        if point.trend == "down" { return Theme.down }
        return Theme.muted
    }

    private var dot: CGFloat { 6 + 12 * CGFloat(entry.size) }

    private var helpText: String {
        var text = "\(point.name) 热度 \(NumberFormat.number(point.heat))"
        if let tag = point.anomalyTag { text += " · \(tag)" }
        return text
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if point.resonance {
                    Circle()
                        .stroke(Theme.accent, lineWidth: 2)
                        .frame(width: dot + 8, height: dot + 8)
                }
                Circle()
                    .fill(dotColor)
                    .frame(width: dot, height: dot)
                    .overlay(Circle().stroke(isSelected ? Theme.text : Color.clear, lineWidth: 2))
                Text(point.name)
                    .font(.system(size: 9))
                    .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                    .offset(y: dot / 2 + 8)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .position(position)
        .help(helpText)
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

    struct Layout {
        var positions: [String: CGPoint] = [:]
        var sizes: [String: CGFloat] = [:]
    }

    private func layout(in size: CGSize) -> Layout {
        let players = graph.nodes(of: .player)
        let stocks = Array(graph.nodes(of: .stock).prefix(maxStocks))
        let concepts = graph.nodes(of: .concept)
        let columns: [(CGFloat, [FlowGraph.Node])] = [(0.12, players), (0.5, stocks), (0.88, concepts)]
        var layout = Layout()
        let maxGross: Double = max(graph.nodes.map(\.gross).max() ?? 1, 1)
        for (xRatio, nodes) in columns {
            let count = max(nodes.count, 1)
            let step = (size.height - 40) / CGFloat(count)
            for (index, node) in nodes.enumerated() {
                layout.positions[node.id] = CGPoint(x: size.width * xRatio, y: 20 + step * (CGFloat(index) + 0.5))
                layout.sizes[node.id] = 6 + 14 * CGFloat(sqrt(node.gross / maxGross))
            }
        }
        return layout
    }

    var body: some View {
        GeometryReader { geo in
            let layout = layout(in: geo.size)
            let highlighted: Set<String>? = selected.map { graph.neighbors(of: $0).union([$0]) }
            let visible = graph.nodes.filter { layout.positions[$0.id] != nil }
            ZStack {
                TopologyEdges(graph: graph, layout: layout, highlighted: highlighted)
                ForEach(visible) { node in
                    TopologyNode(
                        node: node,
                        position: layout.positions[node.id] ?? .zero,
                        radius: layout.sizes[node.id] ?? 6,
                        active: highlighted?.contains(node.id) ?? true,
                        isSelected: selected == node.id
                    ) {
                        onSelect(selected == node.id ? nil : node.id)
                    }
                }
            }
        }
    }
}

/// 所有资金边。
private struct TopologyEdges: View {
    let graph: FlowGraph
    let layout: TopologyCanvas.Layout
    let highlighted: Set<String>?

    var body: some View {
        let maxEdge: Double = max(graph.edges.map { abs($0.value) }.max() ?? 1, 1)
        Canvas { context, _ in
            for edge in graph.edges {
                guard let from = layout.positions[edge.from], let to = layout.positions[edge.to] else { continue }
                let active: Bool
                if let highlighted {
                    active = highlighted.contains(edge.from) && highlighted.contains(edge.to)
                } else {
                    active = true
                }
                var path = Path()
                path.move(to: from)
                let dx = (to.x - from.x) * 0.5
                path.addCurve(to: to, control1: CGPoint(x: from.x + dx, y: from.y), control2: CGPoint(x: to.x - dx, y: to.y))
                let width: CGFloat = 1 + 7 * CGFloat(sqrt(abs(edge.value) / maxEdge))
                let base: Color = edge.value >= 0 ? Theme.up : Theme.down
                context.stroke(path, with: .color(base.opacity(active ? 0.75 : 0.08)), lineWidth: width)
            }
        }
    }
}

/// 一个节点(圆点 + 名称 + 净额)。
private struct TopologyNode: View {
    let node: FlowGraph.Node
    let position: CGPoint
    let radius: CGFloat
    let active: Bool
    let isSelected: Bool
    let onTap: () -> Void

    private var fill: Color {
        switch node.kind {
        case .stock: Theme.changeColor(node.net)
        case .player: Theme.accent
        case .concept: Theme.muted
        }
    }

    private var helpText: String {
        var text = "\(node.label) \(MoneyFormat.yuan(node.net))"
        if let reason = node.reason { text += " · \(reason)" }
        return text
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                if node.kind == .concept { label }
                Circle()
                    .fill(fill.opacity(active ? 1 : 0.25))
                    .frame(width: radius * 2, height: radius * 2)
                    .overlay(Circle().stroke(isSelected ? Theme.text : Color.clear, lineWidth: 2))
                if node.kind != .concept { label }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(position)
        .help(helpText)
    }

    private var label: some View {
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

/// 迷你折线。
struct SparkLine: View {
    let values: [Double]
    var color: Color = Theme.accent

    var body: some View {
        GeometryReader { geo in
            if let min = values.min(), let max = values.max(), values.count > 1 {
                let range = max - min == 0 ? 1 : max - min
                Path { path in
                    for (index, value) in values.enumerated() {
                        let x = geo.size.width * CGFloat(index) / CGFloat(values.count - 1)
                        let y = geo.size.height * (1 - CGFloat((value - min) / range))
                        index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
