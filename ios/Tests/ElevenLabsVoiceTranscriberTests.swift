import XCTest
@testable import TwentyNinerNext

@MainActor
final class ElevenLabsVoiceTranscriberTests: XCTestCase {
    func testMultipartIncludesConfiguredFieldsKeytermsAndAudio() throws {
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: audioURL) }
        try Data("audio-payload".utf8).write(to: audioURL)
        var configuration = VoiceProviderConfiguration.new(.elevenLabs)
        configuration.detectsLanguageAutomatically = false
        configuration.languageCode = "es"
        configuration.elevenLabsModel = "scribe_v2"
        configuration.elevenLabsNoVerbatim = true
        configuration.elevenLabsTagsAudioEvents = true
        configuration.elevenLabsKeyterms = "Nostr, Mosaico\nNIP-29"

        let body = try ElevenLabsVoiceTranscriber.multipartBody(
            audioURL: audioURL,
            configuration: configuration,
            boundary: "test-boundary"
        )
        let text = String(decoding: body, as: UTF8.self)

        XCTAssertTrue(text.contains("name=\"model_id\"\r\n\r\nscribe_v2"))
        XCTAssertTrue(text.contains("name=\"language_code\"\r\n\r\nes"))
        XCTAssertTrue(text.contains("name=\"no_verbatim\"\r\n\r\ntrue"))
        XCTAssertTrue(text.contains("name=\"tag_audio_events\"\r\n\r\ntrue"))
        XCTAssertEqual(text.components(separatedBy: "name=\"keyterms\"").count - 1, 3)
        XCTAssertTrue(text.contains("audio-payload"))
        XCTAssertTrue(text.hasSuffix("--test-boundary--\r\n"))
    }

    func testAutomaticLanguageOmitsLanguageCode() throws {
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: audioURL) }
        try Data([0x01]).write(to: audioURL)
        let configuration = VoiceProviderConfiguration.new(.elevenLabs)

        let body = try ElevenLabsVoiceTranscriber.multipartBody(
            audioURL: audioURL,
            configuration: configuration,
            boundary: "boundary"
        )

        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("language_code"))
    }

    func testScribeV1OmitsV2OnlyOptions() throws {
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: audioURL) }
        try Data([0x01]).write(to: audioURL)
        var configuration = VoiceProviderConfiguration.new(.elevenLabs)
        configuration.elevenLabsModel = "scribe_v1"
        configuration.elevenLabsKeyterms = "Mosaico"

        let body = try ElevenLabsVoiceTranscriber.multipartBody(
            audioURL: audioURL,
            configuration: configuration,
            boundary: "boundary"
        )
        let text = String(decoding: body, as: UTF8.self)

        XCTAssertFalse(text.contains("no_verbatim"))
        XCTAssertFalse(text.contains("keyterms"))
    }

    func testCrashRecoverableCAFUsesItsAudioContentType() throws {
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: audioURL) }
        try Data([0x01]).write(to: audioURL)

        let body = try ElevenLabsVoiceTranscriber.multipartBody(
            audioURL: audioURL,
            configuration: .new(.elevenLabs),
            boundary: "boundary"
        )

        XCTAssertTrue(
            String(decoding: body, as: UTF8.self).contains("Content-Type: audio/x-caf")
        )
    }
}
