import SwiftUI

#if os(iOS)
struct SystemSettingsView: View {
    @Environment(VoiceProviderStore.self) private var providers
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("System") {
                    NavigationLink {
                        VoiceSettingsView()
                    } label: {
                        SettingsValueRow(
                            title: "Voice",
                            systemImage: "waveform",
                            value: providers.activeName
                        )
                    }
                    .accessibilityIdentifier("system-voice-settings")
                }
            }
            .navigationTitle("System")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct VoiceSettingsView: View {
    @Environment(VoiceProviderStore.self) private var providers

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    VoiceProviderListView()
                } label: {
                    SettingsValueRow(
                        title: "Provider",
                        systemImage: "captions.bubble",
                        value: providers.activeName
                    )
                }
                .accessibilityIdentifier("voice-provider-settings")
            } header: {
                Text("Speech to Text")
            } footer: {
                providerPrivacyText
            }

            Section {
                Label("Unsent recordings stay in their original chat.", systemImage: "lock.doc")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Drafts")
            } footer: {
                Text("Recordings remain on this device until you send or deliberately delete them.")
            }
        }
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var providerPrivacyText: Text {
        switch providers.activeConfiguration.kind {
        case .apple:
            Text("Apple transcription may run on-device when supported by this iPhone and language.")
        case .elevenLabs:
            Text("Audio is sent to ElevenLabs for transcription using the active configuration.")
        }
    }
}

private struct SettingsValueRow: View {
    let title: String
    let systemImage: String
    let value: String

    var body: some View {
        Label {
            HStack {
                Text(title)
                Spacer()
                Text(value)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
        }
    }
}
#endif
