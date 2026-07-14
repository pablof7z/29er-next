import Foundation
import SwiftUI

/// Renders raw kind:9 message text into a display `AttributedString` with
/// tappable web links and styled `nostr:` entity tokens. Pure presentation:
/// no network, no signing, and — critically — no bech32 decode. Resolving a
/// `nostr:npub…`/`nprofile…` mention to a hex pubkey (and thus to a kind:0
/// display name) needs a decoder NMP does not yet expose over FFI, so entity
/// tokens are shown as a shortened bech32 label until that codec lands.
enum MessageContent {
    /// A contiguous run of the source text classified for display.
    enum Segment: Equatable {
        case text(String)
        case link(display: String, url: URL)
        case audio(display: String, url: URL)
        /// A `nostr:` entity. `token` is the full `nostr:npub1…` source;
        /// `label` is the shortened form shown inline.
        case entity(token: String, label: String)
    }

    enum Block: Equatable {
        case inline([Segment])
        case audio(display: String, url: URL)
    }

    static func attributed(_ raw: String) -> AttributedString {
        attributed(segments(of: raw))
    }

    static func attributed(_ segments: [Segment]) -> AttributedString {
        segments.reduce(into: AttributedString()) { result, segment in
            result.append(rendered(segment))
        }
    }

    static func blocks(of raw: String) -> [Block] {
        var blocks: [Block] = []
        var inline: [Segment] = []

        func flushInline() {
            let normalized = normalizedInline(inline)
            if !normalized.isEmpty { blocks.append(.inline(normalized)) }
            inline.removeAll(keepingCapacity: true)
        }

        for segment in segments(of: raw) {
            if case .audio(let display, let url) = segment {
                flushInline()
                blocks.append(.audio(display: display, url: url))
            } else {
                inline.append(segment)
            }
        }
        flushInline()
        return blocks
    }

    // MARK: - Tokenizing

    /// Classifies `raw` into an ordered, non-overlapping list of segments.
    /// Entity tokens win over link detection where they overlap, so a
    /// `nostr:` URI is never mis-rendered as a plain web link.
    static func segments(of raw: String) -> [Segment] {
        guard !raw.isEmpty else { return [] }

        let entities = entitySpans(in: raw)
        let links = linkSpans(in: raw).filter { link in
            !entities.contains { $0.range.overlaps(link.range) }
        }

        let spans = (entities + links).sorted { $0.range.lowerBound < $1.range.lowerBound }

        var segments: [Segment] = []
        var cursor = raw.startIndex
        for span in spans {
            if cursor < span.range.lowerBound {
                segments.append(.text(String(raw[cursor..<span.range.lowerBound])))
            }
            segments.append(span.segment)
            cursor = span.range.upperBound
        }
        if cursor < raw.endIndex {
            segments.append(.text(String(raw[cursor...])))
        }
        return segments
    }

    private struct Span {
        let range: Range<String.Index>
        let segment: Segment
    }

    private static func linkSpans(in raw: String) -> [Span] {
        let full = NSRange(raw.startIndex..., in: raw)
        return linkDetector.matches(in: raw, range: full).compactMap { match in
            guard let url = match.url, let range = Range(match.range, in: raw) else { return nil }
            guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
                return nil
            }
            let display = String(raw[range])
            let segment: Segment = isSupportedAudioURL(url)
                ? .audio(display: display, url: url)
                : .link(display: display, url: url)
            return Span(range: range, segment: segment)
        }
    }

    private static func entitySpans(in raw: String) -> [Span] {
        entityRegex.matches(in: raw, range: NSRange(raw.startIndex..., in: raw)).compactMap { match in
            guard let range = Range(match.range, in: raw) else { return nil }
            let token = String(raw[range])
            return Span(range: range, segment: .entity(token: token, label: entityLabel(for: token)))
        }
    }

    /// `nostr:` followed by a TLV/bech32 entity prefix and its bech32 body
    /// (charset excludes `1`, `b`, `i`, `o` after the separator).
    private static let entityRegex: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: "nostr:(?:npub|nprofile|note|nevent|naddr)1[023456789acdefghjklmnpqrstuvwxyz]+",
            options: [.caseInsensitive]
        )
    }()

    private static let linkDetector: NSDataDetector = {
        // swiftlint:disable:next force_try
        try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    }()

    private static let supportedAudioExtensions: Set<String> = [
        "aac", "aif", "aiff", "caf", "flac", "m4a", "m4b", "mp3", "wav"
    ]

    static func isSupportedAudioURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return false
        }
        return supportedAudioExtensions.contains(url.pathExtension.lowercased())
    }

    /// Shortens a `nostr:npub1abc…xyz` token to `npub1abc…6w6` for inline
    /// display. The `nostr:` scheme prefix is dropped; short tokens are shown
    /// whole.
    static func entityLabel(for token: String) -> String {
        let body = token.lowercased().hasPrefix("nostr:")
            ? String(token.dropFirst("nostr:".count))
            : token
        guard body.count > 18 else { return body }
        return "\(body.prefix(10))…\(body.suffix(5))"
    }

    // MARK: - Rendering

    private static func rendered(_ segment: Segment) -> AttributedString {
        switch segment {
        case .text(let value):
            return AttributedString(value)
        case .link(let display, let url):
            var attributed = AttributedString(display)
            attributed.link = url
            attributed.foregroundColor = .accentColor
            return attributed
        case .audio:
            return AttributedString()
        case .entity(_, let label):
            var attributed = AttributedString(label)
            attributed.foregroundColor = .accentColor
            attributed.font = .body.weight(.medium)
            return attributed
        }
    }

    private static func normalizedInline(_ segments: [Segment]) -> [Segment] {
        var result = segments
        while case .text(let value)? = result.first {
            let trimmed = value.drop(while: \.isWhitespace)
            if trimmed.isEmpty {
                result.removeFirst()
            } else {
                result[0] = .text(String(trimmed))
                break
            }
        }
        while case .text(let value)? = result.last {
            let trimmed = value.reversed().drop(while: \.isWhitespace).reversed()
            if trimmed.isEmpty {
                result.removeLast()
            } else {
                result[result.count - 1] = .text(String(trimmed))
                break
            }
        }
        return result
    }
}
