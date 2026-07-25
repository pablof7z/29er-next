import XCTest
@testable import TwentyNinerNext

final class WorkspaceTintTests: XCTestCase {
    func testPaletteMatchesMosaicoHashSlots() {
        XCTAssertEqual(WorkspaceTint.paletteIndex(for: "29er-next"), 1)
        XCTAssertEqual(WorkspaceTint.paletteIndex(for: "mosaico"), 0)
        XCTAssertEqual(WorkspaceTint.paletteIndex(for: "nmp"), 2)
    }

    func testPaletteIsStableForRepeatedSeed() {
        XCTAssertEqual(
            WorkspaceTint.paletteIndex(for: "workspace"),
            WorkspaceTint.paletteIndex(for: "workspace")
        )
    }
}
