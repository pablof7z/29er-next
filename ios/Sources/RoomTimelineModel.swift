import Foundation
import NMP
import Observation

@MainActor
@Observable
final class RoomTimelineModel {
    enum State: Equatable {
        case loading
        case observing
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var messages: [RoomMessage] = []
    private(set) var activities: [AgentActivity] = []
    private(set) var members: [RoomMember] = []
    private(set) var admins: [String] = []
    private(set) var profiles = ProfileBook()

    private(set) var messageCoverage: Coverage = .unknown
    private(set) var activityCoverage: Coverage = .unknown
    private(set) var membershipCoverage: Coverage = .unknown

    private(set) var messageError: String?
    private(set) var activityError: String?
    private(set) var membershipError: String?

    private(set) var hasReceivedMessages = false
    private(set) var hasReceivedActivities = false
    private(set) var hasReceivedMembership = false
    private(set) var hasMembershipMetadata = false

    private let engine: NMPEngine
    private let groupID: String
    private let hostRelay: String

    init(engine: NMPEngine, groupID: String, hostRelay: String) {
        self.engine = engine
        self.groupID = groupID
        self.hostRelay = hostRelay
    }

    var people: RoomPeople {
        NIP29ViewProjection.people(members: members, activities: activities)
    }

    /// Management backends present in this room, resolved from kind:0 across
    /// members, admins, and live-session authors.
    var backends: [RoomBackend] {
        let candidates = members.map(\.pubkey) + admins + activities.map(\.author)
        return RoomBackendProjection.backends(candidatePubkeys: candidates, profiles: profiles)
    }

    /// Open a live query WITHOUT blocking the main actor. `engine.observe`
    /// blocks its caller until NMP's `on_subscribe` runs synchronously and
    /// replies — that resolution decodes the subscription's initial snapshot,
    /// which for a room with a large stored history takes real time. Every
    /// `observe*` method below runs on this `@MainActor` model, so issuing the
    /// call directly froze the UI for seconds when opening a busy room. This
    /// helper is `nonisolated`, so the blocking round-trip happens off the main
    /// thread; batches still stream back through the returned query and are
    /// applied on the main actor as before.
    private nonisolated func openQuery(_ filter: NMPFilter) async throws -> NMPQuery {
        try engine.observe(filter)
    }

    func observe() async {
        state = .observing

        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                guard let self else { return }
                await self.observeMessages()
            }
            group.addTask { [weak self] in
                guard let self else { return }
                await self.observeActivities()
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

    private func observeMessages() async {
        do {
            let query = try await openQuery(
                NMPFilter(
                    kinds: [9],
                    tags: ["h": .literal([groupID])],
                    limit: 200
                )
            )
            defer { query.cancel() }

            for await batch in query {
                guard !Task.isCancelled else { return }
                messages = NIP29ViewProjection.messages(from: batch.rows)
                messageCoverage = batch.coverage
                messageError = nil
                hasReceivedMessages = true
            }
        } catch {
            guard !Task.isCancelled else { return }
            messageError = error.localizedDescription
        }
    }

    private func observeActivities() async {
        do {
            let query = try await openQuery(
                NMPFilter(
                    kinds: [30_315],
                    tags: ["h": .literal([groupID])],
                    limit: 100
                )
            )
            defer { query.cancel() }

            for await batch in query {
                guard !Task.isCancelled else { return }
                activities = NIP29ViewProjection.activities(from: batch.rows)
                activityCoverage = batch.coverage
                activityError = nil
                hasReceivedActivities = true
            }
        } catch {
            guard !Task.isCancelled else { return }
            activityError = error.localizedDescription
        }
    }

    private func observeMembership() async {
        do {
            let query = try await openQuery(
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
                membershipCoverage = batch.coverage
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
            let query = try await openQuery(
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
            }
        } catch {
            // Admin discovery is enrichment for the backend affordance; on
            // failure the room still renders members and the timeline.
            return
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
            ),
        ])

        do {
            let query = try await openQuery(NMPFilter(kinds: [0], authors: authors, limit: 500))
            defer { query.cancel() }

            for await batch in query {
                guard !Task.isCancelled else { return }
                profiles = RoomProfileProjection.profiles(from: batch.rows)
            }
        } catch {
            // Identity is enrichment; on failure the timeline still renders
            // with the shortened-hex fallback rather than failing the room.
            return
        }
    }

    /// Send a tenex-edge management command (`add <slug>`, `list sessions`,
    /// `list agents`, …) as a kind:9 chat message that p-tags `backendPubkey`.
    /// The engine signs as `author` and routes to the group host; the backend
    /// replies inline in this room. Returns a message on failure, else nil.
    func sendManagementCommand(_ command: String, backendPubkey: String, author: String) async -> String? {
        let intent = WriteIntent(
            payload: .unsigned(
                pubkey: author,
                createdAt: UInt64(Date().timeIntervalSince1970),
                kind: 9,
                tags: [["h", groupID], ["p", backendPubkey]],
                content: command
            ),
            durability: .durable,
            routing: .authorOutbox
        )

        do {
            let receipt = try await engine.publish(intent)
            for await status in receipt.status {
                switch status {
                case .rejected(_, let reason):
                    return "The relay rejected the command: \(reason)"
                case .failed(let reason):
                    return reason
                case .gaveUp(let relay):
                    return "Could not deliver to \(relay)."
                case .sent, .acked:
                    return nil
                case .accepted, .awaitingCapability, .signed, .routed:
                    continue
                }
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
