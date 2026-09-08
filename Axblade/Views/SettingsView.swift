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
            DataSettingsView(viewModel: viewModel)
                .tabItem { Label(viewModel.text.settingsData, systemImage: "cylinder.split.1x2") }
        }
        .frame(width: 760, height: 520)
        .background(Theme.background)
    }
}

/// 通用标签页:界面语言 + 智能体自动附带实时数据。
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

            Section {
                Toggle(viewModel.text.agentAutoContextLabel, isOn: Binding(
                    get: { viewModel.settings.agentAutoContext },
                    set: { viewModel.settings.agentAutoContext = $0 }
                ))
                Text(viewModel.text.agentAutoContextHint)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
    }
}

/// 模型服务标签页:只在官方后端的固定模型间单选。
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

/// 数据源标签页:同花顺金融数据 API Key(钥匙串)+ 本地研究缓存。
struct DataSettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var keyDraft = ""
    @State private var usingBuiltIn = FuyaoKeyStore.isUsingBuiltIn
    @State private var testResult: String?
    @State private var isTesting = false

    private var text: L10nStrings { viewModel.text }

    var body: some View {
        Form {
            Section(text.dataKeyHeader) {
                HStack(spacing: 8) {
                    SecureField(text.dataKeyPlaceholder, text: $keyDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveKey)
                    Button(text.save, action: saveKey)
                        .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                HStack(spacing: 10) {
                    Text(usingBuiltIn ? text.dataKeyUsingBuiltIn : text.dataKeyUsingCustom)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    if !usingBuiltIn {
                        Button(text.dataKeyReset) {
                            FuyaoKeyStore.set(nil)
                            usingBuiltIn = true
                        }
                        .controlSize(.small)
                    }
                    Button(text.dataKeyTest, action: testConnection)
                        .controlSize(.small)
                        .disabled(isTesting)
                }
                if let testResult {
                    Text(testResult)
                        .font(.caption)
                        .foregroundStyle(testResult.hasPrefix("✓") ? Theme.success : Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                HStack {
                    Text(String(format: text.researchCacheFormat, ByteCountFormatter.string(fromByteCount: viewModel.marketTrend.cacheBytes, countStyle: .file)))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Button(text.clearCache) { viewModel.marketTrend.clearCache() }
                        .controlSize(.small)
                }
                Text(text.dataKeyFooter)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
    }

    private func saveKey() {
        guard FuyaoKeyStore.set(keyDraft) else { return }
        keyDraft = ""
        usingBuiltIn = FuyaoKeyStore.isUsingBuiltIn
        testResult = nil
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        Task { @MainActor in
            do {
                let days = try await viewModel.data.tradingDays()
                testResult = "✓ " + String(format: text.dataKeyTestOKFormat, days.count)
            } catch {
                testResult = text.describe(error)
            }
            isTesting = false
        }
    }
}
