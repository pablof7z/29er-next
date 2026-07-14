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
    private(set) var chatRows: [Row] = []
    private(set) var membershipRows: [Row] = []
    private(set) var activityRows: [Row] = []
    private(set) var members: [RoomMember] = []
    private(set) var admins: [String] = []
    private(set) var profiles = ProfileBook()

    private(set) var chatError: String?
    private(set) var membershipError: String?
    private(set) var activityError: String?
    private(set) var adminError: String?
    private(set) var profileError: String?

    private(set) var hasReceivedChat = false
    private(set) var hasReceivedMembership = false
    private(set) var hasReceivedActivities = false
    private(set) var hasMembershipMetadata = false

    let engine: NMPEngine
    let groupID: String
    let hostRelay: String
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

    var timelineItems: [RoomTimelineItem] {
        NIP29ViewProjection.timelineItems(from: chatRows)
    }

    var mentionIDs: Set<String> {
        guard let recipient else { return [] }
        return MentionProjection.mentionIDs(from: chatRows, recipient: recipient)
    }

    var activities: [AgentActivity] {
        NIP29ViewProjection.activities(from: activityRows)
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
                await self.observeChat()
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

    private func observeChat() async {
        do {
            let demand = try roomChatDemand(host: hostRelay, groupID: groupID)
            let query = try await queryOpening.demand(engine, demand)
            defer { query.cancel() }

            for await batch in query {
                guard !Task.isCancelled else { return }
                chatRows = batch.rows
                chatError = nil
                hasReceivedChat = true
            }
        } catch {
            guard !Task.isCancelled else { return }
            chatError = error.localizedDescription
        }
    }

    private func observeActivities() async {
        do {
            let demand = try roomActivityDemand(host: hostRelay, groupID: groupID)
            let query = try await queryOpening.demand(engine, demand)
            defer { query.cancel() }

            for await batch in query {
                guard !Task.isCancelled else { return }
                activityRows = batch.rows
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
            let query = try await queryOpening.demand(
                engine,
                roomMembershipDemand(host: hostRelay, groupID: groupID)
            )
            defer { query.cancel() }

            for await batch in query {
                guard !Task.isCancelled else { return }
                membershipRows = batch.rows
                members = NIP29ViewProjection.members(from: membershipRows)
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
            let query = try await queryOpening.demand(
                engine,
                roomAdminDemand(host: hostRelay, groupID: groupID)
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
        // members, admins (the tenex-edge backend surfaces here), membership
        // event subjects, and live-session authors — via a reactive union
        // binding so demand grows as new pubkeys appear. NMP owns the routing;
        // the app only declares which authors it cares about, never a hand-kept
        // list.
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
            .derived(
                inner: NMPFilter(kinds: [9_000, 9_001], tags: ["h": .literal([groupID])], limit: 200),
                project: .tag("p")
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

}
