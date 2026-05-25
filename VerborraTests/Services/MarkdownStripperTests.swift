import XCTest
@testable import Verborra

final class MarkdownStripperTests: XCTestCase {

    func testPlainTextPassesThrough() {
        let input = "Hello world"
        let result = MarkdownStripper.stripMarkdown(input)
        XCTAssertEqual(result, "Hello world")
    }

    func testStripsHeadings() {
        let input = "# Heading 1\n\nSome text"
        let result = MarkdownStripper.stripMarkdown(input)
        XCTAssertTrue(result.contains("Heading 1"))
        XCTAssertTrue(result.contains("Some text"))
        XCTAssertFalse(result.contains("#"))
    }

    func testStripsBoldAndItalic() {
        let input = "This is **bold** and *italic* text"
        let result = MarkdownStripper.stripMarkdown(input)
        XCTAssertTrue(result.contains("bold"))
        XCTAssertTrue(result.contains("italic"))
        XCTAssertFalse(result.contains("**"))
        XCTAssertFalse(result.contains("*italic*"))
    }

    func testStripsLists() {
        let input = "- Item 1\n- Item 2\n- Item 3"
        let result = MarkdownStripper.stripMarkdown(input)
        XCTAssertTrue(result.contains("Item 1"))
        XCTAssertTrue(result.contains("Item 2"))
        XCTAssertTrue(result.contains("Item 3"))
    }

    func testStripsLinks() {
        let input = "Visit [Google](https://google.com) for search"
        let result = MarkdownStripper.stripMarkdown(input)
        XCTAssertTrue(result.contains("Google"))
        XCTAssertTrue(result.contains("for search"))
        XCTAssertFalse(result.contains("]("))
    }

    func testStripsInlineCode() {
        let input = "Use `print()` function"
        let result = MarkdownStripper.stripMarkdown(input)
        XCTAssertTrue(result.contains("print()"))
        XCTAssertFalse(result.contains("`"))
    }

    func testStripsCodeBlocks() {
        let input = "```swift\nlet x = 1\n```"
        let result = MarkdownStripper.stripMarkdown(input)
        XCTAssertTrue(result.contains("let x = 1"))
        XCTAssertFalse(result.contains("```"))
    }

    func testStripsNestedMarkdown() {
        let input = "# Title\n\nThis is **bold with *nested italic*** text\n\n- List item with `code`"
        let result = MarkdownStripper.stripMarkdown(input)
        XCTAssertTrue(result.contains("Title"))
        XCTAssertTrue(result.contains("bold with"))
        XCTAssertTrue(result.contains("nested italic"))
        XCTAssertTrue(result.contains("code"))
    }

    func testEmptyInput() {
        let result = MarkdownStripper.stripMarkdown("")
        XCTAssertTrue(result.isEmpty)
    }

    func testStripsStrikethrough() {
        let input = "This is ~~deleted~~ text"
        let result = MarkdownStripper.stripMarkdown(input)
        XCTAssertTrue(result.contains("deleted"))
        XCTAssertFalse(result.contains("~~"))
    }
}
