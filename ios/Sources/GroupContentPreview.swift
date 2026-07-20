import NMP
import NMPContent
import NMPUI
import SwiftUI

/// A channel-row projection over the same bounded content session used by full
/// content. Renderers are text-sized and interaction-free so a NavigationLink
/// row keeps its ordinary tap target, height, and accessibility behavior.
struct GroupContentPreview: View {
    let message: RoomMessage
    let observationFactory: NMPReferenceObservationFactory

    var body: some View {
        NostrContent(
            content: message.content,
            observationFactory: observationFactory,
            context: NostrContentRenderContext(
                ancestorTargetKeys: [],
                depth: 0,
                maximumDepth: 1
            ),
            purpose: .preview,
            renderers: Self.renderers,
            maximumBlocks: 1,
            maximumLinesPerBlock: 2
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private static let renderers = NostrContentRenderers.standard
        .event(kind: 30_023, purpose: .preview, layout: .inline) { input in
            Text(ChannelPreviewText.eventLabel(input.event))
        }
        .fallbackEvent(layout: .inline) { input in
            Text(ChannelPreviewText.eventLabel(input.event))
        }
        .unresolvedReference(layout: .inline) { input in
            Text(ChannelPreviewText.referenceFallback(input.occurrence.original))
                .monospaced()
        }
        .hashtag { input in
            Text(input.original)
        }
        .link { input in
            Text(input.label)
        }
}

enum ChannelPreviewText {
    static func eventLabel(_ row: Row) -> String {
        let content = row.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty ? "Nostr event" : content
    }

    static func referenceFallback(_ original: String) -> String {
        guard original.count > 30 else { return original }
        return "\(original.prefix(19))…\(original.suffix(8))"
    }
}
