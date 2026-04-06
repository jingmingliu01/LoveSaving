import XCTest
@testable import LoveSaving

final class AppContainerTests: XCTestCase {
    func testRuntimeModeStaysLiveWhenBackendConfigured() {
        let mode = AppContainer.runtimeModeForCurrentProcess(
            environment: [:],
            runningUnderTests: false
        )

        XCTAssertEqual(mode, .live)
    }

    func testRuntimeModeUsesUiTestWhenExplicitlyRequested() {
        let mode = AppContainer.runtimeModeForCurrentProcess(
            environment: [
                "LOVESAVING_MODE": "UI_TEST",
                "LOVESAVING_SCENARIO": "linked"
            ],
            runningUnderTests: false
        )

        XCTAssertEqual(mode, .uiTest(.linked))
    }

    func testRuntimeModeRespectsExplicitLiveOverride() {
        let mode = AppContainer.runtimeModeForCurrentProcess(
            environment: ["LOVESAVING_MODE": "LIVE"],
            runningUnderTests: true
        )

        XCTAssertEqual(mode, .live)
    }
}
