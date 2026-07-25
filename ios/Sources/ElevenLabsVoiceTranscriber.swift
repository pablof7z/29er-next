import Foundation

@MainActor
final class ElevenLabsVoiceTranscriber: VoiceTranscribing {
    private let session: URLSession
    private let endpoint: URL

    init(
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!
    ) {
        self.session = session
        self.endpoint = endpoint
    }

    func transcribe(
        audioURL: URL,
        snapshot: VoiceProviderSnapshot
    ) async throws -> String {
        let configuration = snapshot.configuration
        guard configuration.kind == .elevenLabs else {
            throw VoiceTranscriptionError.providerUnavailable
        }
        guard let credential = snapshot.credential, !credential.isEmpty else {
            throw VoiceTranscriptionError.missingCredential
        }

        let boundary = "VoiceBoundary-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(credential, forHTTPHeaderField: "xi-api-key")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = try Self.multipartBody(
            audioURL: audioURL,
            configuration: configuration,
            boundary: boundary
        )

        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw VoiceTranscriptionError.service("The provider returned an invalid response.")
            }
            guard (200..<300).contains(response.statusCode) else {
                throw Self.error(for: response.statusCode)
            }
            let payload = try JSONDecoder().decode(ElevenLabsTranscript.self, from: data)
            return payload.text
        } catch let error as VoiceTranscriptionError {
            throw error
        } catch let error as URLError
            where [.notConnectedToInternet, .networkConnectionLost, .timedOut]
                .contains(error.code) {
            throw VoiceTranscriptionError.offline
        } catch {
            throw VoiceTranscriptionError.service("ElevenLabs could not finish the transcription.")
        }
    }

    static func multipartBody(
        audioURL: URL,
        configuration: VoiceProviderConfiguration,
        boundary: String
    ) throws -> Data {
        var body = Data()
        appendField("model_id", configuration.elevenLabsModel, boundary: boundary, to: &body)
        if let language = configuration.normalizedLanguageCode {
            appendField("language_code", language, boundary: boundary, to: &body)
        }
        appendField(
            "tag_audio_events",
            String(configuration.elevenLabsTagsAudioEvents),
            boundary: boundary,
            to: &body
        )
        if configuration.elevenLabsModel == "scribe_v2" {
            appendField(
                "no_verbatim",
                String(configuration.elevenLabsNoVerbatim),
                boundary: boundary,
                to: &body
            )
            for keyterm in configuration.keyterms.prefix(1000) {
                appendField("keyterms", keyterm, boundary: boundary, to: &body)
            }
        }
        let audio = try Data(contentsOf: audioURL)
        body.append("--\(boundary)\r\n")
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(audioURL.lastPathComponent)\"\r\n"
        )
        let contentType = audioURL.pathExtension.lowercased() == "caf"
            ? "audio/x-caf"
            : "audio/mp4"
        body.append("Content-Type: \(contentType)\r\n\r\n")
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n")
        return body
    }

    private static func appendField(
        _ name: String,
        _ value: String,
        boundary: String,
        to body: inout Data
    ) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.append("\(value)\r\n")
    }

    private static func error(for status: Int) -> VoiceTranscriptionError {
        switch status {
        case 401, 402, 403: .elevenLabsAccount
        case 429: .rateLimited
        case 500...599: .service("ElevenLabs is temporarily unavailable.")
        default: .service("ElevenLabs rejected the transcription request.")
        }
    }
}

private struct ElevenLabsTranscript: Decodable {
    let text: String
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
