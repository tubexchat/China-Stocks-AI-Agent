import Foundation

/// 块级 Markdown 结构。行内语法(粗体、行内代码、链接)不在这里处理,交给 `AttributedString`。
enum MarkdownBlock: Equatable, Sendable {
    struct ListItem: Equatable, Sendable {
        var text: String
        /// 嵌套深度,0 = 顶层。每 2 个及以上空格(或一个 tab)算一层。
        var depth: Int
    }

    case heading(level: Int, text: String)
    case paragraph(String)
    case list(ordered: Bool, start: Int, items: [ListItem])
    case quote(String)
    case rule
    case table(header: [String], rows: [[String]])
}

/// 把一段散文(已经由 `MarkdownSegmenter` 摘掉代码块)切成块。
/// 设计目标是「模型输出的常见 Markdown 都能看」而不是完整规范:
/// 标题、无序/有序列表(带嵌套)、引用、分割线、GFM 表格、段落(保留软换行)。
/// 任何半截输入都按段落兜底,流式渲染时不会崩、不会丢字。
enum MarkdownBlockParser {
    static func blocks(from text: String) -> [MarkdownBlock] {
        let lines = text.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }
            if let heading = parseHeading(trimmed) {
                blocks.append(heading)
                index += 1
                continue
            }
            if isRule(trimmed) {
                blocks.append(.rule)
                index += 1
                continue
            }
            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    quoteLines.append(String(candidate.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(.quote(quoteLines.joined(separator: "\n")))
                continue
            }
            if let table = parseTable(lines, from: index) {
                blocks.append(table.block)
                index = table.nextIndex
                continue
            }
            if let (_, ordered, start) = listMarker(line) {
                var items: [MarkdownBlock.ListItem] = []
                while index < lines.count {
                    let candidate = lines[index]
                    if let (item, itemOrdered, _) = listMarker(candidate), itemOrdered == ordered {
                        items.append(item)
                        index += 1
                    } else if !candidate.trimmingCharacters(in: .whitespaces).isEmpty,
                              candidate.hasPrefix("  "), var last = items.popLast() {
                        // 缩进续行:并入上一项
                        last.text += "\n" + candidate.trimmingCharacters(in: .whitespaces)
                        items.append(last)
                        index += 1
                    } else {
                        break
                    }
                }
                blocks.append(.list(ordered: ordered, start: start, items: items))
                continue
            }

            // 段落:直到空行或下一个块级标记
            var paragraph: [String] = [trimmed]
            index += 1
            while index < lines.count {
                let candidate = lines[index]
                let candidateTrimmed = candidate.trimmingCharacters(in: .whitespaces)
                if candidateTrimmed.isEmpty || parseHeading(candidateTrimmed) != nil || isRule(candidateTrimmed)
                    || candidateTrimmed.hasPrefix(">") || listMarker(candidate) != nil
                    || parseTable(lines, from: index) != nil {
                    break
                }
                paragraph.append(candidateTrimmed)
                index += 1
            }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
        }

        return blocks.isEmpty ? [.paragraph(text)] : blocks
    }

    // MARK: - 标题 / 分割线

    private static func parseHeading(_ trimmed: String) -> MarkdownBlock? {
        var level = 0
        var rest = Substring(trimmed)
        while rest.first == "#" {
            level += 1
            rest = rest.dropFirst()
        }
        guard (1...6).contains(level), rest.first == " " else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return .heading(level: level, text: text)
    }

    private static func isRule(_ trimmed: String) -> Bool {
        let compact = trimmed.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    // MARK: - 列表

    /// 返回 (条目, 是否有序, 起始序号);不是列表行返回 nil。
    private static func listMarker(_ line: String) -> (MarkdownBlock.ListItem, Bool, Int)? {
        let expanded = line.replacingOccurrences(of: "\t", with: "  ")
        let leading = expanded.prefix { $0 == " " }.count
        let body = expanded.dropFirst(leading)
        let depth = leading / 2

        if let first = body.first, "-*+".contains(first) {
            let after = body.dropFirst()
            guard let next = after.first, next == " " else { return nil }
            let text = after.trimmingCharacters(in: .whitespaces)
            return (.init(text: text, depth: depth), false, 1)
        }

        let digits = body.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 9, let number = Int(digits) else { return nil }
        let afterDigits = body.dropFirst(digits.count)
        guard let punct = afterDigits.first, punct == "." || punct == ")" else { return nil }
        let after = afterDigits.dropFirst()
        guard let next = after.first, next == " " else { return nil }
        let text = after.trimmingCharacters(in: .whitespaces)
        return (.init(text: text, depth: depth), true, number)
    }

    // MARK: - 表格

    private static func parseTable(_ lines: [String], from index: Int) -> (block: MarkdownBlock, nextIndex: Int)? {
        guard index + 1 < lines.count else { return nil }
        guard let header = tableCells(lines[index]), isTableSeparator(lines[index + 1]) else { return nil }
        var rows: [[String]] = []
        var cursor = index + 2
        while cursor < lines.count, let cells = tableCells(lines[cursor]) {
            rows.append(cells)
            cursor += 1
        }
        return (.table(header: header, rows: rows), cursor)
    }

    /// `| a | b |` → ["a", "b"];不含 `|` 的行不是表格行。
    private static func tableCells(_ line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return nil }
        var inner = Substring(trimmed)
        if inner.hasPrefix("|") { inner = inner.dropFirst() }
        if inner.hasSuffix("|") { inner = inner.dropLast() }
        let cells = inner.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return cells.isEmpty ? nil : cells
    }

    /// `|---|:---:|` 这类分隔行。
    private static func isTableSeparator(_ line: String) -> Bool {
        guard let cells = tableCells(line), !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let core = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return core.count >= 3 && core.allSatisfy { $0 == "-" }
        }
    }
}
