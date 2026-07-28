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
                    List {
                        if recipients.count > 1 {
                            everyoneButton
                        }
                        ForEach(recipients) { recipient in
                            recipientButton(recipient)
                        }
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

    private var isEveryoneSelected: Bool {
        ChatComposerState.everyoneIsSelected(
            pickable: recipients,
            selectedRecipients: selectedRecipients,
            requiredRecipientID: requiredRecipientID
        )
    }

    private var everyoneButton: some View {
        Button {
            selectedRecipients = ChatComposerState.togglingEveryone(
                pickable: recipients,
                selectedRecipients: selectedRecipients,
                requiredRecipientID: requiredRecipientID
            )
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.3.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Everyone")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("Mention all \(recipients.count) in this room")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isEveryoneSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("composer-recipient-everyone")
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
            dismiss()
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
                    if let summary = recipient.activitySummary {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(recipient.activity?.isBusy == true ? Color.orange : Color.green)
                                .frame(width: 6, height: 6)
                            Text(summary)
                                .lineLimit(2)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
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
