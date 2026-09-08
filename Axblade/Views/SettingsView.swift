import SwiftUI

/// 设置窗口:通用 / 账户 / 模型服务 / 数据源 四个标签。
struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        TabView {
            GeneralSettingsView(viewModel: viewModel)
                .tabItem { Label(viewModel.text.settingsGeneral, systemImage: "gearshape") }
            AccountSettingsView(viewModel: viewModel)
                .tabItem { Label(viewModel.text.settingsAccount, systemImage: "person.crop.circle") }
            ModelsSettingsView(viewModel: viewModel)
                .tabItem { Label(viewModel.text.settingsModels, systemImage: "sparkles") }
            SourcesSettingsView(viewModel: viewModel)
                .tabItem { Label(viewModel.text.settingsSources, systemImage: "chart.line.uptrend.xyaxis") }
        }
        .frame(width: 760, height: 500)
        .background(Theme.background)
    }
}

/// 通用标签页:界面语言切换,选完即时生效。
struct GeneralSettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Form {
            Picker(viewModel.text.languageLabel, selection: Binding(
                get: { viewModel.settings.language },
                set: { viewModel.selectLanguage($0) }
            )) {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .pickerStyle(.inline)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
    }
}

/// 模型服务标签页:只在官方后端的固定模型间单选。
/// 所有请求经由官方后端转发,客户端不保存、不需要任何 API Key。
struct ModelsSettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Form {
            Section(viewModel.text.modelSectionHeader) {
                ForEach(viewModel.availableModels) { model in
                    Button {
                        viewModel.selectModel(model.alias)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.displayName)
                                    .foregroundStyle(Theme.text)
                                Text(model.alias)
                                    .font(.caption)
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            if viewModel.currentModel.alias == model.alias {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                Text(viewModel.text.modelFooter)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
    }
}
