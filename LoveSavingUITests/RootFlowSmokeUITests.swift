import XCTest

final class RootFlowSmokeUITests: XCTestCase {
    func testSignedOutScenarioShowsAuthRoot() {
        let app = launchApp(scenario: "signed_out")
        XCTAssertTrue(app.otherElements["root.auth"].waitForExistence(timeout: 5))
    }

    func testUnlinkedScenarioShowsLinkingRoot() {
        let app = launchApp(scenario: "unlinked")
        XCTAssertTrue(app.otherElements["root.linking"].waitForExistence(timeout: 5))
    }

    func testLinkedScenarioShowsMainRoot() {
        let app = launchApp(scenario: "linked")
        XCTAssertTrue(app.otherElements["root.main"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["home.balance"].waitForExistence(timeout: 5))
    }

    private func launchApp(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        if app.state != .notRunning {
            app.terminate()
        }
        app.launchEnvironment["LOVEBANK_MODE"] = "UI_TEST"
        app.launchEnvironment["LOVEBANK_SCENARIO"] = scenario
        app.launch()
        return app
    }
}
