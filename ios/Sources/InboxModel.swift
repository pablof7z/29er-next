import NMP
import Observation

/// Cross-room projection of kind:9 messages that p-tag the active account, plus
/// the kind:0 identities of their authors for display. One live query buckets
/// every room, so newly mentioned rooms need no re-subscription. Read state is
/// held by the shared `MentionReads`; this model only decides what a mention is
/// and how the unread set is derived from it.
@MainActor
@Observable
final class InboxModel {
    private(set) var mentions: [Mention] = []
    private(set) var profiles = ProfileBook()

    let reads: MentionReads

    private let engine: NMPEngine
    private let recipient: String

    init(engine: NMPEngine, recipient: String, reads: MentionReads) {
        self.engine = engine
        self.recipient = recipient
        self.reads = reads
    }

    var unreadMentions: [Mention] {
        mentions.filter { reads.isUnread(id: $0.id, createdAt: $0.createdAt) }
    }

    var unreadCount: Int {
        unreadMentions.count
    }

    func observe() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in await self?.observeMentions() }
            group.addTask { [weak self] in await self?.observeProfiles() }
        }
    }

    private func observeMentions() async {
        do {
            let query = try await openNMPQuery(
                engine: engine,
                filter: NMPFilter(kinds: [9], tags: ["p": .literal([recipient])], limit: 500)
            )
            defer { query.cancel() }

            for await batch in query {
                guard !Task.isCancelled else { return }
                mentions = MentionProjection.mentions(from: batch.rows, recipient: recipient)
            }
        } catch {
            // The inbox is enrichment; on failure the app still runs unmentioned.
            return
        }
    }

    private func observeProfiles() async {
        // kind:0 for every author who has mentioned me, via a reactive derived
        // binding so demand grows as new mention authors appear. NMP owns the
        // routing; the app only declares which authors it cares about.
        let authors: NMPBinding = .derived(
            inner: NMPFilter(
                kinds: [9],
                tags: ["p": .literal([recipient])],
                limit: 500
            ),
            project: .authors
        )

        do {
            let query = try await openNMPQuery(
                engine: engine,
                filter: NMPFilter(kinds: [0], authors: authors, limit: 500)
            )
            defer { query.cancel() }

            for await batch in query {
                guard !Task.isCancelled else { return }
                profiles = RoomProfileProjection.profiles(from: batch.rows)
            }
        } catch {
            // Identity is enrichment; the inbox still renders shortened-hex.
            return
        }
    }
}
