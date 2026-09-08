import SwiftUI

/// 一条消息。用户消息右对齐气泡,AI 消息左侧带标志、全宽铺开(Claude 那套)。
struct MessageRow: View {
    let message: ChatMessage
    var isStreaming = false

    var body: some View {
        switch message.role {
        case .user:
            userBubble
        case .assistant, .system:
            assistantBlock
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 60)
            Text(message.content)
                .textSelection(.enabled)
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var assistantBlock: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.isError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.down)
                    .frame(width: 24, height: 24)
            } else {
                BrandMark(size: 24)
            }

            VStack(alignment: .leading, spacing: 8) {
                if message.isError {
                    Text(message.content)
                        .textSelection(.enabled)
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    MarkdownText(content: message.content)
                }
                if isStreaming {
                    StreamingCursor()
                } else if !message.isError && !message.content.isEmpty {
                    // 回答底部的复制按钮:复制原始 Markdown 全文
                    CopyButton(text: message.content)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(message.isError ? 12 : 0)
            .background(message.isError ? Theme.down.opacity(0.08) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                if message.isError {
                    RoundedRectangle(cornerRadius: 8).stroke(Theme.down.opacity(0.55), lineWidth: 1)
                }
            }
        }
    }
}

/// 生成中的光标块。
private struct StreamingCursor: View {
    @Environment(\.l10n) private var l10n
    @State private var on = true

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Theme.accent)
            .frame(width: 9, height: 16)
            .opacity(on ? 1 : 0.15)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: on)
            .onAppear { on.toggle() }
            .accessibilityLabel(l10n.generating)
    }
}

#Preview {
    VStack(spacing: 20) {
        MessageRow(message: ChatMessage(role: .user, content: "帮我解释一下 actor"))
        MessageRow(message: ChatMessage(role: .assistant, content: "**actor** 是 Swift 的并发隔离域。"), isStreaming: true)
        MessageRow(message: ChatMessage(role: .assistant, content: "请先在 设置 → 模型服务 中配置 API Key", isError: true))
    }
    .padding()
    .background(Theme.background)
}
