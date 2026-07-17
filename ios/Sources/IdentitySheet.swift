import SwiftUI

struct IdentitySheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var secretKey = ""
    @State private var isReplacingIdentity = false

    var body: some View {
        Group {
            #if os(macOS)
            macContent
            #else
            mobileContent
            #endif
        }
        .platformIdentityPresentation()
        .interactiveDismissDisabled(model.isSigningIn)
        .onDisappear {
            secretKey.removeAll(keepingCapacity: false)
            model.clearIdentityError()
        }
    }

    private var mobileContent: some View {
        NavigationStack {
            Form {
                if let pubkey = model.activePubkey {
                    signedInContent(pubkey: pubkey)
                } else {
                    signedOutContent
                }
            }
            .navigationTitle(model.activePubkey == nil ? "Sign In" : "Account")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    #if os(macOS)
    private var macContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            macHeader

            Divider()

            if let pubkey = model.activePubkey {
                macSignedInContent(pubkey: pubkey)
            } else {
                macSignedOutContent
            }
        }
        .background(PlatformSupport.windowBackground)
    }

    private var macHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: model.activePubkey == nil ? "key.fill" : "person.crop.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 42, height: 42)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(model.activePubkey == nil ? "Sign in to 29er Next" : "Your account")
                    .font(.title2.weight(.semibold))
                Text(
                    model.activePubkey == nil
                        ? "Use your Nostr secret key to send messages."
                        : "This account is available when the app starts."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(24)
    }

    private var macSignedOutContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Nostr secret key")
                    .font(.headline)
                SecureField("nsec1… or 64-character secret hex", text: $secretKey)
                    .textFieldStyle(.roundedBorder)
                    .privacySensitive()
                    .disabled(model.isSigningIn)
                    .onSubmit { Task { await submit() } }
                    .accessibilityIdentifier("identity-secret-field")
            }

            Label {
                Text(
                    "NMP stores this key as plaintext in the app sandbox for automatic sign-in. "
                        + "It is not protected by Keychain or hardware-backed encryption."
                )
                .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock.open.fill")
                    .foregroundStyle(.orange)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(12)
            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

            if let identityError = model.identityError {
                Label(identityError, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("identity-close-button")
                Spacer()
                Button {
                    Task { await submit() }
                } label: {
                    if model.isSigningIn {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Sign In")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
                .accessibilityIdentifier("identity-sign-in-button")
            }
        }
        .padding(24)
    }

    private func macSignedInContent(pubkey: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if let profile = model.generatedIdentityProfile {
                GeneratedIdentityHeader(profile: profile)
            }
            VStack(alignment: .leading, spacing: 7) {
                Label("Signed in", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Text("Public key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(pubkey.shortIdentity)
                    .monospaced()
                    .textSelection(.enabled)
            }

            Divider()

            if isReplacingIdentity {
                replacementEntry
            } else {
                HStack {
                    Button("Close") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Use Another Account") { isReplacingIdentity = true }
                }
            }
        }
        .padding(24)
    }
    #endif

    @ViewBuilder
    private func signedInContent(pubkey: String) -> some View {
        if let profile = model.generatedIdentityProfile {
            Section {
                GeneratedIdentityHeader(profile: profile)
            } footer: {
                Text("29er created this identity automatically. You can replace it at any time.")
            }
        }

        Section {
            Label("Signed in", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            LabeledContent("Public key") {
                Text(pubkey.shortIdentity)
                    .monospaced()
                    .textSelection(.enabled)
            }
        } footer: {
            Text("NMP restores this account automatically when the app starts.")
        }

        Section {
            if isReplacingIdentity {
                SecureField("nsec1… or secret hex", text: $secretKey)
                    .platformSecretEntry()
                    .privacySensitive()
                    .disabled(model.isSigningIn)
                Button {
                    Task { await submit() }
                } label: {
                    if model.isSigningIn { ProgressView() } else { Text("Replace Account") }
                }
                .disabled(!canSubmit)
            } else {
                Button("Use Another Account") { isReplacingIdentity = true }
            }
        } footer: {
            Text("The entered account replaces the current local identity after NMP validates it.")
        }
    }

    @ViewBuilder
    private var signedOutContent: some View {
        Section {
            SecureField("nsec1… or secret hex", text: $secretKey)
                .platformSecretEntry()
                .privacySensitive()
                .disabled(model.isSigningIn)
        } header: {
            Text("Nostr secret key")
        } footer: {
            Text(
                "NMP saves the key as plaintext in this app's sandbox for automatic login. "
                    + "It is not protected by Keychain or hardware-backed encryption."
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
        let didReplace = await model.signIn(secretKey: submittedKey)
        submittedKey.removeAll(keepingCapacity: false)
        if didReplace {
            dismiss()
        }
    }

    private var canSubmit: Bool {
        !secretKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.isSigningIn
    }

    #if os(macOS)
    private var replacementEntry: some View {
        VStack(alignment: .leading, spacing: 12) {
            SecureField("nsec1… or 64-character secret hex", text: $secretKey)
                .textFieldStyle(.roundedBorder)
                .privacySensitive()
                .disabled(model.isSigningIn)
                .onSubmit { Task { await submit() } }
            if let identityError = model.identityError {
                Label(identityError, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Button("Cancel") { isReplacingIdentity = false }
                Spacer()
                Button("Replace Account") { Task { await submit() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
        }
    }
    #endif
}
