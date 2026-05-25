import Markdown
import SwiftUI

// MARK: - MarkdownTextView

struct MarkdownTextView: NSViewRepresentable {
    let text: String
    var isEditable: Bool = false
    var onTextChange: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(isEditable: isEditable, onTextChange: onTextChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.isRichText = true
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = NSColor(calibratedRed: 0x2F/255.0, green: 0x2F/255.0, blue: 0x2F/255.0, alpha: 1.0)
        textView.backgroundColor = NSColor(calibratedRed: 0xF4/255.0, green: 0xF4/255.0, blue: 0xF4/255.0, alpha: 1.0)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.delegate = context.coordinator
        textView.drawsBackground = true

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.onTextChange = onTextChange

        if textView.string != text {
            textView.string = text
            context.coordinator.applyMarkdownStyling(to: textView)
        }

        textView.isEditable = isEditable
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        let isEditable: Bool
        var onTextChange: ((String) -> Void)?
        private var isUpdating = false

        init(isEditable: Bool, onTextChange: ((String) -> Void)?) {
            self.isEditable = isEditable
            self.onTextChange = onTextChange
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            onTextChange?(textView.string)
        }

        func applyMarkdownStyling(to textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }
            guard !isUpdating else { return }

            isUpdating = true
            defer { isUpdating = false }

            let source = textStorage.string
            guard !source.isEmpty else { return }

            let fullRange = NSRange(location: 0, length: textStorage.length)
            let baseFont = NSFont.systemFont(ofSize: 14)
            let textColor = NSColor(calibratedRed: 0x2F/255.0, green: 0x2F/255.0, blue: 0x2F/255.0, alpha: 1.0)

            textStorage.addAttribute(.font, value: baseFont, range: fullRange)
            textStorage.addAttribute(.foregroundColor, value: textColor, range: fullRange)

            let document = Document(parsing: source)
            for block in document.children {
                applyBlockStyling(block, in: textStorage, source: source)
            }
        }

        private func applyBlockStyling(_ markup: any Markup, in storage: NSTextStorage, source: String) {
            if let heading = markup as? Heading {
                if let range = nsRange(for: heading, in: source) {
                    let fontSize: CGFloat = switch heading.level {
                    case 1: 24
                    case 2: 20
                    case 3: 17
                    default: 15
                    }
                    storage.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: fontSize), range: range)
                }
            }

            if markup is UnorderedList || markup is OrderedList {
                if let range = nsRange(for: markup, in: source) {
                    let paragraphStyle = NSMutableParagraphStyle()
                    paragraphStyle.headIndent = 20
                    paragraphStyle.firstLineHeadIndent = 8
                    storage.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
                }
            }

            for child in markup.children {
                if let strong = child as? Strong {
                    if let range = nsRange(for: strong, in: source) {
                        let currentFont = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? .systemFont(ofSize: 14)
                        let boldFont = NSFontManager.shared.convert(currentFont, toHaveTrait: .boldFontMask)
                        storage.addAttribute(.font, value: boldFont, range: range)
                    }
                } else if let emphasis = child as? Emphasis {
                    if let range = nsRange(for: emphasis, in: source) {
                        let currentFont = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? .systemFont(ofSize: 14)
                        let italicFont = NSFontManager.shared.convert(currentFont, toHaveTrait: .italicFontMask)
                        storage.addAttribute(.font, value: italicFont, range: range)
                    }
                } else if let code = child as? InlineCode {
                    if let range = nsRange(for: code, in: source) {
                        storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), range: range)
                        storage.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: range)
                    }
                }

                applyBlockStyling(child, in: storage, source: source)
            }
        }

        private func nsRange(for markup: any Markup, in source: String) -> NSRange? {
            guard let sourceRange = markup.range else { return nil }

            let startLine = sourceRange.lowerBound.line - 1
            let startCol = sourceRange.lowerBound.column - 1
            let endLine = sourceRange.upperBound.line - 1
            let endCol = sourceRange.upperBound.column - 1

            let lines = source.components(separatedBy: "\n")
            guard startLine < lines.count, endLine < lines.count else { return nil }

            var startOffset = 0
            for i in 0..<startLine {
                startOffset += lines[i].count + 1
            }
            startOffset += startCol

            var endOffset = 0
            for i in 0..<endLine {
                endOffset += lines[i].count + 1
            }
            endOffset += endCol

            let nsSource = source as NSString
            let clampedStart = min(startOffset, nsSource.length)
            let clampedEnd = min(endOffset, nsSource.length)

            guard clampedStart <= clampedEnd else { return nil }
            return NSRange(location: clampedStart, length: clampedEnd - clampedStart)
        }
    }
}
