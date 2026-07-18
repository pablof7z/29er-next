import XCTest
@testable import TwentyNinerNext

@MainActor
final class VoiceDraftPlayerTests: XCTestCase {
    // 31. Playback completion resets the preview control to "play".
    func testPlaybackCompletionResetsControl() {
        let player = VoiceDraftPlayer()
        player.markFinished()
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.progress, 0)
    }

    // Stopping releases playback state cleanly (draft deleted / composer disappears).
    func testStopResetsState() {
        let player = VoiceDraftPlayer()
        player.stop()
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.progress, 0)
    }
}
