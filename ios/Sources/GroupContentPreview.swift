import NMP
import NMPContent
import NMPUI
import SwiftUI

/// A channel-row projection over the same bounded content session used by full
/// content. Renderers are text-sized and interaction-free so a NavigationLink
/// row keeps its ordinary tap target, height, and accessibility behavior.
struct GroupContentPreview: View {
    @StateObject private var session: NostrContentSession

    init(message: RoomMessage, contentClient: NMPContentClient) {
        _session = StateObject(
            wrappedValue: contentClient.session(
                content: message.content,
                policy: NostrContentPolicy(
                    maxActiveReferences: 4,
                    maxResolvedReferences: 8,
                    maxDepth: 1,
                    releaseGraceMilliseconds: 250
                )
            )
        )
    }

    var body: some View {
        NostrContent(
            session: session,
            purpose: .preview,
            renderers: Self.renderers,
            maximumBlocks: 1,
            maximumLinesPerBlock: 2
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .onDisappear { session.stop() }
    }

    private static let renderers = NostrContentRenderers.standard
        .profileMention { input in
            NMPName(pubkey: input.pubkey, profile: input.profile)
        }
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
    static func profileName(pubkey: String, profile: NostrProfileMetadata?) -> String {
        NMPDisplayName.resolve(pubkey: pubkey, profile: profile)
    }

    static func eventLabel(_ row: Row) -> String {
        if let article = decodeNIP23Article(from: row),
           let title = article.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }
        let content = row.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty ? "Nostr event" : content
    }

    static func referenceFallback(_ original: String) -> String {
        guard original.count > 30 else { return original }
        return "\(original.prefix(19))…\(original.suffix(8))"
    }
}
