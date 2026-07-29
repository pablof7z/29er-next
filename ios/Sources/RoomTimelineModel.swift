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
    var messageDeliveryState = MessageDeliveryState.idle
    var messageReceiptPresentation = MessageReceiptPresentation()
    var reactionReceiptPresentation = ReactionReceiptPresentation()
    @ObservationIgnored var reactionTasks: [UUID: Task<Void, Never>] = [:]
    let engine: NMPEngine
    let groupID: String
    let hostRelay: String
    let recipient: String?
    let queryOpening: NMPQueryOpening
    let profileAuthorUpdates = ProfileAuthorUpdates()
    let messageReceiptStore: DurableReceiptStore
    let reactionReceiptStore: DurableReceiptStore
    var lastProfileAuthors: [String]?

    init(
        engine: NMPEngine,
        groupID: String,
        hostRelay: String,
        storeGeneration: String,
        recipient: String? = nil,
        queryOpening: NMPQueryOpening = .live,
        messageReceiptStore: DurableReceiptStore? = nil,
        reactionReceiptStore: DurableReceiptStore? = nil
    ) {
        self.engine = engine
        self.groupID = groupID
        self.hostRelay = hostRelay
        self.recipient = recipient
        self.queryOpening = queryOpening
        self.messageReceiptStore = messageReceiptStore ?? DurableReceiptStore(
            storeGeneration: storeGeneration,
            scope: .message,
            account: recipient ?? "signed-out",
            host: hostRelay,
            groupID: groupID
        )
        self.reactionReceiptStore = reactionReceiptStore ?? DurableReceiptStore(
            storeGeneration: storeGeneration,
            scope: .reaction,
            account: recipient ?? "signed-out",
            host: hostRelay,
            groupID: groupID
        )
        if RoomOpenProbe.shared.isEnabled, RoomOpenProbe.shared.groupID != groupID {
            RoomOpenProbe.shared.begin(groupID: groupID)
        }
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
            group.addTask { [weak self] in
                guard let self else { return }
                await self.observeRetainedMessageReceipts()
            }
            group.addTask { [weak self] in
                guard let self else { return }
                await self.observeRetainedReactionReceipts()
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
