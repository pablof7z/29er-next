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
        return await sendGroupMessage(
            content,
            recipientPubkeys: request.recipients.map(\.pubkey),
            reply: request.reply
        )
    }

    func sendManagementCommand(_ command: String, backendPubkey: String) async -> String? {
        await sendGroupMessage(command, recipientPubkeys: [backendPubkey], reply: nil)
    }

    private func sendGroupMessage(
        _ content: String,
        recipientPubkeys: [String],
        reply: ComposerReply?
    ) async -> String? {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Messages cannot be empty."
        }
        guard let author = recipient else { return "Sign in to send a message." }

        do {
            let status = try roomGroup(host: hostRelay, groupID: groupID).publish(
                engine: engine,
                authorPubkeyHex: author,
                kind: RoomKind.chat,
                tags: ChatMessageTags.rows(recipients: recipientPubkeys, reply: reply, relay: hostRelay),
                content: content
            )
            return await firstFailure(in: status)
        } catch {
            return error.localizedDescription
        }
    }

    /// Drain a group write's receipt stream until NMP accepts it or something
    /// terminal goes wrong.
    ///
    /// `.accepted` is the point at which NMP has committed the write into its
    /// canonical store -- and therefore into this room's live query, whose
    /// provenance reports it as in cache with `relays: []` until a relay
    /// carries it. That is a real state, not a loading placeholder, so the
    /// composer hands control back here instead of blocking on `.acked`.
    func firstFailure(in status: NMPGroupWriteStatus) async -> String? {
        do {
            for try await frame in status {
                if let failure = deliveryFailure(for: frame) { return failure }
                if case .accepted = frame { return nil }
            }
            return "Message delivery ended before NMP accepted it."
        } catch {
            return error.localizedDescription
        }
    }

    func deliveryFailure(for status: WriteStatus) -> String? {
        WriteFailureText.message(for: status, subject: "message")
    }
}

/// The tag rows a group chat message carries beyond the `h` row NMP itself
/// stamps at publish time.
///
/// NOT NMP-owned yet, and it should be: NMP already owns this schema in Rust
/// (`crates/nmp-nipc7`, `compose_chat`/`compose_chat_reply` with NIP-C7's
/// NIP-18 `q` reply row) but that crate is not in `nmp-ffi`'s dependency set
/// and no `composeChat` reaches Swift, so a native consumer cannot use it.
/// Delete this in favour of NMP's composer the moment it crosses the FFI.
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
