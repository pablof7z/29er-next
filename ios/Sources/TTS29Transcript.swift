import Foundation

/// A block of the read-along transcript, classified from the spoken item's
/// Markdown body.
enum TTS29BlockKind: Hashable, Sendable {
    case heading(Int)
    case paragraph
    case bullet
    case ordered(String)
    case quote
    case code
}

struct TTS29Block: Identifiable, Hashable, Sendable {
    let id: Int
    let kind: TTS29BlockKind
    let text: String
    let startFraction: Double
    let endFraction: Double
}

/// Which sentence of which block is currently spoken.
struct TTS29Focus: Equatable, Sendable {
    let block: Int
    let sentence: Int
}

/// Parses a spoken item's Markdown body into read-along blocks and derives a
/// sentence-level focus from linear audio progress. There is no per-word
/// timing: focus is a proportional approximation weighted by the alphanumeric
/// character count of each sentence, so punctuation and Markdown never skew the
/// map.
struct TTS29Transcript: Equatable, Sendable {
    let blocks: [TTS29Block]
    private let units: [Unit]

    private struct Unit: Equatable, Sendable {
        let block: Int
        let sentence: Int
        let endFraction: Double
    }

    init(_ body: String) {
        let raw = Self.segment(body)
        let total = max(raw.reduce(0) { $0 + Self.speakableWeight($1.text) }, 1)

        var blocks: [TTS29Block] = []
        var cursor = 0
        for (index, segment) in raw.enumerated() {
            let start = Double(cursor) / Double(total)
            cursor += max(Self.speakableWeight(segment.text), 1)
            let end = index == raw.count - 1 ? 1 : Double(cursor) / Double(total)
            blocks.append(
                TTS29Block(
                    id: index,
                    kind: segment.kind,
                    text: segment.text,
                    startFraction: start,
                    endFraction: end
                )
            )
        }
        self.blocks = blocks

        var units: [Unit] = []
        var sentenceCursor = 0
        for block in blocks {
            let sentences = Self.sentences(in: block)
            for (offset, sentence) in sentences.enumerated() {
                sentenceCursor += max(Self.speakableWeight(sentence), 1)
                units.append(
                    Unit(
                        block: block.id,
                        sentence: offset,
                        endFraction: Double(sentenceCursor) / Double(total)
                    )
                )
            }
        }
        if let last = units.indices.last {
            units[last] = Unit(
                block: units[last].block,
                sentence: units[last].sentence,
                endFraction: 1
            )
        }
        self.units = units
    }

    var isEmpty: Bool { blocks.isEmpty }

    /// The focused sentence at a playback progress in `0...1`: the first unit
    /// whose `endFraction` exceeds progress, falling back to the last unit.
    func focus(at progress: Double) -> TTS29Focus? {
        guard !units.isEmpty else { return nil }
        let clamped = min(max(progress, 0), 1)
        let unit = units.first { clamped < $0.endFraction } ?? units[units.count - 1]
        return TTS29Focus(block: unit.block, sentence: unit.sentence)
    }

    /// Sentences within a block. Headings and code stay whole; other blocks
    /// split on sentence terminators so the highlight advances mid-paragraph.
    static func sentences(in block: TTS29Block) -> [String] {
        switch block.kind {
        case .heading, .code: [block.text]
        default: sentences(in: block.text)
        }
    }

    /// Splits a text run into approximate sentences: a break follows `.`, `!`,
    /// or `?` when the next character is whitespace or the end of the text.
    static func sentences(in text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var result: [String] = []
        let scalars = Array(trimmed)
        var start = 0
        var index = 0
        while index < scalars.count {
            let character = scalars[index]
            let isTerminator = character == "." || character == "!" || character == "?"
            let nextIsBoundary = index + 1 >= scalars.count || scalars[index + 1].isWhitespace
            if isTerminator && nextIsBoundary {
                let sentence = String(scalars[start...index]).trimmingCharacters(in: .whitespaces)
                if !sentence.isEmpty { result.append(sentence) }
                var next = index + 1
                while next < scalars.count, scalars[next].isWhitespace { next += 1 }
                start = next
                index = next
                continue
            }
            index += 1
        }
        if start < scalars.count {
            let tail = String(scalars[start...]).trimmingCharacters(in: .whitespaces)
            if !tail.isEmpty { result.append(tail) }
        }
        return result.isEmpty ? [trimmed] : result
    }

    // MARK: - Segmentation

    private struct Segment { let kind: TTS29BlockKind; let text: String }

    /// Alphanumerics only, so punctuation and Markdown syntax never weight the
    /// proportional map.
    static func speakableWeight(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { count, scalar in
            CharacterSet.alphanumerics.contains(scalar) ? count + 1 : count
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func segment(_ body: String) -> [Segment] {
        var segments: [Segment] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var code: [String] = []
        var inCode = false

        func flushParagraph() {
            let text = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { segments.append(Segment(kind: .paragraph, text: text)) }
            paragraph.removeAll()
        }
        func flushQuote() {
            let text = quote.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { segments.append(Segment(kind: .quote, text: text)) }
            quote.removeAll()
        }

        for rawLine in body.components(separatedBy: "\n") {
            let line = rawLine
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCode {
                    segments.append(Segment(kind: .code, text: code.joined(separator: "\n")))
                    code.removeAll()
                    inCode = false
                } else {
                    flushParagraph()
                    flushQuote()
                    inCode = true
                }
                continue
            }
            if inCode {
                code.append(line)
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
                segments.append(heading)
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
                segments.append(ordered)
                continue
            }
            if let bullet = bulletItem(trimmed) {
                flushParagraph()
                flushQuote()
                segments.append(Segment(kind: .bullet, text: bullet))
                continue
            }
            flushQuote()
            paragraph.append(trimmed)
        }

        if inCode, !code.isEmpty {
            segments.append(Segment(kind: .code, text: code.joined(separator: "\n")))
        }
        flushParagraph()
        flushQuote()
        return segments
    }

    private static func heading(_ line: String) -> Segment? {
        var level = 0
        for character in line {
            if character == "#" { level += 1 } else { break }
        }
        guard (1...6).contains(level) else { return nil }
        let rest = line.dropFirst(level)
        guard rest.first == " " else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return Segment(kind: .heading(level), text: text)
    }

    private static func orderedItem(_ line: String) -> Segment? {
        var digits = ""
        for character in line {
            if character.isNumber { digits.append(character) } else { break }
        }
        guard !digits.isEmpty else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.first == "." else { return nil }
        let text = rest.dropFirst().trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return Segment(kind: .ordered("\(digits)."), text: text)
    }

    private static func bulletItem(_ line: String) -> String? {
        for prefix in ["- ", "* ", "+ "] where line.hasPrefix(prefix) {
            let text = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : text
        }
        return nil
    }
}
