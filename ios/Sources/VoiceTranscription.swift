import Foundation

@MainActor
protocol VoiceTranscribing {
    func transcribe(
        audioURL: URL,
        snapshot: VoiceProviderSnapshot
    ) async throws -> String
}

@MainActor
struct VoiceTranscriptionService {
    private let apple: any VoiceTranscribing
    private let elevenLabs: any VoiceTranscribing

    init(
        apple: any VoiceTranscribing = AppleVoiceTranscriber(),
        elevenLabs: any VoiceTranscribing = ElevenLabsVoiceTranscriber()
    ) {
        self.apple = apple
        self.elevenLabs = elevenLabs
    }

    func transcribe(
        audioURL: URL,
        snapshot: VoiceProviderSnapshot
    ) async throws -> String {
        let result: String
        switch snapshot.configuration.kind {
        case .apple:
            result = try await apple.transcribe(audioURL: audioURL, snapshot: snapshot)
        case .elevenLabs:
            result = try await elevenLabs.transcribe(audioURL: audioURL, snapshot: snapshot)
        }
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw VoiceTranscriptionError.noSpeech }
        return trimmed
    }
}

enum VoiceTranscriptionError: LocalizedError, Equatable {
    case providerUnavailable
    case permissionDenied
    case onDeviceUnavailable
    case missingCredential
    case noSpeech
    case offline
    case elevenLabsAccount
    case rateLimited
    case service(String)

    var errorDescription: String? {
        switch self {
        case .providerUnavailable:
            "Provider Unavailable — Your recording is saved. Choose a transcription provider, then try again."
        case .permissionDenied:
            "Speech Recognition Is Off — Your recording is saved. Allow access in Settings to use Apple Transcription."
        case .onDeviceUnavailable:
            "On-device transcription is unavailable for this language. Your recording is saved."
        case .missingCredential:
            "ElevenLabs needs an API key. Your recording is saved. Update Voice Settings, then try again."
        case .noSpeech:
            "No Speech Detected — Your recording is saved. You can retry or send the audio without text."
        case .offline:
            "Couldn’t Transcribe — No connection. Your recording is saved in this chat. Try again when you’re online."
        case .elevenLabsAccount:
            "ElevenLabs Couldn’t Transcribe — Your recording is saved in this chat. Check your API key or plan, then try again."
        case .rateLimited:
            "ElevenLabs is temporarily rate limited. Your recording is saved in this chat."
        case .service(let detail):
            "Couldn’t Transcribe — Your recording is saved in this chat. \(detail)"
        }
    }
}

enum VoiceTranscriptText {
    static func appending(_ transcript: String, to existing: String) -> String {
        let addition = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !addition.isEmpty else { return existing }
        guard !existing.isEmpty else { return addition }
        if existing.last?.isWhitespace == true { return existing + addition }
        return existing + " " + addition
    }

    static func merging(
        _ transcript: String,
        originalText: String,
        currentText: String
    ) -> String {
        let expected = appending(transcript, to: originalText)
        if currentText.isEmpty || currentText == originalText { return expected }
        if currentText == expected { return currentText }
        return appending(transcript, to: currentText)
    }
}
