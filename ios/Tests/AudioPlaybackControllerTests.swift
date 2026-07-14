import XCTest
@testable import TwentyNinerNext

final class AudioPlaybackControllerTests: XCTestCase {
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
