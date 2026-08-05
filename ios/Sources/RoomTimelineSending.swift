import Foundation
import NMP

extension RoomTimelineModel {
    /// The canonical accepted event returns through `observeChat`; this never
    /// creates an app-owned pending-message mirror.
    func sendMessage(_ request: ComposerRequest) async -> String? {
        let uploader = BlossomAttachmentUploader(engine: engine)
        var attachmentURLs: [URL] = []
        do {
            for attachment in request.attachments {
                try Task.checkCancellation()
                attachmentURLs.append(try await uploader.upload(attachment, to: hostRelay))
            }
        } catch {
            return error.localizedDescription
        }
        guard let content = ChatComposerState.messageContent(
            draft: request.content,
            attachmentURLs: attachmentURLs
        ) else {
            return "Messages cannot be empty."
        }
        return sendGroupMessage(
            content,
            recipientPubkeys: request.recipients.map(\.pubkey),
            reply: request.reply
        )
    }

    func sendManagementCommand(_ command: String, backendPubkey: String) -> String? {
        sendGroupMessage(command, recipientPubkeys: [backendPubkey], reply: nil)
    }

    /// Hand the message to NMP and stop.
    ///
    /// `publish` returning IS acceptance -- there is no `.accepted` frame to
    /// wait for any more, because there is nothing left to ask. The event is
    /// in NMP's canonical store and therefore already in this room's live
    /// query, whose provenance reports it as in cache with `relays: []` until
    /// a relay carries it. That is a real state, not a loading placeholder.
    ///
    /// The only failures left here are the two `publish` itself refuses on:
    /// NMP could not write anything down, or the instruction could not
    /// resolve. Everything else is in NMP's custody and settles on the facts
    /// stream, which `watchWrite` reads without anybody waiting.
    private func sendGroupMessage(
        _ content: String,
        recipientPubkeys: [String],
        reply: ComposerReply?
    ) -> String? {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Messages cannot be empty."
        }
        guard let author = recipient else { return "Sign in to send a message." }

        do {
            let receipt = try roomGroup(host: hostRelay, groupID: groupID).publish(
                engine: engine,
                authorPubkeyHex: author,
                payload: try ChatDraft.payload(
                    content: content,
                    recipientPubkeys: recipientPubkeys,
                    replyTarget: replyTarget(for: reply)
                )
            )
            watchWrite(receipt, subject: "message")
            return nil
        } catch RoomSendFailure.replyTargetNotLoaded {
            return "The message being replied to is no longer loaded. Reopen the room and try again."
        } catch {
            return WriteFailureText.startFailure(error, action: "message")
        }
    }

    /// The canonical row being replied to, which is what NMP's tagging door
    /// reads the thread position out of.
    ///
    /// `ComposerReply` carries an id, an author and a preview because those
    /// are what the reply banner draws. They are a presentation model, and
    /// this app deliberately does not rebuild a protocol reference from one --
    /// the row NMP delivered is the only acceptable input.
    private func replyTarget(for reply: ComposerReply?) throws -> Row? {
        guard let reply else { return nil }
        guard let target = chatRows.first(where: { $0.id == reply.eventID }) else {
            throw RoomSendFailure.replyTargetNotLoaded
        }
        return target
    }

    /// Report a write that settled badly, long after the composer let go.
    ///
    /// This is INSPECTION, not waiting: nothing a person can see is blocked
    /// on it, and a write that parks on an absent signer or an unresolved
    /// route simply never reports, which is correct -- no clock ends either.
    /// The room owns the watch, so leaving the room drops it; NMP's custody
    /// of the write is untouched.
    func watchWrite(_ receipt: Receipt, subject: String) {
        let id = UUID()
        writeWatchers[id] = Task { [weak self] in
            let failure = await WriteReport.failure(draining: receipt.status, subject: subject)
            guard let self, !Task.isCancelled else { return }
            self.writeWatchers[id] = nil
            if let failure { self.writeFailure = failure }
        }
    }

    func stopWatchingWrites() {
        writeWatchers.values.forEach { $0.cancel() }
        writeWatchers.removeAll()
    }

    /// Report a write that was already over before this room was opened.
    ///
    /// A watch dies with the process; NMP's custody does not, so after a
    /// relaunch the publish queue is the only place the verdict still exists.
    /// A group write now returns the ordinary `Receipt`, store-issued id
    /// included, but that id lived in a process that is gone -- keeping it
    /// would be app-owned write state, which is exactly what this app does
    /// not do. The frozen event id is the handle that survives, and it can
    /// only be matched against events already in this room's own query, which
    /// is exactly what an accepted write is.
    ///
    /// One inspection, when the room's first rows land. The door never streams
    /// and never waits for settlement, so there is nothing here to poll.
    func reportStrandedWrites() {
        guard writeFailure == nil else { return }
        let mine = Set(chatRows.map(\.id))
        guard !mine.isEmpty else { return }

        let engine = engine
        let id = UUID()
        writeWatchers[id] = Task { [weak self] in
            let failure = await Self.strandedFailure(engine: engine, eventIDs: mine)
            guard let self, !Task.isCancelled else { return }
            self.writeWatchers[id] = nil
            if let failure, self.writeFailure == nil { self.writeFailure = failure }
        }
    }

    /// `nonisolated` so the engine round-trip happens off the main actor. It
    /// answers immediately, but opening a room is the worst moment to find
    /// out otherwise.
    nonisolated private static func strandedFailure(
        engine: NMPEngine,
        eventIDs: Set<String>
    ) async -> String? {
        guard let entries = try? engine.publishQueue() else { return nil }
        for entry in entries where eventIDs.contains(entry.eventID) {
            guard let outcome = entry.outcome else { continue }
            var report = WriteReport(subject: "message")
            report.record(.signing(entry.signing))
            for (relay, state) in entry.relayStates {
                report.record(.relay(relay: relay, state: state))
            }
            report.record(.outcome(outcome))
            if let failure = report.failure { return failure }
        }
        return nil
    }
}

