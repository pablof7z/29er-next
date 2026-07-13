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
        Group {
            if #available(iOS 26.0, *) {
                liquidGlassContent
            } else {
                fallbackContent
            }
        }
    }

    @available(iOS 26.0, *)
    private var liquidGlassContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if canSend {
                liquidGlassComposer
            } else {
                liquidGlassSignedOutComposer
            }

            if isSending {
                Label("Sending…", systemImage: "arrow.up.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(in: .capsule)
                    .accessibilityIdentifier("room-composer-sending")
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular.tint(.red.opacity(0.12)), in: .capsule)
                    .accessibilityIdentifier("room-composer-error")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    @available(iOS 26.0, *)
    private var liquidGlassComposer: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .frame(minHeight: 46)
                    .glassEffect(in: .rect(cornerRadius: 22))
                    .disabled(isSending)
                    .accessibilityIdentifier("room-message-composer")

                Button(action: submit) {
                    if isSending {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(canSubmit ? .white : .secondary)
                    }
                }
                .frame(width: 56, height: 56)
                .contentShape(Circle())
                .buttonStyle(.glassProminent)
                .tint(canSubmit ? .blue : .gray)
                .disabled(!canSubmit || isSending)
                .accessibilityLabel("Send message")
                .accessibilityIdentifier("room-message-send")
            }
        }
    }

    @available(iOS 26.0, *)
    private var liquidGlassSignedOutComposer: some View {
        Label("Sign in to write", systemImage: "lock.fill")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(in: .capsule)
            .accessibilityIdentifier("room-composer-signed-out")
    }

    private var fallbackContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if canSend {
                HStack(alignment: .bottom, spacing: 12) {
                    TextField("Message", text: $draft, axis: .vertical)
                        .lineLimit(1...5)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isSending)
                        .accessibilityIdentifier("room-message-composer")

                    Button(action: submit) {
                        if isSending {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.headline.weight(.semibold))
                        }
                    }
                    .frame(width: 56, height: 56)
                    .contentShape(Circle())
                    .background(Color.accentColor.opacity(canSubmit ? 0.9 : 0.2), in: .circle)
                    .buttonStyle(.plain)
                    .disabled(!canSubmit || isSending)
                    .accessibilityLabel("Send message")
                    .accessibilityIdentifier("room-message-send")
                }
            } else {
                Label("Sign in to write", systemImage: "lock.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.thinMaterial, in: .capsule)
                    .accessibilityIdentifier("room-composer-signed-out")
            }

            if isSending {
                Label("Sending…", systemImage: "arrow.up.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var canSubmit: Bool {
        ChatComposerState.message(from: draft) != nil
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
