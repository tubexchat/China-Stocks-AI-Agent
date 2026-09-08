import SwiftUI

/// 盘面工作区:模块卡列表 → 模块页。选中项存 ViewModel,与侧栏联动。
struct ModulesView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Group {
            if let module = viewModel.selectedModule {
                moduleView(module)
                    .id(module)
            } else {
                moduleGrid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    @ViewBuilder
    private func moduleView(_ module: AgentModule) -> some View {
        switch module {
        case .limitUpPulse:
            LimitUpPulseView(viewModel: viewModel, model: viewModel.limitUpPulse)
        case .dragonTigerTopology:
            DragonTigerTopologyView(viewModel: viewModel, model: viewModel.dragonTigerTopology)
        case .heatRadar:
            HeatRadarView(viewModel: viewModel, model: viewModel.heatRadar)
        case .marketTrend:
            MarketTrendView(viewModel: viewModel, model: viewModel.marketTrend)
        case .dragonTigerWatch:
            DragonTigerWatchView(viewModel: viewModel, model: viewModel.dragonTigerWatch)
        }
    }

    private var moduleGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.text.modulesHeader)
                        .font(.title.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Text(viewModel.text.modulesSubtitle)
                        .font(.callout)
                        .foregroundStyle(Theme.muted)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 14)], spacing: 14) {
                    ForEach(AgentModule.allCases) { module in
                        Button {
                            viewModel.selectedModule = module
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Image(systemName: module.icon)
                                    .font(.system(size: 26))
                                    .foregroundStyle(Theme.accent)
                                Text(viewModel.text.moduleName(module))
                                    .font(.headline)
                                    .foregroundStyle(Theme.text)
                                Text(viewModel.text.moduleSubtitle(module))
                                    .font(.callout)
                                    .foregroundStyle(Theme.muted)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(18)
                            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer()
            }
            .padding(28)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - 模块页共用组件

/// 模块页头:返回 + 图标 + 标题 + 右侧控件。
struct ModuleHeader<Trailing: View>: View {
    @ObservedObject var viewModel: AppViewModel
    let module: AgentModule
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            Button { viewModel.selectedModule = nil } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(Theme.muted)
            }
            .buttonStyle(.plain)
            .help(viewModel.text.backToModules)
            Image(systemName: module.icon)
                .foregroundStyle(Theme.accent)
            Text(viewModel.text.moduleName(module))
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.text)
            Spacer()
            trailing()
        }
    }
}

/// 加载 / 错误 / 进度一条龙。
struct ModuleStatusBar: View {
    @ObservedObject var model: ModuleModel
    @Environment(\.l10n) private var l10n

    var body: some View {
        if model.isLoading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(model.progressText ?? l10n.loading).font(.callout).foregroundStyle(Theme.muted)
            }
        }
        if let errorText = model.errorText {
            Text(errorText)
                .font(.callout)
                .foregroundStyle(Theme.danger)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.danger.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

/// 数字瓷砖。
struct KPITile: View {
    let label: String
    let value: String
    var color: Color = Theme.text
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(Theme.muted)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let caption {
                Text(caption).font(.caption2).foregroundStyle(Theme.muted).lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// 带标题的卡片。
struct SectionCard<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Theme.text)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(Theme.muted)
                }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
    }
}

/// 「让 AI 解读」+ 免责声明。
struct AnalyzeBar: View {
    @ObservedObject var viewModel: AppViewModel
    let report: String?

    var body: some View {
        HStack {
            Button {
                if let report { viewModel.analyze(report: report) }
            } label: {
                Label(viewModel.text.analyzeWithAI, systemImage: "sparkles")
            }
            .disabled(report == nil)
            Text(viewModel.text.disclaimer)
                .font(.caption)
                .foregroundStyle(Theme.muted)
            Spacer()
        }
    }
}

/// 交易日前后翻页。
struct DateNavigator: View {
    let date: String
    let onPrevious: () -> Void
    let onNext: () -> Void
    var onToday: (() -> Void)?
    @Environment(\.l10n) private var l10n

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onPrevious) { Image(systemName: "chevron.left") }
                .help(l10n.previousDay)
            Text(date)
                .font(.callout.monospacedDigit())
                .foregroundStyle(Theme.text)
                .frame(minWidth: 88)
            Button(action: onNext) { Image(systemName: "chevron.right") }
                .help(l10n.nextDay)
            if let onToday {
                Button(l10n.today, action: onToday)
            }
        }
        .controlSize(.small)
    }
}

/// 涨跌幅文本(红涨绿跌)。
struct ChangeText: View {
    let value: Double?
    /// 输入是否已经是百分数(10.0 = +10%);否则按小数(0.1 = +10%)。
    var isPercent = true

    var body: some View {
        let pct = value.map { isPercent ? $0 : $0 * 100 }
        Text(pct.map(MarketSnapshot.formatPercent) ?? "—")
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(Theme.changeColor(pct))
    }
}

/// 金额文本(元 → 亿/万),按正负着色。
struct MoneyText: View {
    let value: Double?
    var signed = true

    var body: some View {
        Text(value.map { (signed && $0 > 0 ? "+" : "") + MoneyFormat.yuan($0) } ?? "—")
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(signed ? Theme.changeColor(value) : Theme.text)
    }
}

/// 可折叠列表:默认显示前 N 行。
struct CollapsibleList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    var limit = 8
    @ViewBuilder var row: (Item) -> Row
    @State private var expanded = false
    @Environment(\.l10n) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(expanded ? items : Array(items.prefix(limit))) { item in
                row(item)
            }
            if items.count > limit {
                Button(expanded ? l10n.showLess : "\(l10n.showMore) (\(items.count))") { expanded.toggle() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Theme.accentStrong)
            }
            if items.isEmpty {
                Text(l10n.noData).font(.caption).foregroundStyle(Theme.muted)
            }
        }
    }
}

/// 小标签。
struct Chip: View {
    let text: String
    var color: Color = Theme.accentSoft
    var foreground: Color = Theme.text

    var body: some View {
        Text(text)
            .font(.caption)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
