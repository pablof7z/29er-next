import XCTest
@testable import TwentyNinerNext

final class WorkspaceTintTests: XCTestCase {
    func testPaletteMatchesTenexEdgeHashSlots() {
        XCTAssertEqual(WorkspaceTint.paletteIndex(for: "29er-next"), 1)
        XCTAssertEqual(WorkspaceTint.paletteIndex(for: "tenex-edge"), 5)
        XCTAssertEqual(WorkspaceTint.paletteIndex(for: "nmp"), 2)
    }

    func testPaletteIsStableForRepeatedSeed() {
        XCTAssertEqual(
            WorkspaceTint.paletteIndex(for: "workspace"),
            WorkspaceTint.paletteIndex(for: "workspace")
        )
    }
}
