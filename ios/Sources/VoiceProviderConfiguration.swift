import Foundation

enum VoiceProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case apple
    case elevenLabs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: "Apple"
        case .elevenLabs: "ElevenLabs"
        }
    }

    var systemImage: String {
        switch self {
        case .apple: "apple.logo"
        case .elevenLabs: "waveform.badge.mic"
        }
    }
}

enum AppleRecognitionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case onDeviceOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .onDeviceOnly: "On Device Only"
        }
    }
}

struct VoiceProviderConfiguration: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var kind: VoiceProviderKind
    var languageCode: String
    var detectsLanguageAutomatically: Bool
    var appleRecognitionMode: AppleRecognitionMode
    var elevenLabsModel: String
    var elevenLabsNoVerbatim: Bool
    var elevenLabsTagsAudioEvents: Bool
    var elevenLabsKeyterms: String

    static let builtInAppleID = UUID(uuidString: "29E00000-0000-4000-8000-000000000001")!

    static let builtInApple = VoiceProviderConfiguration(
        id: builtInAppleID,
        name: "Apple (Built-In)",
        kind: .apple,
        languageCode: Locale.current.identifier,
        detectsLanguageAutomatically: false,
        appleRecognitionMode: .automatic,
        elevenLabsModel: "scribe_v2",
        elevenLabsNoVerbatim: true,
        elevenLabsTagsAudioEvents: false,
        elevenLabsKeyterms: ""
    )

    static func new(_ kind: VoiceProviderKind) -> VoiceProviderConfiguration {
        VoiceProviderConfiguration(
            id: UUID(),
            name: kind == .apple ? "Apple" : "ElevenLabs",
            kind: kind,
            languageCode: kind == .apple ? Locale.current.identifier : "",
            detectsLanguageAutomatically: kind == .elevenLabs,
            appleRecognitionMode: .automatic,
            elevenLabsModel: "scribe_v2",
            elevenLabsNoVerbatim: true,
            elevenLabsTagsAudioEvents: false,
            elevenLabsKeyterms: ""
        )
    }

    var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedLanguageCode: String? {
        guard !detectsLanguageAutomatically else { return nil }
        let value = languageCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var keyterms: [String] {
        elevenLabsKeyterms
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct VoiceProviderSnapshot: Equatable, Sendable {
    let configuration: VoiceProviderConfiguration
    let credential: String?
}

enum VoiceProviderConfigurationError: LocalizedError, Equatable {
    case activeConfigurationCannotBeDeleted
    case missingName
    case missingCredential
    case missingConfiguration

    var errorDescription: String? {
        switch self {
        case .activeConfigurationCannotBeDeleted:
            "Choose another active provider before deleting this configuration."
        case .missingName:
            "Give this configuration a name."
        case .missingCredential:
            "Add an ElevenLabs API key before making this configuration active."
        case .missingConfiguration:
            "Choose a transcription provider in System Settings."
        }
    }
}
