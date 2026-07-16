import NMP
import XCTest
@testable import TwentyNinerNext

final class ChatHistoryPagingTests: XCTestCase {
    func testPagingAdvancesInBoundedSteps() {
        var paging = ChatHistoryPaging(initialRows: 200, pageSize: 200, maxRows: 500)

        XCTAssertEqual(paging.proposedTarget, 400)
        paging.acceptedRequest(target: 400)
        XCTAssertEqual(paging.state, .loading)
        XCTAssertNil(paging.proposedTarget)

        paging.receive(.returned(added: 200))
        XCTAssertEqual(paging.state, .ready)
        XCTAssertEqual(paging.proposedTarget, 500)

        paging.acceptedRequest(target: 500)
        paging.receive(.returned(added: 20))
        XCTAssertEqual(paging.state, .atBound(max: 500))
        XCTAssertNil(paging.proposedTarget)
    }

    func testZeroRowsDoesNotFabricateEndOfHistory() {
        var paging = ChatHistoryPaging(initialRows: 200, pageSize: 200, maxRows: 1_000)
        paging.acceptedRequest(target: 400)
        paging.receive(.returned(added: 0))

        XCTAssertEqual(paging.state, .noRowsReturned)
        XCTAssertEqual(paging.proposedTarget, 600)
    }

    func testRequestFailureCanRetryTheSameTarget() {
        var paging = ChatHistoryPaging(initialRows: 200, pageSize: 200, maxRows: 1_000)
        XCTAssertEqual(paging.proposedTarget, 400)

        paging.fail("offline")

        XCTAssertEqual(paging.state, .failed("offline"))
        XCTAssertEqual(paging.proposedTarget, 400)
    }
}
