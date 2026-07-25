import XCTest
@testable import TwentyNinerNext

final class VoiceTranscriptTextTests: XCTestCase {
    func testAppendsToExistingComposerTextWithOneSeparator() {
        XCTAssertEqual(
            VoiceTranscriptText.appending(" dictated thought ", to: "Typed first."),
            "Typed first. dictated thought"
        )
        XCTAssertEqual(
            VoiceTranscriptText.appending("dictated thought", to: "Typed first. "),
            "Typed first. dictated thought"
        )
    }

    func testMergeIsIdempotentWhenCompletionArrivesTwice() {
        let merged = VoiceTranscriptText.merging(
            "dictated thought",
            originalText: "Typed first.",
            currentText: "Typed first."
        )
        XCTAssertEqual(merged, "Typed first. dictated thought")
        XCTAssertEqual(
            VoiceTranscriptText.merging(
                "dictated thought",
                originalText: "Typed first.",
                currentText: merged
            ),
            merged
        )
    }

    func testMergePreservesTextTypedWhileTranscriptionRuns() {
        XCTAssertEqual(
            VoiceTranscriptText.merging(
                "dictated thought",
                originalText: "Typed first.",
                currentText: "Typed first. Added meanwhile."
            ),
            "Typed first. Added meanwhile. dictated thought"
        )
    }
}
