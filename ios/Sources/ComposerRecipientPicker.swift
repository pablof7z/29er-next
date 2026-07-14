import SwiftUI

struct ComposerRecipientPicker: View {
    let recipients: [ComposerRecipient]
    let requiredRecipientID: String?
    @Binding var selectedRecipients: [ComposerRecipient]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if recipients.isEmpty {
                    ContentUnavailableView(
                        "No People Available",
                        systemImage: "at",
                        description: Text("People appear here from the room's durable member roster.")
                    )
                } else {
                    List(recipients) { recipient in
                        recipientButton(recipient)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Mention an Agent")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .platformRecipientPickerPresentation()
    }

    private func recipientButton(_ recipient: ComposerRecipient) -> some View {
        let isRequired = requiredRecipientID == recipient.id
        let isSelected = isRequired || selectedRecipients.contains { $0.id == recipient.id }
        return Button {
            guard !isRequired else { return }
            if isSelected {
                selectedRecipients.removeAll { $0.id == recipient.id }
            } else {
                selectedRecipients.append(recipient)
            }
        } label: {
            HStack(spacing: 12) {
                AuthorAvatar(
                    pubkey: recipient.pubkey,
                    displayName: recipient.displayName,
                    pictureURL: recipient.pictureURL,
                    size: 40
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(recipient.mentionLabel)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    if isRequired {
                        Text("Reply recipient")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("composer-recipient-\(recipient.pubkey)")
    }
}
