import Foundation
import NMP
import Observation

@MainActor
@Observable
final class RoomTimelineModel {
    enum State: Equatable {
        case loading
        case observing
    }

    private(set) var state: State = .loading
    private(set) var contentRows: [Row] = []
    private(set) var members: [RoomMember] = []
    private(set) var admins: [String] = []
    private(set) var profiles = ProfileBook()

    private(set) var contentError: String?
    private(set) var membershipError: String?
    private(set) var adminError: String?
    private(set) var profileError: String?

    private(set) var hasReceivedContent = false
    private(set) var hasReceivedMembership = false
    private(set) var hasMembershipMetadata = false

    private let engine: NMPEngine
    private let groupID: String
    private let hostRelay: String
    private let recipient: String?
    private let queryOpening: NMPQueryOpening

    init(
        engine: NMPEngine,
        groupID: String,
        hostRelay: String,
        recipient: String? = nil,
        queryOpening: NMPQueryOpening = .live
    ) {
        self.engine = engine
        self.groupID = groupID
        self.hostRelay = hostRelay
        self.recipient = recipient
        self.queryOpening = queryOpening
    }

    var messages: [RoomMessage] {
        NIP29ViewProjection.messages(from: contentRows)
    }

    var mentionIDs: Set<String> {
        guard let recipient else { return [] }
        return MentionProjection.mentionIDs(from: contentRows, recipient: recipient)
    }

    var activities: [AgentActivity] {
        NIP29ViewProjection.activities(from: contentRows)
    }

    var people: RoomPeople {
        NIP29ViewProjection.people(members: members, activities: activities)
    }

    var composerRecipients: [ComposerRecipient] {
        RoomComposerProjection.recipients(
            from: people,
            profiles: profiles,
            excluding: recipient
        )
    }

    func composerReply(to message: RoomMessage) -> ComposerReply {
        RoomComposerProjection.reply(to: message, people: people, profiles: profiles)
    }

    /// Management backends present in this room, resolved from kind:0 across
    /// members, admins, and live-session authors.
    var backends: [RoomBackend] {
        let candidates = members.map(\.pubkey) + admins + activities.map(\.author)
        return RoomBackendProjection.backends(candidatePubkeys: candidates, profiles: profiles)
    }

