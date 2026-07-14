import XCTest
@testable import TwentyNinerNext

final class AudioPlaybackControllerTests: XCTestCase {
    func testAttachmentPresentationUsesDecodedFilenameAndHost() throws {
        let id = AudioAttachmentID(
            messageID: "message",
            ordinal: 0,
            url: try XCTUnwrap(URL(string: "https://media.example/Marina%20voice.mp3"))
        )

        XCTAssertEqual(id.displayTitle, "Marina voice.mp3")
        XCTAssertEqual(id.displaySource, "media.example")
    }

    @MainActor
    func testDismissClearsActivePlayback() throws {
        let controller = AudioPlaybackController()
        let id = AudioAttachmentID(
            messageID: "message",
            ordinal: 0,
            url: try XCTUnwrap(URL(string: "https://media.example/audio.mp3"))
        )

        controller.toggle(id: id, url: id.url)
        XCTAssertEqual(controller.activeID, id)

        controller.dismiss()

        XCTAssertNil(controller.activeID)
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertEqual(controller.currentTime, 0)
        XCTAssertEqual(controller.duration, 0)
    }

    func testTimeLabelUsesMinutesAndSeconds() {
        XCTAssertEqual(AudioPlaybackTime.label(0), "0:00")
        XCTAssertEqual(AudioPlaybackTime.label(65.9), "1:05")
    }

    func testTimeLabelAddsHoursWhenNeeded() {
        XCTAssertEqual(AudioPlaybackTime.label(3_661), "1:01:01")
    }

    func testTimeLabelSanitizesInvalidValues() {
        XCTAssertEqual(AudioPlaybackTime.label(-1), "0:00")
        XCTAssertEqual(AudioPlaybackTime.label(.infinity), "0:00")
        XCTAssertEqual(AudioPlaybackTime.label(.nan), "0:00")
    }
}
