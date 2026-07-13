import SwiftUI

struct ComposerReplySummary: View {
    let reply: ComposerReply
    let cancel: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.caption)
                .foregroundStyle(.tint)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text("Replying to \(reply.author.mentionLabel)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                Text(reply.preview.isEmpty ? "Message" : reply.preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: cancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel reply")
            .accessibilityIdentifier("room-message-reply-cancel")
        }
        .accessibilityIdentifier("room-message-reply")
    }
}

struct ComposerMentionChip: View {
    let recipient: ComposerRecipient
    let isRequired: Bool
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(recipient.mentionLabel)
                .font(.caption.weight(.semibold))
            if !isRequired {
                Button(action: remove) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(recipient.mentionLabel)")
            }
        }
        .foregroundStyle(.tint)
        .padding(.leading, 9)
        .padding(.trailing, isRequired ? 9 : 3)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.13), in: .capsule)
        .accessibilityIdentifier("composer-mention-\(recipient.pubkey)")
    }
}

struct ComposerDeliveryStatus: View {
    let isSending: Bool
    let errorMessage: String?

    @ViewBuilder
    var body: some View {
        if isSending {
            Label("Sending…", systemImage: "arrow.up.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .accessibilityIdentifier("room-composer-sending")
        } else if let errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.horizontal, 14)
                .accessibilityIdentifier("room-composer-error")
        }
    }
}
