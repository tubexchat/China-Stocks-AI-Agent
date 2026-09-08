import SwiftUI

/// 消息正文渲染:``` 围栏里的内容做成可复制的代码卡片,其余散文再切成
/// 标题 / 列表 / 引用 / 分割线 / 表格 / 段落分别排版,段落内的行内 Markdown
/// (粗体、斜体、行内代码、链接)交给 `AttributedString`。
struct MarkdownText: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(MarkdownSegmenter.segments(from: content).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let prose):
                    ForEach(Array(MarkdownBlockParser.blocks(from: prose).enumerated()), id: \.offset) { _, block in
                        MarkdownBlockView(block: block)
                    }
                case .code(let language, let code):
                    CodeBlock(language: language, code: code)
                }
            }
        }
    }

    /// 只解析行内语法并保留换行 —— 整段解析会把软换行吃掉,聊天里读起来会粘成一坨。
    static func inlineMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

// MARK: - 块级排版

private struct MarkdownBlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(MarkdownText.inlineMarkdown(text))
                .font(Self.headingFont(level))
                .foregroundStyle(Theme.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, level <= 2 ? 6 : 2)
        case .paragraph(let text):
            Text(MarkdownText.inlineMarkdown(text))
                .foregroundStyle(Theme.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .list(let ordered, let start, let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(Self.marker(ordered: ordered, start: start, offset: offset, items: items, depth: item.depth))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(ordered ? Theme.muted : Theme.accent)
                            .frame(minWidth: ordered ? 22 : 10, alignment: .trailing)
                        Text(MarkdownText.inlineMarkdown(item.text))
                            .foregroundStyle(Theme.text)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(item.depth) * 18)
                }
            }
        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Theme.accent)
                    .frame(width: 3)
                Text(MarkdownText.inlineMarkdown(text))
                    .foregroundStyle(Theme.muted)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
        case .rule:
            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)
                .padding(.vertical, 4)
        case .table(let header, let rows):
            MarkdownTable(header: header, rows: rows)
        }
    }

    private static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title2.weight(.bold)
        case 2: .title3.weight(.semibold)
        case 3: .headline
        default: .subheadline.weight(.semibold)
        }
    }

    /// 无序列表按深度换符号;有序列表按同一深度连续编号。
    private static func marker(ordered: Bool, start: Int, offset: Int,
                               items: [MarkdownBlock.ListItem], depth: Int) -> String {
        guard ordered else { return depth == 0 ? "•" : (depth == 1 ? "◦" : "▪") }
        let sameDepthBefore = items.prefix(offset).filter { $0.depth == depth }.count
        return "\(start + sameDepthBefore)."
    }
}

/// GFM 表格:表头加粗、行间细线、数字等宽,超宽时横向滚动。
private struct MarkdownTable: View {
    let header: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                        cellView(cell, isHeader: true)
                    }
                }
                .background(Theme.surface2)
                Divider().gridCellUnsizedAxes(.horizontal).overlay(Theme.border)
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(0..<header.count, id: \.self) { column in
                            cellView(column < row.count ? row[column] : "", isHeader: false)
                        }
                    }
                    if rowIndex < rows.count - 1 {
                        Divider().gridCellUnsizedAxes(.horizontal).overlay(Theme.border.opacity(0.6))
                    }
                }
            }
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
        }
    }

    private func cellView(_ text: String, isHeader: Bool) -> some View {
        Text(MarkdownText.inlineMarkdown(text))
            .font(isHeader ? .callout.weight(.semibold) : .callout.monospacedDigit())
            .foregroundStyle(isHeader ? Theme.text : Theme.text)
            .textSelection(.enabled)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 复制按钮(代码块 / 整条消息共用)

/// 点一下把文本放进剪贴板,1.5 秒内显示「已复制 ✓」。
struct CopyButton: View {
    let text: String
    var compact = false

    @Environment(\.l10n) private var l10n
    @State private var copied = false

    var body: some View {
        Button(action: copy) {
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                if !compact {
                    Text(copied ? l10n.copied : l10n.copy)
                }
            }
            .font(.caption)
        }
        .buttonStyle(.plain)
        .foregroundStyle(copied ? Theme.accent : Theme.muted)
        .help(l10n.copy)
        .accessibilityLabel(copied ? l10n.copied : l10n.copy)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

private struct CodeBlock: View {
    let language: String?
    let code: String

    @Environment(\.l10n) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? l10n.codeBlockFallback)
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.muted)
                Spacer()
                CopyButton(text: code)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.surface2)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
    }
}

#Preview {
    MarkdownText(content: """
    ## 3. 均线与关键位置
    粗略估算几个短期均线:

    - MA5 ≈ 63,567
    - MA10 ≈ 63,728
      - 子项

    ### 上方阻力
    | 区间 | 说明 |
    |---|---|
    | 64,600–64,700 | 日内高点 |

    > 仅供研究参考

    ```swift
    let answer = 42
    ```
    """)
    .padding()
    .background(Theme.background)
}
