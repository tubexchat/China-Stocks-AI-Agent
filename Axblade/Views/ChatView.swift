import SwiftUI

/// 右侧聊天区:消息流 + 悬浮输入卡。空会话时显示问候页。
/// 背景自上而下渐入极淡的品牌黄(Binance 主题,不再用青色光晕)。
struct ChatView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            if let conversation = viewModel.current, !conversation.messages.isEmpty {
                transcript(conversation)
            } else {
                EmptyStateView { suggestion in
                    viewModel.draft = suggestion
                    viewModel.send()
                }
            }

            ComposerView(viewModel: viewModel)
        }
        .background(
            LinearGradient(
                stops: [
                    .init(color: Theme.background, location: 0),
                    .init(color: Theme.background, location: 0.8),
                    .init(color: Theme.accentSoft, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .navigationTitle(viewModel.current?.title ?? viewModel.text.appName)
    }

    private func transcript(_ conversation: Conversation) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(conversation.messages) { message in
                        MessageRow(
                            message: message,
                            isStreaming: viewModel.isStreaming && message.id == conversation.messages.last?.id
                        )
                        .id(message.id)
                    }
                    // 滚动锚点:流式追加时始终把最新内容顶到视野里。
                    Color.clear.frame(height: 1).id(Self.bottomAnchor)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: 860, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: conversation.messages.last?.content) { _, _ in
                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
            }
            .onChange(of: conversation.id) { _, _ in
                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
            }
        }
    }

    private static let bottomAnchor = "axblade.transcript.bottom"
}
