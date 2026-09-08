import XCTest
@testable import Axblade

/// 块级 Markdown:标题 / 列表 / 引用 / 分割线 / 表格 / 段落。
/// 行内语法(粗体、行内代码)不在这里解析,交给 AttributedString。
final class MarkdownBlockParserTests: XCTestCase {
    func testHeadingsAndParagraph() {
        let blocks = MarkdownBlockParser.blocks(from: "## 3. 均线与关键位置\n粗略估算几个短期均线:")
        XCTAssertEqual(blocks, [
            .heading(level: 2, text: "3. 均线与关键位置"),
            .paragraph("粗略估算几个短期均线:")
        ])
    }

    func testHeadingLevelIsClampedAndHashOnlyLineIsParagraph() {
        XCTAssertEqual(MarkdownBlockParser.blocks(from: "####### 七个井号"), [.paragraph("####### 七个井号")])
        XCTAssertEqual(MarkdownBlockParser.blocks(from: "#没有空格"), [.paragraph("#没有空格")])
        XCTAssertEqual(MarkdownBlockParser.blocks(from: "###### 六级"), [.heading(level: 6, text: "六级")])
    }

    func testBulletListWithTrailingSpacesAndNesting() {
        let md = """
        - MA5 ≈ 63,567  
        - MA10 ≈ 63,728
          - 子项 A
          * 子项 B
        - MA20 ≈ 63,892
        """
        XCTAssertEqual(MarkdownBlockParser.blocks(from: md), [
            .list(ordered: false, start: 1, items: [
                .init(text: "MA5 ≈ 63,567", depth: 0),
                .init(text: "MA10 ≈ 63,728", depth: 0),
                .init(text: "子项 A", depth: 1),
                .init(text: "子项 B", depth: 1),
                .init(text: "MA20 ≈ 63,892", depth: 0)
            ])
        ])
    }

    func testOrderedListKeepsStartNumber() {
        let md = "3. 第三\n4. 第四\n5) 第五"
        XCTAssertEqual(MarkdownBlockParser.blocks(from: md), [
            .list(ordered: true, start: 3, items: [
                .init(text: "第三", depth: 0), .init(text: "第四", depth: 0), .init(text: "第五", depth: 0)
            ])
        ])
    }

    func testBlankLineSeparatesParagraphsButSoftBreaksAreKept() {
        let md = "第一段第一行\n第一段第二行\n\n第二段"
        XCTAssertEqual(MarkdownBlockParser.blocks(from: md), [
            .paragraph("第一段第一行\n第一段第二行"),
            .paragraph("第二段")
        ])
    }

    func testBlockquoteAndRule() {
        let md = "> 仅供研究参考\n> 不构成投资建议\n---\n后面"
        XCTAssertEqual(MarkdownBlockParser.blocks(from: md), [
            .quote("仅供研究参考\n不构成投资建议"),
            .rule,
            .paragraph("后面")
        ])
        XCTAssertEqual(MarkdownBlockParser.blocks(from: "***"), [.rule])
        XCTAssertEqual(MarkdownBlockParser.blocks(from: "* * *"), [.rule])
    }

    func testGFMTable() {
        let md = """
        | 区间 | 说明 |
        |---|:---:|
        | 64,600–64,700 | 日内高点 |
        | 65,000–65,400 | 密集成交区 |
        """
        XCTAssertEqual(MarkdownBlockParser.blocks(from: md), [
            .table(header: ["区间", "说明"], rows: [
                ["64,600–64,700", "日内高点"],
                ["65,000–65,400", "密集成交区"]
            ])
        ])
    }

    func testTableWithoutSeparatorIsParagraph() {
        XCTAssertEqual(MarkdownBlockParser.blocks(from: "| a | b |\n| c | d |"), [.paragraph("| a | b |\n| c | d |")])
    }

    func testListFollowedByHeadingSplitsCorrectly() {
        let md = """
        ### 上方阻力
        - 64,600–64,700:日内高点
        - 66,500:30日收盘高点附近

        ### 下方支撑
        - 63,800:MA20
        """
        let blocks = MarkdownBlockParser.blocks(from: md)
        XCTAssertEqual(blocks.count, 4)
        XCTAssertEqual(blocks[0], .heading(level: 3, text: "上方阻力"))
        XCTAssertEqual(blocks[2], .heading(level: 3, text: "下方支撑"))
        if case .list(_, _, let items) = blocks[3] { XCTAssertEqual(items.map(\.text), ["63,800:MA20"]) } else { XCTFail("expected list") }
    }

    /// 流式输出中途:半截标题/列表也不能崩,按段落兜底。
    func testPartialInputNeverThrowsAndNeverLosesText() {
        for prefix in ["#", "# ", "-", "- ", "1", "1.", "|", "| a", "> ", "```"] {
            let blocks = MarkdownBlockParser.blocks(from: prefix)
            XCTAssertFalse(blocks.isEmpty || blocks == [.paragraph("")], "prefix \(prefix) → \(blocks)")
        }
    }
}
