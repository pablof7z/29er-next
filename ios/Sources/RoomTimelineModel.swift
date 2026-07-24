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
    private(set) var reactionRows: [Row] = []
    private(set) var members: [RoomMember] = []
    private(set) var admins: [String] = []
    var profiles = ProfileBook()

    private(set) var chatError: String?
    private(set) var membershipError: String?
    private(set) var activityError: String?
    private(set) var adminError: String?
    private(set) var reactionError: String?
    var profileError: String?

    private(set) var hasReceivedChat = false
    private(set) var hasReceivedMembership = false
    private(set) var hasReceivedActivities = false
    private(set) var hasMembershipMetadata = false

    let engine: NMPEngine
    let groupID: String
    let hostRelay: String
    let recipient: String?
    let queryOpening: NMPQueryOpening
    let profileAuthorUpdates = ProfileAuthorUpdates()
    var lastProfileAuthors: [String]?

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
        if RoomOpenProbe.shared.isEnabled, RoomOpenProbe.shared.groupID != groupID {
            RoomOpenProbe.shared.begin(groupID: groupID)
        }
    }

    var timelineItems: [RoomTimelineItem] {
        NIP29ViewProjection.timelineItems(from: chatRows)
    }

    /// TTS29 spoken items present in the room's chat rows, indexed by event id
    /// with their narrated branches assembled.
    var tts29Catalog: TTS29Catalog {
        TTS29Catalog(rows: chatRows)
    }

    var mentionIDs: Set<String> {
        guard let recipient else { return [] }
        return MentionProjection.mentionIDs(from: chatRows, recipient: recipient)
    }

    var activities: [AgentActivity] {
        NIP29ViewProjection.activities(from: activityRows)
    }

    var reactionsByMessage: [String: [RoomReactionGroup]] {
        RoomReactionProjection.summaries(
            from: RoomReactionProjection.reactions(from: reactionRows),
            viewer: recipient
        )
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
        lastProfileAuthors = nil
        publishProfileAuthors()

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
                await self.observeReactions()
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
            let clock = ContinuousClock()
            let started = clock.now
            let query = try await queryOpening.demand(engine, demand)
            RoomOpenProbe.shared.recordObserve(
                .content,
                duration: started.duration(to: clock.now)
            )
            defer { query.cancel() }

            for try await batch in query {
                guard !Task.isCancelled else { return }
                chatRows = batch.rows
                chatError = nil
                hasReceivedChat = true
                publishProfileAuthors()
                recordContentProofSnapshotIfReady()
            }
        } catch {
            guard !Task.isCancelled else { return }
            chatError = error.localizedDescription
        }
    }

    private func observeActivities() async {
        do {
            let demand = try roomActivityDemand(host: hostRelay, groupID: groupID)
            let clock = ContinuousClock()
            let started = clock.now
            let query = try await queryOpening.demand(engine, demand)
            RoomOpenProbe.shared.recordObserve(
                .activity,
                duration: started.duration(to: clock.now)
            )
            defer { query.cancel() }

            for try await batch in query {
                guard !Task.isCancelled else { return }
                RoomOpenProbe.shared.recordSnapshot(.activity, rows: batch.rows)
                activityRows = batch.rows
                activityError = nil
                hasReceivedActivities = true
                publishProfileAuthors()
                recordContentProofSnapshotIfReady()
            }
        } catch {
            guard !Task.isCancelled else { return }
            activityError = error.localizedDescription
        }
    }

    private func observeReactions() async {
        do {
            let demand = try roomReactionsDemand(host: hostRelay, groupID: groupID)
            let query = try await queryOpening.demand(engine, demand)
            defer { query.cancel() }

            for try await batch in query {
                guard !Task.isCancelled else { return }
                reactionRows = batch.rows
                reactionError = nil
            }
        } catch {
            guard !Task.isCancelled else { return }
            reactionError = error.localizedDescription
        }
    }

    private func observeMembership() async {
        do {
            let clock = ContinuousClock()
            let started = clock.now
            let query = try await queryOpening.demand(
                engine,
                roomMembershipDemand(host: hostRelay, groupID: groupID)
            )
            RoomOpenProbe.shared.recordObserve(
                .membership,
                duration: started.duration(to: clock.now)
            )
            defer { query.cancel() }

            for try await batch in query {
                guard !Task.isCancelled else { return }
                membershipRows = batch.rows
                members = NIP29ViewProjection.members(from: membershipRows)
                RoomOpenProbe.shared.recordSnapshot(.membership, rows: batch.rows)
                membershipError = nil
                hasReceivedMembership = true
                hasMembershipMetadata = batch.rows.contains { $0.kind == 39_002 }
                publishProfileAuthors()
            }
        } catch {
            guard !Task.isCancelled else { return }
            membershipError = error.localizedDescription
        }
    }

    private func observeAdmins() async {
        do {
            let clock = ContinuousClock()
            let started = clock.now
            let query = try await queryOpening.demand(
                engine,
                roomAdminDemand(host: hostRelay, groupID: groupID)
            )
            RoomOpenProbe.shared.recordObserve(
                .admins,
                duration: started.duration(to: clock.now)
            )
            defer { query.cancel() }

            for try await batch in query {
                guard !Task.isCancelled else { return }
                RoomOpenProbe.shared.recordSnapshot(.admins, rows: batch.rows)
                admins = NIP29ViewProjection.admins(from: batch.rows)
                adminError = nil
                publishProfileAuthors()
            }
        } catch {
            guard !Task.isCancelled else { return }
            adminError = error.localizedDescription
        }
    }

    private func recordContentProofSnapshotIfReady() {
        guard hasReceivedChat, hasReceivedActivities else { return }
        RoomOpenProbe.shared.recordSnapshot(.content, rows: chatRows + activityRows)
    }

}
