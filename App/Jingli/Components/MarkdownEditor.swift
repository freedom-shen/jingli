import AppKit
import SwiftUI

/// MarkdownTextEditor 通过它把内部 NSTextView 暴露出来（预留扩展点）。
final class MarkdownTextController {
    weak var textView: NSTextView?
}

struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    let controller: MarkdownTextController
    var editable: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = NSColor(white: 0.87, alpha: 1)
        textView.insertionPointColor = NSColor(white: 0.9, alpha: 1)
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isEditable = editable
        textView.string = text

        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        controller.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.isEditable = editable
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: MarkdownTextEditor

        init(_ parent: MarkdownTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(String)
    case numbered(String)
    case checklist(done: Bool, text: String)
    case quote(String)
    case code(String)
}

enum MarkdownParser {
    static func blocks(from text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var codeLines: [String] = []
        var inCode = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph.removeAll()
        }

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(codeLines.joined(separator: "\n")))
                    codeLines.removeAll()
                    inCode = false
                } else {
                    flushParagraph()
                    inCode = true
                }
                continue
            }

            if inCode {
                codeLines.append(rawLine)
                continue
            }

            if line.isEmpty {
                flushParagraph()
                continue
            }

            if line.hasPrefix("### ") {
                flushParagraph()
                blocks.append(.heading(level: 3, text: String(line.dropFirst(4))))
            } else if line.hasPrefix("## ") {
                flushParagraph()
                blocks.append(.heading(level: 2, text: String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                flushParagraph()
                blocks.append(.heading(level: 1, text: String(line.dropFirst(2))))
            } else if let item = checklist(line) {
                flushParagraph()
                blocks.append(item)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph()
                blocks.append(.bullet(String(line.dropFirst(2))))
            } else if let range = line.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                flushParagraph()
                blocks.append(.numbered(String(line[range.upperBound...])))
            } else if line.hasPrefix("> ") {
                flushParagraph()
                blocks.append(.quote(String(line.dropFirst(2))))
            } else {
                paragraph.append(line)
            }
        }

        if inCode, !codeLines.isEmpty {
            blocks.append(.code(codeLines.joined(separator: "\n")))
        }
        flushParagraph()
        return blocks
    }

    private static func checklist(_ line: String) -> MarkdownBlock? {
        for (marker, done) in [("- [x] ", true), ("- [X] ", true), ("- [ ] ", false)] {
            if line.hasPrefix(marker) {
                return .checklist(done: done, text: String(line.dropFirst(marker.count)))
            }
        }
        return nil
    }

    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let attributed = try? AttributedString(markdown: text, options: options) {
            return attributed
        }
        return AttributedString(text)
    }
}

/// 详情里的 Markdown 编辑区：左边纯文本编辑，右边实时预览。
struct MarkdownEditorView: View {
    @Binding var text: String
    var editable: Bool = true
    @State private var controller = MarkdownTextController()

    var body: some View {
        Group {
            if editable {
                HStack(spacing: 0) {
                    MarkdownTextEditor(text: $text, controller: controller, editable: true)
                        .accessibilityIdentifier("task-detail-note-editor")

                    Divider()

                    preview
                        .accessibilityIdentifier("task-detail-note-preview")
                }
            } else {
                preview
            }
        }
        .frame(minHeight: 280)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private var preview: some View {
        ScrollView {
            MarkdownPreview(text: text)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct MarkdownPreview: View {
    let text: String

    var body: some View {
        let blocks = MarkdownParser.blocks(from: text)
        VStack(alignment: .leading, spacing: 8) {
            if blocks.isEmpty {
                Text("还没有详情")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    view(for: block)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            Text(MarkdownParser.inline(text))
                .font(.system(size: level == 1 ? 18 : (level == 2 ? 15 : 13.5), weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, level == 1 ? 6 : 2)

        case let .paragraph(text):
            Text(MarkdownParser.inline(text))
                .font(.system(size: 13))
                .foregroundStyle(Color(white: 0.84))
                .fixedSize(horizontal: false, vertical: true)

        case let .bullet(text):
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                Text(MarkdownParser.inline(text))
                    .font(.system(size: 13))
                    .foregroundStyle(Color(white: 0.84))
            }

        case let .numbered(text):
            HStack(alignment: .top, spacing: 8) {
                Text("·")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text(MarkdownParser.inline(text))
                    .font(.system(size: 13))
                    .foregroundStyle(Color(white: 0.84))
            }

        case let .checklist(done, text):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: done ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .foregroundStyle(done ? Theme.accent : Theme.textSecondary.opacity(0.7))
                    .padding(.top, 2)
                Text(MarkdownParser.inline(text))
                    .font(.system(size: 13))
                    .foregroundStyle(done ? Theme.textSecondary : Color(white: 0.84))
                    .strikethrough(done, color: Theme.textSecondary)
            }

        case let .quote(text):
            HStack(spacing: 10) {
                Rectangle()
                    .fill(Theme.tomato)
                    .frame(width: 2)
                Text(MarkdownParser.inline(text))
                    .font(.system(size: 13))
                    .italic()
                    .foregroundStyle(Color(white: 0.72))
            }
            .padding(.vertical, 2)

        case let .code(text):
            Text(text)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Color(white: 0.8))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
        }
    }
}
