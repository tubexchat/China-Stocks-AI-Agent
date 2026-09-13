import SwiftUI
import Charts

/// 气泡图(行业强度矩阵):横纵轴为相对强度(百分数),气泡大小 = 成交额脉冲;悬停出数值,点击选中。
struct BubbleChart: View {
    struct Item: Identifiable {
        var id: String
        var label: String
        var x: Double
        var y: Double
        var size: Double
        var color: Color
        var detail: String
    }

    let items: [Item]
    var selected: String?
    var xLabel = "RS20"
    var yLabel = "RS60"
    var height: CGFloat = 380
    var onSelect: (String?) -> Void = { _ in }
    @State private var hovered: String?

    /// 只给最突出的 12 个 + 选中 / 悬停的点写名字,免得糊成一片。
    private var labeled: Set<String> {
        var ids = Set(items.sorted { abs($0.x) + abs($0.y) > abs($1.x) + abs($1.y) }.prefix(12).map(\.id))
        if let selected { ids.insert(selected) }
        if let hovered { ids.insert(hovered) }
        return ids
    }

    private func symbolSize(_ item: Item) -> CGFloat {
        CGFloat(40 + 160 * min(max(item.size, 0.2), 3) / 3)
    }

    var body: some View {
        let labeled = labeled
        Chart {
            RuleMark(x: .value("zero", 0)).foregroundStyle(Theme.border)
            RuleMark(y: .value("zero", 0)).foregroundStyle(Theme.border)
            ForEach(items) { item in
                PointMark(x: .value(xLabel, item.x), y: .value(yLabel, item.y))
                    .symbolSize(symbolSize(item))
                    .foregroundStyle(item.color.opacity(item.id == selected || item.id == hovered ? 0.95 : 0.5))
                    .annotation(position: .top, spacing: 0) {
                        if labeled.contains(item.id) {
                            Text(item.label)
                                .font(.system(size: 9))
                                .foregroundStyle(item.id == selected ? Theme.text : Theme.muted)
                        }
                    }
            }
        }
        .chartXAxisLabel(xLabel, alignment: .trailing)
        .chartYAxisLabel(yLabel, position: .leading)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisGridLine().foregroundStyle(Theme.border.opacity(0.6))
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(NumberFormat.number(v) + "%").font(.caption2) }
                }
                .foregroundStyle(Theme.muted)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 6)) { value in
                AxisGridLine().foregroundStyle(Theme.border.opacity(0.6))
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(NumberFormat.number(v) + "%").font(.caption2) }
                }
                .foregroundStyle(Theme.muted)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                BubbleHoverLayer(items: items, proxy: proxy, geo: geo, hovered: $hovered, onSelect: onSelect)
            }
        }
        .frame(height: height)
    }
}

/// 悬停 / 点击命中最近的气泡(像素距离 ≤ 28pt)。
private struct BubbleHoverLayer: View {
    let items: [BubbleChart.Item]
    let proxy: ChartProxy
    let geo: GeometryProxy
    @Binding var hovered: String?
    let onSelect: (String?) -> Void

    private var plotOrigin: CGPoint {
        proxy.plotFrame.map { geo[$0].origin } ?? .zero
    }

    private func position(of item: BubbleChart.Item) -> CGPoint? {
        guard let x = proxy.position(forX: item.x), let y = proxy.position(forY: item.y) else { return nil }
        return CGPoint(x: x + plotOrigin.x, y: y + plotOrigin.y)
    }

    private func nearest(_ location: CGPoint) -> BubbleChart.Item? {
        var best: (BubbleChart.Item, CGFloat)?
        for item in items {
            guard let p = position(of: item) else { continue }
            let d = hypot(p.x - location.x, p.y - location.y)
            if d <= 28, d < (best?.1 ?? .infinity) { best = (item, d) }
        }
        return best?.0
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color.clear).contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location): hovered = nearest(location)?.id
                    case .ended: hovered = nil
                    }
                }
                .onTapGesture(coordinateSpace: .local) { location in
                    onSelect(nearest(location)?.id)
                }
            if let hovered, let item = items.first(where: { $0.id == hovered }), let p = position(of: item) {
                ChartTooltip(title: item.label, lines: item.detail.split(separator: "\n").map(String.init))
                    .offset(x: min(max(p.x + 12, 0), geo.size.width - 190), y: min(max(p.y - 40, 0), geo.size.height - 90))
                    .allowsHitTesting(false)
            }
        }
    }
}

/// 图表悬停提示框。
struct ChartTooltip: View {
    let title: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Theme.text)
            ForEach(lines, id: \.self) { line in
                Text(line).font(.caption2.monospacedDigit()).foregroundStyle(Theme.muted)
            }
        }
        .padding(8)
        .background(Theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
        .frame(maxWidth: 180, alignment: .leading)
        .fixedSize()
    }
}

