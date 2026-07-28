import Foundation
import Speech

@MainActor
final class AppleVoiceTranscriber: VoiceTranscribing {
    func transcribe(
        audioURL: URL,
        snapshot: VoiceProviderSnapshot
    ) async throws -> String {
        let configuration = snapshot.configuration
        guard configuration.kind == .apple else {
            throw VoiceTranscriptionError.providerUnavailable
        }
        guard await authorizationStatus() == .authorized else {
            throw VoiceTranscriptionError.permissionDenied
        }

        let locale = Locale(
            identifier: configuration.normalizedLanguageCode ?? Locale.current.identifier
        )
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw VoiceTranscriptionError.providerUnavailable
        }
        recognizer.defaultTaskHint = .dictation

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        if configuration.appleRecognitionMode == .onDeviceOnly {
            guard recognizer.supportsOnDeviceRecognition else {
                throw VoiceTranscriptionError.onDeviceUnavailable
            }
            request.requiresOnDeviceRecognition = true
        }

        return try await recognize(request, with: recognizer)
    }

    private func authorizationStatus() async -> SFSpeechRecognizerAuthorizationStatus {
        let existing = SFSpeechRecognizer.authorizationStatus()
        guard existing == .notDetermined else { return existing }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func recognize(
        _ request: SFSpeechRecognitionRequest,
        with recognizer: SFSpeechRecognizer
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let completion = AppleRecognitionCompletion(continuation)
            recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    completion.succeed(result.bestTranscription.formattedString)
                } else if let error {
                    completion.fail(Self.map(error))
                }
            }
        }
    }

    private static func map(_ error: Error) -> VoiceTranscriptionError {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return .offline
        }
        return .service("Apple Speech could not finish the transcription.")
    }
}

private final class AppleRecognitionCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?

    init(_ continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
    }

    func succeed(_ text: String) {
        finish(.success(text))
    }

    func fail(_ error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<String, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
