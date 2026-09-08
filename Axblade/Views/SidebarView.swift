import SwiftUI

/// 侧栏(Gemini 范式):搜索框、「发起新对话」、会话列表(只显标题)、底部设置入口。
struct SidebarView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var searchText = ""
    @State private var renamingID: UUID?
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 0) {
            workspacePicker
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)

            if viewModel.workspace == .home {
                homeContent
            } else {
                toolsContent
            }

            bottomBar
        }
        .background(Theme.sidebar)
        .alert(viewModel.text.renameAlertTitle, isPresented: Binding(
            get: { renamingID != nil },
            set: { if !$0 { renamingID = nil } }
        )) {
            TextField(viewModel.text.renameFieldPlaceholder, text: $renameText)
            Button(viewModel.text.cancel, role: .cancel) { renamingID = nil }
            Button(viewModel.text.save) {
                if let id = renamingID { viewModel.renameConversation(id, to: renameText) }
                renamingID = nil
            }
        }
    }

    /// 空会话不进列表(Gemini 行为):它的入口就是高亮的「发起新对话」。
    /// 侧栏顶部的 Home | Tools 分段(参考稿:灰色容器 + 选中段白色凸起胶囊)。
    private var workspacePicker: some View {
        HStack(spacing: 2) {
            workspaceSegment(.home, title: "Home", icon: "house")
            workspaceSegment(.tools, title: "Tools", icon: "wrench.and.screwdriver")
        }
        .padding(3)
        .background(Theme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func workspaceSegment(_ workspace: Workspace, title: String, icon: String) -> some View {
        let isSelected = viewModel.workspace == workspace
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                viewModel.workspace = workspace
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(.callout.weight(isSelected ? .medium : .regular))
            }
            .foregroundStyle(isSelected ? Theme.text : Theme.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(isSelected ? Theme.background : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1)
                }
            }
            .shadow(color: isSelected ? .black.opacity(0.08) : .clear, radius: 2, y: 1)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var homeContent: some View {
        searchField
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 6)

        newChatRow
            .padding(.horizontal, 8)

        List(selection: $viewModel.selectedID) {
            Section {
                ForEach(visibleConversations) { conversation in
                    row(conversation)
                        .tag(conversation.id)
                        .listRowBackground(rowBackground(for: conversation.id))
                        .contextMenu {
                            Button(viewModel.text.rename) { startRenaming(conversation) }
                            Button(viewModel.text.delete, role: .destructive) {
                                viewModel.deleteConversation(conversation.id)
                            }
                        }
                }
            } header: {
                Text(viewModel.text.conversationsHeader)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    /// Tools 模式:侧栏列工具清单。
    @ViewBuilder
    private var toolsContent: some View {
        List(selection: $viewModel.selectedTool) {
            Section {
                ForEach(QuantTool.allCases) { tool in
                    Label(viewModel.text.toolName(tool), systemImage: tool.icon)
                        .font(.callout)
                        .foregroundStyle(Theme.text)
                        .padding(.vertical, 3)
                        .tag(tool)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(tool == viewModel.selectedTool ? Theme.elevated : .clear)
                        )
                }
            } header: {
                Text(viewModel.text.quantToolsHeader)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private var visibleConversations: [Conversation] {
        viewModel.conversations.filter { !$0.messages.isEmpty }.filtered(by: searchText)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            TextField(viewModel.text.search, text: $searchText)
                .textFieldStyle(.plain)
                .font(.callout)
                .foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Theme.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
    }

    private var newChatRow: some View {
        Button(action: viewModel.newConversation) {
            Label(viewModel.text.newChat, systemImage: "square.and.pencil")
                .font(.callout)
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(onEmptyConversation ? Theme.elevated : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(viewModel.text.newChatHelp)
    }

    /// 正站在一个空会话上,说明「发起新对话」就是当前状态,给它选中底色。
    private var onEmptyConversation: Bool {
        viewModel.current?.messages.isEmpty == true
    }

    private func row(_ conversation: Conversation) -> some View {
        Text(conversation.title)
            .font(.callout)
            .lineLimit(1)
            .foregroundStyle(Theme.text)
            .padding(.vertical, 4)
    }

    private func rowBackground(for id: UUID) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(id == viewModel.selectedID ? Theme.elevated : .clear)
    }

    private var bottomBar: some View {
        HStack(spacing: 9) {
            if viewModel.isSignedIn, let account = viewModel.account {
                AccountAvatar(
                    displayName: account.email.isEmpty ? account.displayName : account.email,
                    avatarURL: viewModel.me?.user.avatar_url,
                    size: 22
                )
                Text(account.email.isEmpty ? account.displayName : account.email)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(Theme.text)
                PlanBadge(plan: account.plan)
            } else {
                BrandMark(size: 20, filled: true)
                Text(viewModel.text.notSignedIn)
                    .font(.callout)
                    .foregroundStyle(Theme.muted)
            }
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

    private func startRenaming(_ conversation: Conversation) {
        renameText = conversation.title
        renamingID = conversation.id
    }
}
