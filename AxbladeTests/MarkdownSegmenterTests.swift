import XCTest
@testable import Axblade

final class MarkdownSegmenterTests: XCTestCase {
    func testPlainProseIsOneTextSegment() {
        XCTAssertEqual(
            MarkdownSegmenter.segments(from: "第一行\n第二行"),
            [.text("第一行\n第二行")]
        )
    }

    func testFencedBlockSplitsProseFromCode() {
        let markdown = """
        先看代码:
        ```swift
        let x = 1
        ```
        就这样。
        """

        XCTAssertEqual(MarkdownSegmenter.segments(from: markdown), [
            .text("先看代码:"),
            .code(language: "swift", content: "let x = 1"),
            .text("就这样。")
        ])
    }

    func testFenceWithoutLanguageHasNoLanguage() {
        XCTAssertEqual(
            MarkdownSegmenter.segments(from: "```\nplain\n```"),
            [.code(language: nil, content: "plain")]
        )
    }

    /// 流式输出时代码块经常只写了一半,不能因为没收尾就把它当普通文字。
    func testUnterminatedFenceStillRendersAsCode() {
        XCTAssertEqual(
            MarkdownSegmenter.segments(from: "开始\n```python\nprint(1)"),
            [.text("开始"), .code(language: "python", content: "print(1)")]
        )
    }

    func testEmptySegmentsAreDropped() {
        XCTAssertEqual(
            MarkdownSegmenter.segments(from: "```swift\nlet x = 1\n```\n\n"),
            [.code(language: "swift", content: "let x = 1")]
        )
        XCTAssertEqual(MarkdownSegmenter.segments(from: "   "), [])
    }

    func testConsecutiveBlocksKeepTheirOrder() {
        let markdown = "```a\n1\n```\n```b\n2\n```"

        XCTAssertEqual(MarkdownSegmenter.segments(from: markdown), [
            .code(language: "a", content: "1"),
            .code(language: "b", content: "2")
        ])
    }

    func testIndentedFenceIsStillAFence() {
        XCTAssertEqual(
            MarkdownSegmenter.segments(from: "  ```swift\n  let x = 1\n  ```"),
            [.code(language: "swift", content: "  let x = 1")]
        )
    }
}
