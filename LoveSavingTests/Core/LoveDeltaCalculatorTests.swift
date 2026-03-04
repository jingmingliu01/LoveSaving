import XCTest
@testable import LoveSaving

final class LoveDeltaCalculatorTests: XCTestCase {
    func testUnsignedDeltaBounds() {
        XCTAssertEqual(LoveDeltaCalculator.unsignedDelta(forTapCount: 0), 2)
        XCTAssertEqual(LoveDeltaCalculator.unsignedDelta(forTapCount: 1), 2)
        XCTAssertEqual(LoveDeltaCalculator.unsignedDelta(forTapCount: 10), 10)
        XCTAssertEqual(LoveDeltaCalculator.unsignedDelta(forTapCount: 500), 20)
    }

    func testUnsignedDeltaIsMonotonic() {
        var previous = 0
        for tapCount in 1...100 {
            let value = LoveDeltaCalculator.unsignedDelta(forTapCount: tapCount)
            XCTAssertGreaterThanOrEqual(value, previous)
            XCTAssertTrue((1...20).contains(value))
            previous = value
        }
    }

    func testSignedDeltaFollowsEventType() {
        XCTAssertEqual(LoveDeltaCalculator.signedDelta(forTapCount: 7, type: .deposit), 6)
        XCTAssertEqual(LoveDeltaCalculator.signedDelta(forTapCount: 7, type: .withdraw), -6)
    }
}
