import XCTest
@testable import LoveSaving

final class TapBurstStateTests: XCTestCase {
    func testRegisterTapAndReset() {
        var state = TapBurstState()
        let t1 = Date(timeIntervalSince1970: 100)
        let t2 = Date(timeIntervalSince1970: 200)

        state.registerTap(at: t1)
        XCTAssertEqual(state.count, 1)
        XCTAssertEqual(state.lastTapAt, t1)

        state.registerTap(at: t2)
        XCTAssertEqual(state.count, 2)
        XCTAssertEqual(state.lastTapAt, t2)

        state.reset()
        XCTAssertEqual(state.count, 0)
        XCTAssertNil(state.lastTapAt)
    }
}
