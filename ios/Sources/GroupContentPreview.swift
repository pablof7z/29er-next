import NMP
import NMPContent
import NMPUI
import SwiftUI

/// A channel-row projection over NMP's immutable content document. Selected
/// components own visible reference observations; text-sized renderers keep a
/// NavigationLink row's ordinary tap target, height, and accessibility behavior.
struct GroupContentPreview: View {
    let message: RoomMessage
    let observationFactory: NMPReferenceObservationFactory?

    var body: some View {
        NostrContent(
            content: message.content,
            observationFactory: observationFactory,
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
