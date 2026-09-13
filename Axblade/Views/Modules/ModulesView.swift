import SwiftUI
import AppKit

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
        case .industryMatrix:
            IndustryMatrixView(viewModel: viewModel, model: viewModel.industryMatrix)
        case .cashFlowAudit:
            CashFlowAuditView(viewModel: viewModel, model: viewModel.cashFlowAudit)
        case .financialHealth:
            FinancialHealthView(viewModel: viewModel, model: viewModel.financialHealth)
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

/// 「复制报告」+ 免责声明:把本地算好的文字报告放进剪贴板,方便贴给任何模型或笔记。
struct ReportBar: View {
    let report: String?
    @Environment(\.l10n) private var l10n
    @State private var copied = false

    var body: some View {
        HStack {
            Button {
                guard let report else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(report, forType: .string)
                copied = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            } label: {
                Label(copied ? l10n.copied : l10n.copyReport, systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .disabled(report == nil)
            Text(l10n.disclaimer)
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
        Text(pct.map(NumberFormat.percent) ?? "—")
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize(horizontal: false, vertical: true)
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
            .fixedSize(horizontal: false, vertical: true)
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
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

/// 数据说明卡:数据时间 / 真实模式 / 来源端点 / 计算口径 / 非投资建议。财务与行业模块页脚必带。
struct ProvenanceCard: View {
    let dataTime: String
    let endpoints: [String]
    let methodology: String
    @Environment(\.l10n) private var l10n

    var body: some View {
        SectionCard(title: l10n.dataProvenance) {
            Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text(l10n.dataTime).font(.caption).foregroundStyle(Theme.muted)
                    Text(dataTime).font(.caption.monospacedDigit()).foregroundStyle(Theme.text)
                }
                GridRow {
                    Text(l10n.dataMode).font(.caption).foregroundStyle(Theme.muted)
                    Text(l10n.dataModeReal).font(.caption).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                }
                GridRow {
                    Text(l10n.sourceEndpoints).font(.caption).foregroundStyle(Theme.muted)
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(endpoints, id: \.self) { endpoint in
                            Text(endpoint).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.text).textSelection(.enabled)
                        }
                    }
                }
                GridRow {
                    Text(l10n.methodology).font(.caption).foregroundStyle(Theme.muted)
                    Text(methodology).font(.caption).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(l10n.notAdvice)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.accentStrong)
                .padding(.top, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 「值 / 缺失」文本:nil 显示为「—」,不补零。
struct ValueText: View {
    let text: String?
    var color: Color = Theme.text

    var body: some View {
        Text(text ?? "—")
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(text == nil ? Theme.disabled : color)
    }
}

/// 常用格式:比率 → 百分数 / 倍数,nil 透传。
enum RatioFormat {
    static func percent(_ value: Double?) -> String? { value.map { RiskReport.percent($0) } }
    static func times(_ value: Double?) -> String? { value.map { NumberFormat.number($0) + "×" } }
    static func yuan(_ value: Double?) -> String? { value.map(MoneyFormat.yuan) }
    static func number(_ value: Double?) -> String? { value.map(NumberFormat.number) }
    static func day(_ ms: Int64?) -> String? { ms.map { ShanghaiDate.string(Date(timeIntervalSince1970: Double($0) / 1000)) } }
}
