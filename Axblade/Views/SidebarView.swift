import SwiftUI

/// 侧栏:品牌 + 五个盘面模块清单 + 底部设置入口。
struct SidebarView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            brandHeader
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 6)

            List(selection: $viewModel.selectedModule) {
                Section {
                    ForEach(AgentModule.allCases) { module in
                        Label(viewModel.text.moduleName(module), systemImage: module.icon)
                            .font(.callout)
                            .foregroundStyle(Theme.text)
                            .padding(.vertical, 3)
                            .tag(module)
                            .listRowBackground(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(module == viewModel.selectedModule ? Theme.elevated : .clear)
                            )
                    }
                } header: {
                    Text(viewModel.text.modulesHeader)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            bottomBar
        }
        .background(Theme.sidebar)
    }

    private var brandHeader: some View {
        Button {
            viewModel.selectedModule = nil
        } label: {
            HStack(spacing: 9) {
                BrandMark(size: 24, filled: true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(viewModel.text.appName)
                        .font(.headline)
                        .foregroundStyle(Theme.text)
                    Text(viewModel.text.appTagline)
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(viewModel.text.backToModules)
    }

    private var bottomBar: some View {
        HStack(spacing: 9) {
            Image(systemName: "cylinder.split.1x2")
                .foregroundStyle(Theme.muted)
            Text(viewModel.text.dataSourceBadge)
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            Spacer()
            SettingsLink {
                Image(systemName: "gearshape")
                    .foregroundStyle(Theme.muted)
            }
            .buttonStyle(.plain)
            .help(viewModel.text.settingsHelp)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}
