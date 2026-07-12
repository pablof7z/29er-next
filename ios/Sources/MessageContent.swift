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
        /// A `nostr:` entity. `token` is the full `nostr:npub1…` source;
        /// `label` is the shortened form shown inline.
        case entity(token: String, label: String)
    }

    static func attributed(_ raw: String) -> AttributedString {
        segments(of: raw).reduce(into: AttributedString()) { result, segment in
            result.append(rendered(segment))
        }
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
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        let full = NSRange(raw.startIndex..., in: raw)
        return detector.matches(in: raw, range: full).compactMap { match in
            guard let url = match.url, let range = Range(match.range, in: raw) else { return nil }
            // NSDataDetector also recognises bare `nostr:` schemes as links;
            // leave those to entity handling.
            guard url.scheme?.lowercased() != "nostr" else { return nil }
            return Span(range: range, segment: .link(display: String(raw[range]), url: url))
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

    /// Shortens a `nostr:npub1abc…xyz` token to `npub1abc…6w6` for inline
    /// display. The `nostr:` scheme prefix is dropped; short tokens are shown
    /// whole.
    static func entityLabel(for token: String) -> String {
        let body = token.hasPrefix("nostr:") ? String(token.dropFirst("nostr:".count)) : token
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
        case .entity(_, let label):
            var attributed = AttributedString(label)
            attributed.foregroundColor = .accentColor
            attributed.font = .body.weight(.medium)
            return attributed
        }
    }
}
