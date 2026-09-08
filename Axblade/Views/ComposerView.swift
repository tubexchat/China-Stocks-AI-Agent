import SwiftUI

/// 底部输入卡:8px 圆角的悬浮卡片(Binance 主题不用 pill),上方输入框,
/// 下方一行「+ 数据源 | 模型标签 | 发送/停止」。
struct ComposerView: View {
    @ObservedObject var viewModel: AppViewModel
    @FocusState private var focused: Bool

    @State private var attachmentSource: MarketSourceKind?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !viewModel.isSignedIn { signInBanner }
            card
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .sheet(item: $attachmentSource) { source in
            AttachmentSheet(viewModel: viewModel, source: source) {
                attachmentSource = nil
            }
        }
    }

    /// 未登录:AI 与行情代理都会被后端挡下,先在输入卡上方说清楚。
    private var signInBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .foregroundStyle(Theme.accentStrong)
            Text(viewModel.text.signInBanner)
                .font(.callout)
                .foregroundStyle(Theme.text)
            Spacer()
            SettingsLink {
                Text(viewModel.text.openAccountSettings)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Theme.accentStrong)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.accent.opacity(0.5), lineWidth: 1))
        .padding(.bottom, 8)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !viewModel.pendingAttachments.isEmpty {
                attachmentChips
            }

            TextField(viewModel.text.askPlaceholder, text: $viewModel.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(Theme.text)
                .lineLimit(1...8)
                .focused($focused)
                .onSubmit(viewModel.send)

            HStack(spacing: 12) {
                sourceMenu
                Spacer()
                modelMenu
                actionButton
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(Theme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
        .onAppear { focused = true }
    }

    /// “+”:数据源菜单(分组只列启用的源)。
    private var sourceMenu: some View {
        Menu {
            let crypto = viewModel.enabledSources.filter(\.isCrypto)
            let equity = viewModel.enabledSources.filter { !$0.isCrypto }
            if crypto.isEmpty && equity.isEmpty {
                Text(viewModel.text.noEnabledSources)
            }
            if !crypto.isEmpty {
                Section(viewModel.text.cryptoSection) {
                    ForEach(crypto, id: \.self) { source in
                        Button(viewModel.text.sourceName(source)) { attachmentSource = source }
                    }
                }
            }
            if !equity.isEmpty {
                Section(viewModel.text.equitySection) {
                    ForEach(equity, id: \.self) { source in
                        Button(viewModel.text.sourceName(source)) { attachmentSource = source }
                    }
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.muted)
                .frame(width: 28, height: 28)
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(viewModel.text.attachHelp)
    }

    private var attachmentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.pendingAttachments) { snapshot in
                    HStack(spacing: 5) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 10))
                        Text(snapshot.chipText)
                            .font(.caption.weight(.medium))
                        Button {
                            viewModel.removeAttachment(id: snapshot.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.accent.opacity(0.5), lineWidth: 1))
                }
            }
        }
    }

    /// 模型标签:右下角那种纯文字选择器,只在账户有权限的模型之间切换。
    private var modelMenu: some View {
        Menu {
            ForEach(viewModel.availableModels) { model in
                Button {
                    viewModel.selectModel(model.alias)
                } label: {
                    if model.alias == viewModel.currentModel.alias {
                        Label(model.displayName, systemImage: "checkmark")
                    } else {
                        Text(model.displayName)
                    }
                }
            }
        } label: {
            Text(viewModel.currentModel.displayName)
                .font(.callout)
                .foregroundStyle(Theme.muted)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
    }

    @ViewBuilder
    private var actionButton: some View {
        if viewModel.isStreaming {
            Button(action: viewModel.stopStreaming) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 30, height: 30)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .help(viewModel.text.stopHelp)
        } else {
            Button(action: viewModel.send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(canSend ? Theme.onAccent : Theme.disabled)
                    .frame(width: 30, height: 30)
                    .background(canSend ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.elevated))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .help(viewModel.text.sendHelp)
        }
    }

    private var canSend: Bool {
        !viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !viewModel.pendingAttachments.isEmpty
    }
}
