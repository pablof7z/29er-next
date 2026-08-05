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
    private(set) var activityRows: [Row] = []
    private(set) var reactionRows: [Row] = []

    /// The room's relay-signed lists, exactly as NMP delivered them. These
    /// are complete values, never accumulations: each delivery replaces the
    /// last, so a removed member or a demoted admin disappears here the same
    /// update the relay's new record arrives.
    private(set) var members: [NMPListedSubject] = []
    private(set) var admins: [NMPListedSubject] = []
    /// `nil` until the first delivery. NMP's rollup over the scope's hosts,
    /// carried on the snapshot itself so a loading state never has to reach
    /// into per-host records to find one.
    private(set) var recordsAvailability: NMPGroupAvailability?

    /// The room's records are still being established. `nil` availability is
    /// "no delivery yet"; `.acquiring` is NMP's own word for the same thing
    /// once the observation is open.
    var isAcquiringRecords: Bool {
        recordsAvailability == nil || recordsAvailability == .acquiring
    }
    /// Whether the host has published a kind:39002 at all. Distinct from an
    /// empty `members`: NMP returns what the relay published, and an empty
    /// member list is an empty member list.
    private(set) var hasMemberList = false
    var profiles = ProfileBook()

    private(set) var chatError: String?
    private(set) var activityError: String?
    private(set) var recordsError: String?
    private(set) var reactionError: String?
    var profileError: String?

    /// A write this room started that later settled badly. Never a state the
    /// composer waits in: it appears after the fact, on a message already
    /// visible in the timeline, and the reader dismisses it. See
    /// `RoomTimelineSending.watchWrite`.
    var writeFailure: String?
    var writeWatchers: [UUID: Task<Void, Never>] = [:]

    private(set) var hasReceivedChat = false
    private(set) var hasReceivedActivities = false

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
        NIP29ViewProjection.people(memberPubkeys: members.map(\.pubkey), activities: activities)
    }

    var composerRecipients: [ComposerRecipient] {
        RoomComposerProjection.recipients(
            from: people,
            recentSpeakers: timelineItems.compactMap { $0.message?.author },
            profiles: profiles,
            excluding: recipient
        )
    }

    func composerReply(to message: RoomMessage) -> ComposerReply {
        RoomComposerProjection.reply(to: message, people: people, profiles: profiles)
    }

    /// The default recipient a new message auto-tags with: the most recent
    /// speaker other than the signed-in user (#118).
    var lastOtherSpeaker: ComposerRecipient? {
        RoomComposerProjection.lastOtherSpeaker(
            in: timelineItems,
            excluding: recipient,
            people: people,
            profiles: profiles
        )
    }

    /// Management backends present in this room, resolved from kind:0 across
    /// members, admins, and live-session authors.
    var backends: [RoomBackend] {
        let candidates = members.map(\.pubkey) + admins.map(\.pubkey) + activities.map(\.author)
        return RoomBackendProjection.backends(candidatePubkeys: candidates, profiles: profiles)
    }

    func observe() async {
        state = .observing
        lastProfileAuthors = nil
        publishProfileAuthors()
        defer { stopWatchingWrites() }

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
                await self.observeGroupRecords()
            }
            group.addTask { [weak self] in
                guard let self else { return }
                await self.observeProfiles()
            }
        }
    }

    private func observeChat() async {
        do {
            let clock = ContinuousClock()
            let started = clock.now
            let query = try await queryOpening.query(
                engine,
                try roomChatQuery(host: hostRelay, groupID: groupID)
            )
            RoomOpenProbe.shared.recordObserve(
                .content,
                duration: started.duration(to: clock.now)
            )
            defer { query.cancel() }

            for try await batch in query {
                guard !Task.isCancelled else { return }
                chatRows = batch.rows
                chatError = nil
                if !hasReceivedChat { reportStrandedWrites() }
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
            let clock = ContinuousClock()
            let started = clock.now
            let query = try await queryOpening.query(
                engine,
                try roomActivityQuery(host: hostRelay, groupID: groupID)
            )
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
            let query = try await queryOpening.query(
                engine,
                try roomReactionsQuery(host: hostRelay, groupID: groupID)
            )
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

    /// The room's kind:39001 and kind:39002 records, through NMP's one
    /// reactive door.
    ///
    /// There is no accumulator here and no removal handling, because there is
    /// no delta to accumulate: `snapshot.members` and `snapshot.admins` are
    /// each the complete current list, so assigning them is the whole update.
    /// The previous shape -- two subscriptions folding raw `p` rows -- could
    /// only ever grow.
    private func observeGroupRecords() async {
        do {
            let clock = ContinuousClock()
            let started = clock.now
            let observation = try await queryOpening.records(engine, hostRelay, groupID)
            RoomOpenProbe.shared.recordObserve(
                .groupRecords,
                duration: started.duration(to: clock.now)
            )
            defer { observation.cancel() }

            for try await snapshot in observation {
                guard !Task.isCancelled else { return }
                members = snapshot.members
                admins = snapshot.admins
                recordsAvailability = snapshot.availability
                // The scope names exactly one host, so its own records are
                // the whole answer. `at(_:)` distinguishes "the relay
                // published no member list" from "the relay published an
                // empty one"; `members.isEmpty` cannot.
                hasMemberList = snapshot.at(hostRelay)?.members != nil
                RoomOpenProbe.shared.recordSnapshot(.groupRecords, subjects: snapshot)
                recordsError = nil
                publishProfileAuthors()
            }
        } catch {
            guard !Task.isCancelled else { return }
            recordsError = error.localizedDescription
        }
    }

    private func recordContentProofSnapshotIfReady() {
        guard hasReceivedChat, hasReceivedActivities else { return }
        RoomOpenProbe.shared.recordSnapshot(.content, rows: chatRows + activityRows)
    }

}