/// A refusal this app can state before NMP is involved at all.
enum RoomSendFailure: Error {
    /// A reply was composed against a message this room is no longer holding,
    /// so there is no row for NMP's tagging door to read the thread position
    /// out of. The app deliberately does not reconstruct one from the id and
    /// author it kept for display.
    case replyTargetNotLoaded
}

/// The draft one chat message publishes.
///
/// A reply is composed by NMP's tagging door and nothing else: `chatReply`
/// decides the kind, the `e` row, the thread position and the parent author's
/// `p` row, all read out of the target's own rows. This app used to state all
/// of that itself and stated it wrongly -- it emitted NIP-18's `q` QUOTE row,
/// whose entire purpose is keeping the referenced event OUT of the thread, so
/// no NIP-C7 client could render a 29er reply as a reply.
///
/// What is left is the `p` rows naming people the message addresses, and that
/// should not be here either: NMP writes a NIP-27 `nostr:npub…` token and its
/// `p` row from one statement (`nmp-grammar`'s interpolated content) precisely
/// so the two cannot diverge, and `nmp-nipc7::compose_chat` composes the
/// top-level message itself. Neither crosses the FFI, so a Swift consumer that
/// lets somebody @-mention a person still names the row here, and still names
/// kind 9 for a message that is not a reply (nmp#964). Delete both the moment
/// that door lands.
enum ChatDraft {
    static func payload(
        content: String,
        recipientPubkeys: [String],
        replyTarget: Row?
    ) throws -> WritePayload {
        guard let replyTarget else {
            return .event(
                kind: RoomKind.chat,
                tags: mentionRows(recipientPubkeys, alreadyNamed: []),
                content: content
            )
        }
        guard case .event(let kind, let tags, _, let createdAt) = try chatReply(to: replyTarget)
        else {
            // `chatReply` composes a draft, never a signed event, so this arm
            // is unreachable. It exists because pattern-matching NMP's own
            // value is the honest way to read it, not because a fallback
            // reply shape is acceptable.
            throw RoomSendFailure.replyTargetNotLoaded
        }
        return .event(
            kind: kind,
            tags: tags + mentionRows(recipientPubkeys, alreadyNamed: namedPubkeys(in: tags)),
            content: content,
            createdAt: createdAt
        )
    }

    private static func mentionRows(
        _ recipients: [String],
        alreadyNamed: Set<String>
    ) -> [[String]] {
        var mentioned = alreadyNamed
        return recipients.compactMap { pubkey in
            guard !pubkey.isEmpty, mentioned.insert(pubkey).inserted else { return nil }
            return ["p", pubkey]
        }
    }

    /// The pubkeys an NMP-composed draft already names, so this app never
    /// writes a second row for somebody NMP has already tagged.
    private static func namedPubkeys(in tags: [[String]]) -> Set<String> {
        Set(tags.compactMap { $0.count >= 2 && $0[0] == "p" ? $0[1] : nil })
    }
}