    func observe() async {
        state = .observing

        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                guard let self else { return }
                await self.observeContent()
            }
            group.addTask { [weak self] in
                guard let self else { return }
                await self.observeMembership()
            }
            group.addTask { [weak self] in
                guard let self else { return }
                await self.observeAdmins()
            }
            group.addTask { [weak self] in
                guard let self else { return }
                await self.observeProfiles()
            }
        }
    }

    private func observeContent() async {
        do {
            var demand = try groupContentDemand(host: hostRelay, groupId: groupID)
            demand.selection.limit = 200
            let query = try await queryOpening.demand(engine, demand)
            defer { query.cancel() }

            for await batch in query {
                guard !Task.isCancelled else { return }
                contentRows = batch.rows
                contentError = nil
                hasReceivedContent = true
            }
        } catch {
            guard !Task.isCancelled else { return }
            contentError = error.localizedDescription
        }
    }

    private func observeMembership() async {
        do {
            let query = try await queryOpening.filter(
                engine,
                NMPFilter(
                    kinds: [39_002],
                    tags: ["d": .literal([groupID])],
                    limit: 20
                )
            )
            defer { query.cancel() }

            for await batch in query {
                guard !Task.isCancelled else { return }
                members = NIP29ViewProjection.members(from: batch.rows)
                membershipError = nil
                hasReceivedMembership = true
                hasMembershipMetadata = batch.rows.contains { $0.kind == 39_002 }
            }
        } catch {
            guard !Task.isCancelled else { return }
            membershipError = error.localizedDescription
        }
    }

    private func observeAdmins() async {
        do {
            let query = try await queryOpening.filter(
                engine,
                NMPFilter(
                    kinds: [39_001],
                    tags: ["d": .literal([groupID])],
                    limit: 20
                )
            )
            defer { query.cancel() }

            for await batch in query {
                guard !Task.isCancelled else { return }
                admins = NIP29ViewProjection.admins(from: batch.rows)
                adminError = nil
            }
        } catch {
            guard !Task.isCancelled else { return }
            adminError = error.localizedDescription
        }
    }

    private func observeProfiles() async {
        // kind:0 for every pubkey the room can show — message authors, listed
        // members, admins (the tenex-edge backend surfaces here), and
        // live-session authors — via a reactive union binding so demand grows
        // as new pubkeys appear. NMP owns the routing; the app only declares
        // which authors it cares about, never a hand-kept list.
        //
        // Each derived inner filter carries the SAME limit as the display query
        // it mirrors below. Without a limit the engine must materialize the
        // group's entire kind:9 history just to project its authors — decoding
        // and signature-parsing thousands of events on entry, which stalls the
        // room for seconds in a busy channel. Bounding the derivation to the
        // set we actually render keeps the author demand cheap and correct: we
        // never resolve a profile for a message the timeline does not show.
        let authors: NMPBinding = .setOp(.union, [
            .derived(
                inner: NMPFilter(kinds: [9], tags: ["h": .literal([groupID])], limit: 200),
                project: .authors
            ),
            .derived(
                inner: NMPFilter(kinds: [39_002], tags: ["d": .literal([groupID])], limit: 20),
                project: .tag("p")
            ),
            .derived(
                inner: NMPFilter(kinds: [39_001], tags: ["d": .literal([groupID])], limit: 20),
                project: .tag("p")
            ),
            .derived(
                inner: NMPFilter(kinds: [30_315], tags: ["h": .literal([groupID])], limit: 100),
                project: .authors
            )
        ])

        do {
            let query = try await queryOpening.filter(
                engine,
                NMPFilter(kinds: [0], authors: authors, limit: 500)
            )
            defer { query.cancel() }

            for await batch in query {
                guard !Task.isCancelled else { return }
                profiles = RoomProfileProjection.profiles(from: batch.rows)
                profileError = nil
            }
        } catch {
            guard !Task.isCancelled else { return }
            profileError = error.localizedDescription
        }
    }

    /// Send a normal room message through NMP's typed NIP-29 composition.
    /// The timeline receives the canonical accepted event through `observeContent`;
    /// it does not create an app-owned pending message.
    func sendMessage(_ request: ComposerRequest, author: String) async -> String? {
        guard request.recipients.isEmpty, request.reply == nil else {
            return "Mentions and replies require the pending NMP group-message API."
        }
        return await sendGroupMessage(request.content, extraTags: [], author: author)
    }

    /// Send a tenex-edge management command as a room message p-tagging the
    /// selected backend. This shares the normal typed NIP-29 write path.
    func sendManagementCommand(_ command: String, backendPubkey: String, author: String) async -> String? {
        await sendGroupMessage(command, extraTags: [["p", backendPubkey]], author: author)
    }

    private func sendGroupMessage(
        _ content: String,
        extraTags: [[String]],
        author: String
    ) async -> String? {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Messages cannot be empty."
        }

        do {
            let intent = try groupSendIntent(
                host: hostRelay,
                groupId: groupID,
                authorPubkey: author,
                createdAt: UInt64(Date().timeIntervalSince1970),
                kind: 9,
                content: content,
                extraTags: extraTags,
                recentRows: contentRows
            )
            let receipt = try await engine.publishComposed(intent)
            for await status in receipt.status {
                if let failure = deliveryFailure(for: status) {
                    return failure
                }
                if case .acked = status {
                    return nil
                }
            }
            return "Message delivery ended without relay acknowledgement."
        } catch {
            return error.localizedDescription
        }
    }

    private func deliveryFailure(for status: WriteStatus) -> String? {
        switch status {
        case .rejected(_, let reason):
            return "The relay rejected the message: \(reason)"
        case .failed(let reason):
            return reason
        case .gaveUp(let relay):
            return "Could not deliver the message to \(relay)."
        case .persistenceBlocked(let relay):
            return "Could not persist the message for \(relay)."
        case .routePersistenceBlocked(let relay):
            return "Could not persist message routing for \(relay)."
        case .outcomeUnknown(let relay):
            return "Message delivery outcome for \(relay) is unknown."
        default:
            return nil
        }
    }
}
