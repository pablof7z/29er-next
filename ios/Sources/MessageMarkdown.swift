import SwiftUI

enum MessageMarkdown {
    enum BlockKind: Equatable {
        case heading(Int)
        case paragraph
        case bullet
        case ordered(String)
        case quote
        case code
        case divider
    }

    struct Block: Identifiable, Equatable {
        let id: Int
        let kind: BlockKind
        let text: String
    }

    static func blocks(in source: String) -> [Block] {
        var parsed: [(BlockKind, String)] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var code: [String] = []
        var inCode = false

        func append(_ kind: BlockKind, _ text: String = "") {
            parsed.append((kind, text))
        }
        func flushParagraph() {
            let text = paragraph.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { append(.paragraph, text) }
            paragraph.removeAll(keepingCapacity: true)
        }
        func flushQuote() {
            let text = quote.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { append(.quote, text) }
            quote.removeAll(keepingCapacity: true)
        }

        for rawLine in source.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCode {
                    append(.code, code.joined(separator: "\n"))
                    code.removeAll(keepingCapacity: true)
                } else {
                    flushParagraph()
                    flushQuote()
                }
                inCode.toggle()
                continue
            }
            if inCode {
                code.append(rawLine)
                continue
            }
            if trimmed.isEmpty {
                flushParagraph()
                flushQuote()
                continue
            }
            if let heading = heading(trimmed) {
                flushParagraph()
                flushQuote()
                append(heading.kind, heading.text)
                continue
            }
            if isDivider(trimmed) {
                flushParagraph()
                flushQuote()
                append(.divider)
                continue
            }
            if trimmed.hasPrefix("> ") {
                flushParagraph()
                quote.append(String(trimmed.dropFirst(2)))
                continue
            }
            if let ordered = orderedItem(trimmed) {
                flushParagraph()
                flushQuote()
                append(ordered.kind, ordered.text)
                continue
            }
            if let bullet = bulletItem(trimmed) {
                flushParagraph()
                flushQuote()
                append(.bullet, bullet)
                continue
            }
            flushQuote()
            paragraph.append(rawLine.trimmingCharacters(in: .whitespaces))
        }

        if inCode { append(.code, code.joined(separator: "\n")) }
        flushParagraph()
        flushQuote()
        return parsed.enumerated().map { index, value in
            Block(id: index, kind: value.0, text: value.1)
        }
    }

    private static func heading(_ line: String) -> (kind: BlockKind, text: String)? {
        let level = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level) else { return nil }
        let rest = line.dropFirst(level)
        guard rest.first == " " else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (.heading(level), text)
    }

    private static func orderedItem(_ line: String) -> (kind: BlockKind, text: String)? {
        let digits = line.prefix(while: \.isNumber)
        guard !digits.isEmpty else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") else { return nil }
        let text = rest.dropFirst(2).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (.ordered("\(digits)."), text)
    }

    private static func bulletItem(_ line: String) -> String? {
        for prefix in ["- ", "* ", "+ "] where line.hasPrefix(prefix) {
            let text = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : text
        }
        return nil
    }

    private static func isDivider(_ line: String) -> Bool {
        let characters = line.filter { !$0.isWhitespace }
        guard characters.count >= 3, let marker = characters.first else { return false }
        return ["-", "*", "_"].contains(marker) && characters.allSatisfy { $0 == marker }
    }
}

struct MessageMarkdownText: View {
    let segments: [MessageContent.Segment]
    let resolveMention: (String) -> String?
    let onOpenLink: (URL) -> Void
    let onReply: () -> Void

    private var source: String {
        MessageContent.source(of: segments)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(MessageMarkdown.blocks(in: source)) { block in
                content(for: block)
            }
        }
        .foregroundStyle(.primary)
        .tint(.accentColor)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in
            onOpenLink(url)
            return .handled
        })
        .contentShape(Rectangle())
        .onTapGesture {
            PlatformSupport.performLightImpact()
            onReply()
        }
    }

    @ViewBuilder
    private func content(for block: MessageMarkdown.Block) -> some View {
        switch block.kind {
        case .heading(let level):
            inline(block.text)
                .font(headingFont(level))
        case .paragraph:
            inline(block.text)
        case .bullet:
            marker("•", text: block.text)
        case .ordered(let glyph):
            marker(glyph, text: block.text)
        case .quote:
            HStack(spacing: 10) {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 3)
                inline(block.text).italic()
            }
        case .code:
            Text(block.text)
                .font(.callout.monospaced())
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.primary.opacity(0.06))
                )
        case .divider:
            Divider()
        }
    }

    private func inline(_ raw: String) -> Text {
        Text(MessageContent.attributed(raw, resolveMention: resolveMention))
    }

    private func marker(_ glyph: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(glyph)
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
            inline(text)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title2.bold()
        case 2: .title3.weight(.semibold)
        case 3: .headline
        default: .subheadline.weight(.semibold)
        }
    }
}