/// 报告期 × 多序列的分组柱状图;悬停 / 键盘选中某一期时高亮并显示该期全部值。缺失值不画(不补零)。
struct PeriodBarChart: View {
    struct Series: Identifiable {
        var name: String
        var color: Color
        var id: String { name }
    }

    struct Point: Identifiable {
        var id: Int64
        var label: String
        /// 与 `series` 一一对应;nil = 缺失。
        var values: [Double?]
    }

    let series: [Series]
    let points: [Point]
    @Binding var hovered: Int64?
    var height: CGFloat = 200
    var valueLabel: (Double) -> String = MoneyFormat.yuan

    private struct Bar: Identifiable {
        var id: String
        var period: String
        var periodID: Int64
        var series: String
        var value: Double
    }

    private var bars: [Bar] {
        points.flatMap { point in
            series.indices.compactMap { index -> Bar? in
                guard index < point.values.count, let value = point.values[index] else { return nil }
                return Bar(id: "\(point.id)#\(series[index].name)", period: point.label, periodID: point.id, series: series[index].name, value: value)
            }
        }
    }

    var body: some View {
        Chart {
            ForEach(bars) { bar in
                BarMark(x: .value("period", bar.period), y: .value(bar.series, bar.value))
                    .position(by: .value("series", bar.series))
                    .foregroundStyle(by: .value("series", bar.series))
                    .opacity(hovered == nil || hovered == bar.periodID ? 1 : 0.3)
                    .cornerRadius(2)
            }
            if let hovered, let point = points.first(where: { $0.id == hovered }) {
                RuleMark(x: .value("period", point.label))
                    .foregroundStyle(Theme.border)
                    .annotation(position: .top, alignment: .center, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ChartTooltip(title: point.label, lines: series.indices.map { index in
                            let value = index < point.values.count ? point.values[index] : nil
                            return "\(series[index].name) \(value.map(valueLabel) ?? "—")"
                        })
                    }
            }
        }
        .chartForegroundStyleScale(domain: series.map(\.name), range: series.map(\.color))
        .chartXScale(domain: points.map(\.label))
        .chartLegend(position: .top, alignment: .leading)
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel().font(.caption2).foregroundStyle(Theme.muted)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Theme.border)
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(valueLabel(v)).font(.caption2) }
                }
                .foregroundStyle(Theme.muted)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                let origin = proxy.plotFrame.map { geo[$0].origin } ?? .zero
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            if let label: String = proxy.value(atX: location.x - origin.x) {
                                hovered = points.first { $0.label == label }?.id
                            }
                        case .ended:
                            hovered = nil
                        }
                    }
            }
        }
        .frame(height: height)
    }
}

/// 瀑布桥:总量柱与增减柱交替(净利润 → 应计 → 经营现金流 → 购建支出 → 自由现金流)。
/// 任一环节缺失就断链,后续只画得出的总量。
struct WaterfallChart: View {
    struct Step: Identifiable {
        enum Kind { case total, delta }
        var label: String
        var amount: Double?
        var kind: Kind
        var id: String { label }
    }

    let steps: [Step]
    var height: CGFloat = 200

    private struct Bar: Identifiable {
        var id: String
        var label: String
        var start: Double
        var end: Double
        var color: Color
        var text: String
    }

    private var bars: [Bar] {
        var level: Double? = 0
        var result: [Bar] = []
        for step in steps {
            switch (step.kind, step.amount) {
            case (.total, let amount?):
                result.append(Bar(id: step.label, label: step.label, start: 0, end: amount, color: Theme.accent, text: MoneyFormat.yuan(amount)))
                level = amount
            case (.delta, let amount?):
                if let current = level {
                    result.append(Bar(id: step.label, label: step.label, start: current, end: current + amount, color: amount >= 0 ? Theme.up : Theme.down, text: (amount >= 0 ? "+" : "") + MoneyFormat.yuan(amount)))
                    level = current + amount
                } else {
                    level = nil
                }
            default:
                level = nil
            }
        }
        return result
    }

    var body: some View {
        let bars = bars
        Chart(bars) { bar in
            BarMark(x: .value("step", bar.label), yStart: .value("start", bar.start), yEnd: .value("end", bar.end))
                .foregroundStyle(bar.color.opacity(0.85))
                .cornerRadius(3)
                .annotation(position: bar.end >= bar.start ? .top : .bottom, spacing: 2) {
                    Text(bar.text).font(.caption2.monospacedDigit()).foregroundStyle(Theme.muted)
                }
        }
        .chartXScale(domain: steps.map(\.label))
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let label = value.as(String.self) {
                        let missing = steps.first { $0.label == label }?.amount == nil
                        Text(missing ? "\(label)(—)" : label).font(.caption2).foregroundStyle(missing ? Theme.disabled : Theme.muted)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Theme.border)
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(MoneyFormat.yuan(v)).font(.caption2) }
                }
                .foregroundStyle(Theme.muted)
            }
        }
        .frame(height: height)
    }
}
