import XCTest
@testable import Verborra

final class PasteServiceTests: XCTestCase {
    var pasteService: PasteService!

    override func setUp() {
        super.setUp()
        pasteService = PasteService(targetPIDProvider: { 0 })
    }

    func testCopyToClipboard() {
        let text = "# Hello World"
        pasteService.copyToClipboard(text)

        let pasteboard = NSPasteboard.general
        XCTAssertEqual(pasteboard.string(forType: .string), text)
    }

    func testCopyPlainTextStripsMarkdown() {
        let markdownText = "This is **bold** and *italic* text"
        pasteService.copyPlainTextToClipboard(markdownText)

        let pasteboard = NSPasteboard.general
        let result = pasteboard.string(forType: .string) ?? ""
        XCTAssertFalse(result.contains("**"))
        XCTAssertTrue(result.contains("bold"))
        XCTAssertTrue(result.contains("italic"))
    }

    func testCopyPlainTextWithHeadings() {
        let markdownText = "# Title\n\nSome paragraph"
        pasteService.copyPlainTextToClipboard(markdownText)

        let pasteboard = NSPasteboard.general
        let result = pasteboard.string(forType: .string) ?? ""
        XCTAssertTrue(result.contains("Title"))
        XCTAssertTrue(result.contains("Some paragraph"))
        XCTAssertFalse(result.contains("#"))
    }

    func testCopyMarkdownPreservesFormatting() {
        let markdownText = "## Heading\n\n**Bold** text"
        pasteService.copyToClipboard(markdownText)

        let pasteboard = NSPasteboard.general
        XCTAssertEqual(pasteboard.string(forType: .string), markdownText)
    }
}
