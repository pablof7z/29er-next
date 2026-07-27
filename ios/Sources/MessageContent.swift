import Foundation
import NMP
import SwiftUI

/// Renders raw kind:9 message text as Markdown with tappable web links and
/// styled `nostr:` entity tokens. Pure presentation: no network, no signing.
/// A `nostr:npub…`/`nprofile…` mention is decoded (NMP's stateless bech32
/// codec, #116) to its hex pubkey and shown as `@<kind:0 display name>` when
/// the caller's `resolveMention` resolver knows that pubkey; otherwise, and
/// for every other entity kind, it falls back to the shortened bech32 label.
enum MessageContent {
    /// A contiguous run of the source text classified for display.
    enum Segment: Equatable {
        case text(String)
        case link(display: String, url: URL)
        case audio(display: String, url: URL)
        case image(display: String, url: URL)
        /// A `nostr:` entity. `token` is the full `nostr:npub1…` source;
        /// `label` is the shortened form shown inline.
        case entity(token: String, label: String)
    }

    enum Block: Equatable {
        case inline([Segment])
        case audio(display: String, url: URL)
        case image(display: String, url: URL)
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
            switch segment {
            case .audio(let display, let url):
                flushInline()
                blocks.append(.audio(display: display, url: url))
            case .image(let display, let url):
                flushInline()
                blocks.append(.image(display: display, url: url))
            case .link(let display, let url) where isImageURL(url):
                flushInline()
                blocks.append(.image(display: display, url: url))
            default:
                inline.append(segment)
            }
        }
        flushInline()
        return blocks
    }

    static func imageURLs(in raw: String) -> [URL] {
        var seen = Set<URL>()
        return segments(of: raw).compactMap { segment in
            let url: URL
            switch segment {
            case .image(_, let imageURL):
                url = imageURL
            case .link(_, let linkURL) where isImageURL(linkURL):
                url = linkURL
            default:
                return nil
            }
            return seen.insert(url).inserted ? url : nil
        }
    }

    static func isImageURL(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    // MARK: - Tokenizing

    /// Classifies `raw` into an ordered, non-overlapping list of segments.
    /// Entity tokens win over link detection where they overlap, so a
    /// `nostr:` URI is never mis-rendered as a plain web link.
    static func segments(of raw: String) -> [Segment] {
        guard !raw.isEmpty else { return [] }

        let images = markdownImageSpans(in: raw)
        let destinations = markdownDestinationRanges(in: raw)
        let entities = entitySpans(in: raw).filter { entity in
            !images.contains { $0.range.overlaps(entity.range) }
        }
        let links = linkSpans(in: raw).filter { link in
            !entities.contains { $0.range.overlaps(link.range) }
                && !images.contains { $0.range.overlaps(link.range) }
                && !destinations.contains { $0.overlaps(link.range) }
        }

        let spans = (images + entities + links).sorted {
            $0.range.lowerBound < $1.range.lowerBound
        }

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

    private static func markdownImageSpans(in raw: String) -> [Span] {
        markdownImageRegex.matches(
            in: raw,
            range: NSRange(raw.startIndex..., in: raw)
        ).compactMap { match in
            guard
                let range = Range(match.range, in: raw),
                let altRange = Range(match.range(at: 1), in: raw),
                let urlRange = Range(match.range(at: 2), in: raw),
                let url = URL(string: String(raw[urlRange])),
                isSupportedWebURL(url)
            else {
                return nil
            }
            return Span(
                range: range,
                segment: .image(display: String(raw[altRange]), url: url)
            )
        }
    }

    private static func markdownDestinationRanges(in raw: String) -> [Range<String.Index>] {
        markdownDestinationRegex.matches(
            in: raw,
            range: NSRange(raw.startIndex..., in: raw)
        ).compactMap { Range($0.range(at: 1), in: raw) }
    }

    /// `nostr:` followed by a TLV/bech32 entity prefix and its bech32 body
    /// (charset excludes `1`, `b`, `i`, `o` after the separator).
    static let entityRegex: NSRegularExpression = {
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

    private static let markdownImageRegex: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"!\[([^\]\n]*)\]\(\s*<?(https?://[^\s)>]+)>?(?:\s+(?:"[^"]*"|'[^']*'|\([^)]*\)))?\s*\)"#,
            options: [.caseInsensitive]
        )
    }()

    private static let markdownDestinationRegex: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"!?\[[^\]\n]*\]\(\s*<?(https?://[^\s)>]+)>?(?:\s+(?:"[^"]*"|'[^']*'|\([^)]*\)))?\s*\)"#,
            options: [.caseInsensitive]
        )
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

    private static let imageExtensions: Set<String> = [
        "avif", "gif", "heic", "heif", "jpeg", "jpg", "png", "webp"
    ]
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

    /// `@<kind:0 display name>` for an `npub`/`nprofile` token the caller's
    /// resolver knows; the shortened bech32 `label` otherwise (unresolved
    /// pubkey, or an entity kind that isn't a profile mention at all).
    static func mentionLabel(
        for token: String,
        fallback label: String,
        resolveMention: (String) -> String?
    ) -> String {
        guard let pubkey = mentionPubkey(in: token), let name = resolveMention(pubkey) else {
            return label
        }
        return "@\(name)"
    }

    private static func mentionPubkey(in token: String) -> String? {
        guard let entity = try? decodeNostrEntity(token) else { return nil }
        switch entity {
        case .pubkey(let pubkey):
            return pubkey
        case .profile(let pubkey, _):
            return pubkey
        case .eventId, .event, .coordinate:
            return nil
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
