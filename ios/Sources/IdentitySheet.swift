import SwiftUI

struct IdentitySheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var secretKey = ""

    var body: some View {
        NavigationStack {
            Form {
                if let pubkey = model.activePubkey {
                    signedInContent(pubkey: pubkey)
                } else {
                    signedOutContent
                }
            }
            .navigationTitle(model.activePubkey == nil ? "Session Sign In" : "Session Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(model.isSigningIn)
        .onDisappear {
            secretKey.removeAll(keepingCapacity: false)
            model.clearIdentityError()
        }
    }

    @ViewBuilder
    private func signedInContent(pubkey: String) -> some View {
        Section {
            Label("Signed in", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            LabeledContent("Public key") {
                Text(pubkey.shortIdentity)
                    .monospaced()
                    .textSelection(.enabled)
            }
        } footer: {
            Text("This account exists only in the current NMP engine session.")
        }

        Section {
            Button("End Session", role: .destructive) {
                model.endIdentitySession()
                dismiss()
            }
        } footer: {
            Text("Ending the session shuts down the credential-owning engine and starts a fresh read-only engine.")
        }
    }

    @ViewBuilder
    private var signedOutContent: some View {
        Section {
            SecureField("nsec1… or secret hex", text: $secretKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.password)
                .privacySensitive()
                .disabled(model.isSigningIn)
        } header: {
            Text("Nostr secret key")
        } footer: {
            Text(
                "Your key is handed once to NMP and is not saved by 29er Next. "
                    + "This is a session import, not persistent secure login."
            )
        }

        if let identityError = model.identityError {
            Section {
                Label(identityError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }

        Section {
            Button {
                Task { await submit() }
            } label: {
                HStack {
                    Spacer()
                    if model.isSigningIn {
                        ProgressView()
                    } else {
                        Text("Sign In")
                    }
                    Spacer()
                }
            }
            .disabled(secretKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSigningIn)
        }
    }

    private func submit() async {
        var submittedKey = secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        secretKey.removeAll(keepingCapacity: false)
        await model.signIn(secretKey: submittedKey)
        submittedKey.removeAll(keepingCapacity: false)
        if model.activePubkey != nil {
            dismiss()
        }
    }
}

private extension String {
    var shortIdentity: String {
        guard count > 20 else { return self }
        return "\(prefix(10))…\(suffix(10))"
    }
}
