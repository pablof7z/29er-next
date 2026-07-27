import Foundation
import SwiftUI

extension MessageContent {
    static func attributed(
        _ raw: String,
        resolveMention: (String) -> String? = { _ in nil }
    ) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        var attributed = (try? AttributedString(markdown: raw, options: options))
            ?? AttributedString(raw)
        removeUnsupportedLinks(from: &attributed)
        replaceEntities(in: &attributed, resolveMention: resolveMention)
        return attributed
    }

    static func attributed(
        _ segments: [Segment],
        resolveMention: (String) -> String? = { _ in nil }
    ) -> AttributedString {
        attributed(source(of: segments), resolveMention: resolveMention)
    }

    static func source(of segments: [Segment]) -> String {
        segments.map { segment in
            switch segment {
            case .text(let value):
                value
            case .link(let display, _), .audio(let display, _), .image(let display, _):
                display
            case .entity(let token, _):
                token
            }
        }.joined()
    }

    static func isSupportedWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https"].contains(scheme)
    }

    private static func removeUnsupportedLinks(from attributed: inout AttributedString) {
        let unsupported = attributed.runs.reduce(
            into: [Range<AttributedString.Index>]()
        ) { ranges, run in
            guard let link = run.link, !isSupportedWebURL(link) else { return }
            ranges.append(run.range)
        }
        for range in unsupported {
            attributed[range].link = nil
        }
    }

    private static func replaceEntities(
        in attributed: inout AttributedString,
        resolveMention: (String) -> String?
    ) {
        let visible = String(attributed.characters)
        let matches = entityRegex.matches(
            in: visible,
            range: NSRange(visible.startIndex..., in: visible)
        )
        for match in matches.reversed() {
            guard let stringRange = Range(match.range, in: visible) else { continue }
            let lowerOffset = visible.distance(from: visible.startIndex, to: stringRange.lowerBound)
            let upperOffset = visible.distance(from: visible.startIndex, to: stringRange.upperBound)
            let lower = attributed.characters.index(
                attributed.characters.startIndex,
                offsetBy: lowerOffset
            )
            let upper = attributed.characters.index(
                attributed.characters.startIndex,
                offsetBy: upperOffset
            )
            let range = lower..<upper
            let token = String(visible[stringRange])
            let label = entityLabel(for: token)
            var replacement = AttributedString(
                mentionLabel(for: token, fallback: label, resolveMention: resolveMention)
            )
            if let attributes = attributed[range].runs.first?.attributes {
                replacement.mergeAttributes(attributes)
            }
            replacement.foregroundColor = .accentColor
            replacement.font = .body.weight(.medium)
            attributed.replaceSubrange(range, with: replacement)
        }
    }
}
