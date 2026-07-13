import SwiftUI

/// Bottom-of-room text composer. NMP owns the submitted event and all pending
/// write state; this view owns only the user's unsent text and receipt feedback.
struct ChatComposer: View {
    let canSend: Bool
    let send: (String) async -> String?

    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if canSend {
                signedInComposer
            } else {
                Label("Sign in to write", systemImage: "lock.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("room-composer-signed-out")
            }

            if isSending {
                Label("Sending…", systemImage: "arrow.up.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("room-composer-sending")
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("room-composer-error")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var signedInComposer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)
                .disabled(isSending)
                .accessibilityIdentifier("room-message-composer")

            Button(action: submit) {
                if isSending {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
            }
            .disabled(ChatComposerState.message(from: draft) == nil || isSending)
            .accessibilityLabel("Send message")
            .accessibilityIdentifier("room-message-send")
        }
    }

    private func submit() {
        guard let message = ChatComposerState.message(from: draft), !isSending else { return }

        isSending = true
        errorMessage = nil
        Task {
            let error = await send(message)
            guard !Task.isCancelled else { return }

            isSending = false
            if let error {
                errorMessage = error
            } else if draft == message {
                draft = ""
            }
        }
    }
}

enum ChatComposerState {
    static func message(from draft: String) -> String? {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? nil : message
    }
}
