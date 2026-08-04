import XCTest
@testable import TwentyNinerNext

@MainActor
final class RoomOpenProbeTests: XCTestCase {
    func testReportCoversEverySynchronousRoomObservation() {
        XCTAssertEqual(
            RoomOpenProbe.Query.allCases.map(\.observeField),
            [
                "contentObserveMs",
                "activityObserveMs",
                "groupRecordsObserveMs",
                "profilesObserveMs"
            ]
        )
        XCTAssertEqual(RoomOpenProbe.Query.activity.snapshotFieldPrefix, "activityQuery")
    }
}
