import XCTest

final class RootFlowSmokeUITests: XCTestCase {
    private enum Timeout {
        static let root: TimeInterval = 12
        static let content: TimeInterval = 12
    }

    func testSignedOutScenarioShowsAuthRoot() {
        let app = launchApp(scenario: "signed_out")
        assertElementExists("root.auth", in: app, timeout: Timeout.root)
    }

    func testUnlinkedScenarioShowsLinkingRoot() {
        let app = launchApp(scenario: "unlinked")
        assertElementExists("root.linking", in: app, timeout: Timeout.root)
    }

    func testLinkedScenarioShowsMainRoot() {
        let app = launchApp(scenario: "linked")
        assertElementExists("root.main", in: app, timeout: Timeout.root)
        assertElementExists("home.balance", in: app, timeout: Timeout.content)
    }

    private func launchApp(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.terminate()
        app.launchEnvironment["LOVESAVING_MODE"] = "UI_TEST"
        app.launchEnvironment["LOVESAVING_SCENARIO"] = scenario
        app.launchEnvironment["LOVESAVING_SKIP_ONBOARDING"] = "1"
        app.launch()
        return app
    }

    private func assertElementExists(_ identifier: String, in app: XCUIApplication, timeout: TimeInterval) {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            "Element '\(identifier)' not found. UI hierarchy:\n\(app.debugDescription)"
        )
    }
}
