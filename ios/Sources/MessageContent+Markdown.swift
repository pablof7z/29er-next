import Foundation
import NMPContent
import SwiftUI

extension MessageContent {
    static func attributed(
        _ raw: String,
        resolveMention: (String) -> String? = { _ in nil }
    ) -> AttributedString {
        let document = parseNostrContent(raw, syntax: .markdown)
        return attributed(document, resolveMention: resolveMention)
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
            case .entity(let token, _, _):
                token
            }
        }.joined()
    }

    static func isSupportedWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https"].contains(scheme)
    }

    private static func attributed(
        _ document: NostrContentDocument,
        resolveMention: (String) -> String?
    ) -> AttributedString {
        var result = AttributedString()
        for (index, block) in document.blocks.enumerated() {
            if index > 0 {
                result.append(AttributedString("\n\n"))
            }
            for inline in block.inlines {
                result.append(attributed(inline, resolveMention: resolveMention))
            }
        }
        return result
    }

    private static func attributed(
        _ inline: NostrContentInline,
        resolveMention: (String) -> String?
    ) -> AttributedString {
        switch inline {
        case .text(let text, _, let styles):
            return styled(text, styles: styles)
        case .reference(let occurrence, let styles):
            let fallback = entityLabel(for: occurrence.original)
            var value = styled(
                mentionLabel(
                    for: occurrence.target,
                    fallback: fallback,
                    resolveMention: resolveMention
                ),
                styles: styles
            )
            value.foregroundColor = .accentColor
            value.font = .body.weight(.medium)
            return value
        case .hashtag(_, let original, _, let styles):
            return styled(original, styles: styles)
        case .link(let destination, let label, _, let styles):
            var value = styled(label, styles: styles)
            if let url = URL(string: destination), isSupportedWebURL(url) {
                value.link = url
            }
            return value
        case .softBreak:
            return AttributedString(" ")
        case .hardBreak:
            return AttributedString("\n")
        }
    }

    private static func styled(
        _ text: String,
        styles: [NostrContentInlineStyle]
    ) -> AttributedString {
        var value = AttributedString(text)
        var intent: InlinePresentationIntent = []
        if styles.contains(.strong) {
            intent.insert(.stronglyEmphasized)
        }
        if styles.contains(.emphasis) {
            intent.insert(.emphasized)
        }
        if styles.contains(.code) {
            intent.insert(.code)
        }
        if styles.contains(.strikethrough) {
            intent.insert(.strikethrough)
        }
        if !intent.isEmpty {
            value.inlinePresentationIntent = intent
        }
        return value
    }
}
