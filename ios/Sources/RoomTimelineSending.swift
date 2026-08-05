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
            let facts = try roomGroup(host: hostRelay, groupID: groupID).publish(
                engine: engine,
                authorPubkeyHex: author,
                kind: RoomKind.chat,
                tags: ChatMessageTags.rows(recipients: recipientPubkeys, reply: reply, relay: hostRelay),
                content: content
            )
            watchWrite(facts, subject: "message")
            return nil
        } catch {
            return WriteFailureText.startFailure(error, action: "message")
        }
    }

    /// Report a write that settled badly, long after the composer let go.
    ///
    /// This is INSPECTION, not waiting: nothing a person can see is blocked
    /// on it, and a write that parks on an absent signer or an unresolved
    /// route simply never reports, which is correct -- no clock ends either.
    /// The room owns the watch, so leaving the room drops it; NMP's custody
    /// of the write is untouched.
    func watchWrite(_ facts: NMPGroupWriteFacts, subject: String) {
        let id = UUID()
        writeWatchers[id] = Task { [weak self] in
            let failure = await WriteReport.failure(draining: facts, subject: subject)
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
    /// A group write returns no receipt id and hardcodes `correlation: None`
    /// (nmp#1244), so the frozen event id is the one thing an app can match
    /// on -- and it can only match it against events already in its own
    /// query, which is exactly what an accepted write is.
    ///
    /// One inspection, when the room's first rows land. The door never blocks
    /// and never streams, so there is nothing here to poll.
    func reportStrandedWrites() {
        guard writeFailure == nil, let entries = try? engine.publishQueue() else { return }
        let mine = Set(chatRows.map(\.id))
        for entry in entries where mine.contains(entry.eventID) {
            guard let outcome = entry.outcome else { continue }
            var report = WriteReport(subject: "message")
            report.record(.signing(entry.signing))
            for (relay, state) in entry.relayStates {
                report.record(.relay(relay: relay, state: state))
            }
            report.record(.outcome(outcome))
            if let failure = report.failure {
                writeFailure = failure
                return
            }
        }
    }
}

/// The tag rows a group chat message carries beyond the `h` row NMP itself
/// stamps at publish time.
///
/// NOT NMP-owned yet, and it should be: NMP already owns this schema in Rust
/// (`crates/nmp-nipc7`, `compose_chat`/`compose_chat_reply` with NIP-C7's
/// NIP-18 `q` reply row) but that crate is not in `nmp-ffi`'s dependency set
/// and no `composeChat` reaches Swift, so a native consumer cannot use it
/// (nmp#1243). Delete this in favour of NMP's composer the moment it crosses
/// the FFI.
enum ChatMessageTags {
    static func rows(
        recipients: [String],
        reply: ComposerReply?,
        relay: String
    ) -> [[String]] {
        var tags: [[String]] = []
        if let reply {
            tags.append(["q", reply.eventID, relay, reply.author.pubkey])
        }
        var mentioned = Set<String>()
        for pubkey in recipients where !pubkey.isEmpty && mentioned.insert(pubkey).inserted {
            tags.append(["p", pubkey])
        }
        return tags
    }
}
