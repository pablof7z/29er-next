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

    init(engine: NMPEngine, groupID: String) {
        self.engine = engine
        self.groupID = groupID
    }

    var people: RoomPeople {
        NIP29ViewProjection.people(members: members, activities: activities)
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
                await self.observeProfiles()
            }
        }
    }

    private func observeMessages() async {
        do {
            let query = try engine.observe(
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
            let query = try engine.observe(
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
            let query = try engine.observe(
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

    private func observeProfiles() async {
        // kind:0 for every pubkey the room can show — message authors, listed
        // members, and live-session authors — via a reactive union binding so
        // demand grows as new pubkeys appear. NMP owns the routing; the app
        // only declares which authors it cares about, never a hand-kept list.
        let authors: NMPBinding = .setOp(.union, [
            .derived(
                inner: NMPFilter(kinds: [9], tags: ["h": .literal([groupID])]),
                project: .authors
            ),
            .derived(
                inner: NMPFilter(kinds: [39_002], tags: ["d": .literal([groupID])]),
                project: .tag("p")
            ),
            .derived(
                inner: NMPFilter(kinds: [30_315], tags: ["h": .literal([groupID])]),
                project: .authors
            ),
        ])

        do {
            let query = try engine.observe(NMPFilter(kinds: [0], authors: authors, limit: 500))
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
}
