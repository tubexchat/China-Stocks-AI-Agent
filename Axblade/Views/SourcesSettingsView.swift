import SwiftUI

/// 设置 → 数据源:7 个源按类别分组,逐个启用/禁用。
struct SourcesSettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Form {
            Section(viewModel.text.cryptoSection) {
                ForEach(MarketSourceKind.allCases.filter(\.isCrypto), id: \.self, content: row)
            }
            Section(viewModel.text.equitySection) {
                ForEach(MarketSourceKind.allCases.filter { !$0.isCrypto }, id: \.self, content: row)
            }
            Section {
                Text(viewModel.text.sourcesFooter)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
    }

    private func row(_ kind: MarketSourceKind) -> some View {
        Toggle(viewModel.text.sourceName(kind), isOn: Binding(
            get: { !viewModel.settings.disabledSources.contains(kind) },
            set: { viewModel.setSource(kind, enabled: $0) }
        ))
    }
}
