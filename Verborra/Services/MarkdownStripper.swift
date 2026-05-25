import Foundation
import Markdown

// MARK: - MarkdownStripper

struct MarkdownStripper {
    private static let log = DiagnosticLogger.logger(for: .system)

    /// Извлекает plain text из Markdown, удаляя всю разметку
    static func stripMarkdown(_ text: String) -> String {
        log.debug("stripMarkdown", metadata: [
            "inputLength": "\(text.count) chars"
        ])
        let document = Document(parsing: text)
        var extractor = PlainTextExtractor()
        extractor.visit(document)
        let result = extractor.result.trimmingCharacters(in: .whitespacesAndNewlines)
        log.debug("stripMarkdown result", metadata: [
            "outputLength": "\(result.count) chars"
        ])
        return result
    }
}

// MARK: - PlainTextExtractor

private struct PlainTextExtractor: MarkupWalker {
    var result = ""

    mutating func visitText(_ text: Markdown.Text) -> () {
        result += text.string
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> () {
        result += " "
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> () {
        result += "\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> () {
        descendInto(paragraph)
        result += "\n\n"
    }

    mutating func visitHeading(_ heading: Heading) -> () {
        descendInto(heading)
        result += "\n\n"
    }

    mutating func visitListItem(_ listItem: ListItem) -> () {
        result += "• "
        descendInto(listItem)
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> () {
        result += codeBlock.code
        result += "\n"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> () {
        result += inlineCode.code
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> () {
        result += "\n---\n"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> () {
        descendInto(blockQuote)
    }

    mutating func visitLink(_ link: Markdown.Link) -> () {
        descendInto(link)
    }

    mutating func visitImage(_ image: Markdown.Image) -> () {
        descendInto(image)
    }

    mutating func visitStrong(_ strong: Strong) -> () {
        descendInto(strong)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> () {
        descendInto(emphasis)
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> () {
        descendInto(strikethrough)
    }
}
