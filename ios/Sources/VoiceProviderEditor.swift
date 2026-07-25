import Speech
import SwiftUI

#if os(iOS)
struct VoiceProviderEditor: View {
    @Environment(VoiceProviderStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var configuration: VoiceProviderConfiguration
    @State private var apiKey = ""
    @State private var makeActive = false
    @State private var errorMessage: String?
    private let isNew: Bool

    init(configuration: VoiceProviderConfiguration, isNew: Bool) {
        _configuration = State(initialValue: configuration)
        self.isNew = isNew
    }

    var body: some View {
        Form {
            Section("Configuration") {
                TextField("Name", text: $configuration.name)
                    .textInputAutocapitalization(.words)
                LabeledContent("Provider", value: configuration.kind.title)
                if isNew || configuration.id != store.activeConfigurationID {
                    Toggle("Make Active", isOn: $makeActive)
                } else {
                    LabeledContent("Status", value: "Active")
                }
            }

            languageSection

            switch configuration.kind {
            case .apple:
                appleSection
            case .elevenLabs:
                elevenLabsSections
            }

            Section {
                statusRow
            }
        }
        .navigationTitle(isNew ? "New Provider" : configuration.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if isNew { Button("Cancel") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .fontWeight(.semibold)
            }
        }
        .alert("Provider Configuration", isPresented: errorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var languageSection: some View {
        Section("Language") {
            if configuration.kind == .elevenLabs {
                Toggle(
                    "Detect Automatically",
                    isOn: $configuration.detectsLanguageAutomatically
                )
            }
            if configuration.kind == .apple || !configuration.detectsLanguageAutomatically {
                Picker("Language", selection: $configuration.languageCode) {
                    ForEach(languageOptions) { option in
                        Text(option.title).tag(option.identifier)
                    }
                }
            }
        }
    }

    private var appleSection: some View {
        Section {
            Picker("Recognition Mode", selection: $configuration.appleRecognitionMode) {
                ForEach(AppleRecognitionMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            LabeledContent("Access", value: appleAuthorizationLabel)
        } header: {
            Text("Apple Speech")
        } footer: {
            Text("On-device availability depends on this iPhone and the selected language.")
        }
    }

    @ViewBuilder
    private var elevenLabsSections: some View {
        Section {
            SecureField("API Key", text: $apiKey)
                .textContentType(.password)
                .privacySensitive()
            if let masked = store.maskedCredential(for: configuration.id) {
                LabeledContent("Stored Key", value: masked)
            }
            Picker("Model", selection: $configuration.elevenLabsModel) {
                Text("Scribe v2").tag("scribe_v2")
                Text("Scribe v1").tag("scribe_v1")
            }
        } header: {
            Text("ElevenLabs")
        } footer: {
            Text("The API key is stored in Keychain and never written to app settings.")
        }

        Section {
            Toggle("Include Audio Events", isOn: $configuration.elevenLabsTagsAudioEvents)
            Toggle("Clean Up Filler Words", isOn: $configuration.elevenLabsNoVerbatim)
                .disabled(configuration.elevenLabsModel != "scribe_v2")
            TextField(
                "Key terms, separated by commas",
                text: $configuration.elevenLabsKeyterms,
                axis: .vertical
            )
            .lineLimit(2...5)
            .disabled(configuration.elevenLabsModel != "scribe_v2")
        } header: {
            Text("Transcript")
        } footer: {
            Text(elevenLabsTranscriptFooter)
        }
    }

    private var statusRow: some View {
        HStack {
            Label(
                isLocallyReady ? "Ready" : "Needs Attention",
                systemImage: isLocallyReady ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
            )
            .foregroundStyle(isLocallyReady ? Color.green : Color.orange)
            Spacer()
            Text(configuration.kind.title)
                .foregroundStyle(.secondary)
        }
    }

    private var elevenLabsTranscriptFooter: String {
        if configuration.elevenLabsModel == "scribe_v2" {
            return "Audio is sent to ElevenLabs. Key terms may increase provider charges."
        }
        return "Audio is sent to ElevenLabs. Filler-word cleanup and key terms require Scribe v2."
    }

    private var isLocallyReady: Bool {
        guard !configuration.normalizedName.isEmpty else { return false }
        guard configuration.kind == .elevenLabs else { return true }
        return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || store.maskedCredential(for: configuration.id) != nil
    }

    private var appleAuthorizationLabel: String {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: "Allowed"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .notDetermined: "Asked at First Use"
        @unknown default: "Unavailable"
        }
    }

    private var languageOptions: [VoiceLocaleOption] {
        switch configuration.kind {
        case .apple:
            VoiceLocaleOptions.apple
        case .elevenLabs:
            VoiceLocaleOptions.elevenLabs
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func save() {
        do {
            try store.save(configuration, newCredential: apiKey)
            if makeActive { try store.activate(configuration.id) }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct VoiceLocaleOption: Identifiable {
    let identifier: String
    let title: String
    var id: String { identifier }
}

private enum VoiceLocaleOptions {
    static let apple: [VoiceLocaleOption] = SFSpeechRecognizer.supportedLocales()
        .map { locale in
            VoiceLocaleOption(
                identifier: locale.identifier,
                title: Locale.current.localizedString(forIdentifier: locale.identifier)
                    ?? locale.identifier
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

    /// Scribe v2 accepts ISO-639-1 or ISO-639-3 codes. Keeping this provider-specific
    /// prevents Apple locale identifiers such as `en_US` from reaching ElevenLabs.
    static let elevenLabs: [VoiceLocaleOption] = [
        "afr", "amh", "ara", "hye", "asm", "ast", "aze", "bel", "ben", "bos",
        "bul", "mya", "yue", "cat", "ceb", "nya", "hrv", "ces", "dan", "nld",
        "eng", "est", "fil", "fin", "fra", "ful", "glg", "lug", "kat", "deu",
        "ell", "guj", "hau", "heb", "hin", "hun", "isl", "ibo", "ind", "gle",
        "ita", "jpn", "jav", "kea", "kan", "kaz", "khm", "kor", "kur", "kir",
        "lao", "lav", "lin", "lit", "luo", "ltz", "mkd", "msa", "mal", "mlt",
        "zho", "mri", "mar", "mon", "nep", "nso", "nor", "oci", "ori", "pus",
        "fas", "pol", "por", "pan", "ron", "rus", "srp", "sna", "snd", "slk",
        "slv", "som", "spa", "swa", "swe", "tam", "tgk", "tel", "tha", "tur",
        "ukr", "umb", "urd", "uzb", "vie", "cym", "wol", "xho", "yor", "zul"
    ]
    .map { code in
        VoiceLocaleOption(
            identifier: code,
            title: Locale.current.localizedString(forLanguageCode: code) ?? code
        )
    }
    .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
}
#endif
