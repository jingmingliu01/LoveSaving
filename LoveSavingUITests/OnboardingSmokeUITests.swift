import XCTest

final class OnboardingSmokeUITests: XCTestCase {
    private enum Timeout {
        static let intro: TimeInterval = 8
        static let overlay: TimeInterval = 6
        static let composer: TimeInterval = 6
        static let root: TimeInterval = 8
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testLinkedUserCanCompleteOnboardingAndReachMainRoot() {
        let app = launchApp(scenario: "linked")

        completePart1(in: app)
        completePart2(in: app)

        assertElementExists("root.main", in: app, timeout: Timeout.root)
        assertElementExists("home.balance", in: app, timeout: Timeout.root)
    }

    func testSignedOutUserCanCompleteOnboardingAndReachAuthRoot() {
        let app = launchApp(scenario: "signed_out")

        completePart1(in: app)
        completePart2(in: app)

        assertElementExists("root.auth", in: app, timeout: Timeout.root)
    }

    func testSignedOutUserCanSignUpAfterOnboardingWithoutReplay() {
        let app = launchApp(scenario: "signed_out")

        completePart1(in: app)
        completePart2(in: app)

        assertElementExists("root.auth", in: app, timeout: Timeout.root)

        let signUpSegment = app.segmentedControls.buttons["Sign Up"]
        XCTAssertTrue(signUpSegment.waitForExistence(timeout: Timeout.root))
        signUpSegment.tap()

        let email = "onboarding-smoke-\(UUID().uuidString.prefix(8))@example.com"
        let password = "secret12"
        let displayName = "Smoke User"

        let emailField = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "Email")).firstMatch
        XCTAssertTrue(emailField.waitForExistence(timeout: Timeout.root))
        emailField.tap()
        emailField.typeText(email)

        let passwordField = app.secureTextFields.matching(NSPredicate(format: "placeholderValue == %@", "Password")).firstMatch
        XCTAssertTrue(passwordField.waitForExistence(timeout: Timeout.root))
        passwordField.tap()
        passwordField.typeText(password)

        let displayNameField = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "Display Name")).firstMatch
        XCTAssertTrue(displayNameField.waitForExistence(timeout: Timeout.root))
        displayNameField.tap()
        displayNameField.typeText(displayName)

        let submitButton = app.buttons["auth.submit"]
        XCTAssertTrue(submitButton.waitForExistence(timeout: Timeout.root))
        submitButton.tap()

        XCTAssertFalse(
            app.alerts["Error"].waitForExistence(timeout: 3),
            "Did not expect a blocking auth/linking alert after onboarding sign-up. UI hierarchy:\n\(app.debugDescription)"
        )

        assertElementExists("root.linking", in: app, timeout: Timeout.root)
        assertElementExists("linking.incoming.empty", in: app, timeout: Timeout.root)

        XCTAssertFalse(
            app.buttons["onboarding.next"].waitForExistence(timeout: 3),
            "Onboarding unexpectedly replayed after sign-up. UI hierarchy:\n\(app.debugDescription)"
        )
    }

    func testInviteRootShowsSignOutAndReturnsToAuth() {
        let app = launchApp(scenario: "signed_out")

        completePart1(in: app)
        completePart2(in: app)

        assertElementExists("root.auth", in: app, timeout: Timeout.root)

        let signUpSegment = app.segmentedControls.buttons["Sign Up"]
        XCTAssertTrue(signUpSegment.waitForExistence(timeout: Timeout.root))
        signUpSegment.tap()

        let email = "invite-signout-\(UUID().uuidString.prefix(8))@example.com"
        let password = "secret12"
        let displayName = "Invite Signout"

        let emailField = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "Email")).firstMatch
        XCTAssertTrue(emailField.waitForExistence(timeout: Timeout.root))
        emailField.tap()
        emailField.typeText(email)

        let passwordField = app.secureTextFields.matching(NSPredicate(format: "placeholderValue == %@", "Password")).firstMatch
        XCTAssertTrue(passwordField.waitForExistence(timeout: Timeout.root))
        passwordField.tap()
        passwordField.typeText(password)

        let displayNameField = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "Display Name")).firstMatch
        XCTAssertTrue(displayNameField.waitForExistence(timeout: Timeout.root))
        displayNameField.tap()
        displayNameField.typeText(displayName)

        let submitButton = app.buttons["auth.submit"]
        XCTAssertTrue(submitButton.waitForExistence(timeout: Timeout.root))
        submitButton.tap()

        assertElementExists("root.linking", in: app, timeout: Timeout.root)

        let signOutButton = app.buttons["linking.signOut"]
        XCTAssertTrue(
            signOutButton.waitForExistence(timeout: Timeout.root),
            "Expected sign out button on invite root. UI hierarchy:\n\(app.debugDescription)"
        )
        signOutButton.tap()

        assertElementExists("root.auth", in: app, timeout: Timeout.root)
    }

    private func launchApp(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.terminate()
        app.launchEnvironment["LOVESAVING_MODE"] = "UI_TEST"
        app.launchEnvironment["LOVESAVING_SCENARIO"] = scenario
        app.launch()
        return app
    }

    private func completePart1(in app: XCUIApplication) {
        let nextButton = app.buttons["onboarding.next"]
        XCTAssertTrue(
            nextButton.waitForExistence(timeout: Timeout.intro),
            "Expected onboarding next button for firePast. UI hierarchy:\n\(app.debugDescription)"
        )
        nextButton.tap()

        let backButton = app.buttons["onboarding.back"]
        XCTAssertTrue(
            backButton.waitForExistence(timeout: Timeout.intro),
            "Expected onboarding back button for loveNow. UI hierarchy:\n\(app.debugDescription)"
        )
        XCTAssertTrue(nextButton.waitForExistence(timeout: Timeout.intro))
        nextButton.tap()
    }

    private func completePart2(in app: XCUIApplication) {
        assertElementExists("onboarding.part2.copy.focusHeart", in: app, timeout: Timeout.overlay)

        let heartButton = app.buttons["home.tapButton"]
        XCTAssertTrue(
            heartButton.waitForExistence(timeout: Timeout.overlay),
            "Expected tutorial heart button. UI hierarchy:\n\(app.debugDescription)"
        )

        for _ in 0..<4 {
            heartButton.tap()
        }

        assertElementExists("home.composer", in: app, timeout: Timeout.composer)
        assertElementExists("onboarding.part2.copy.submit", in: app, timeout: Timeout.overlay)

        let submitButton = app.buttons["home.submit"]
        XCTAssertTrue(
            submitButton.waitForExistence(timeout: Timeout.overlay),
            "Expected tutorial submit button. UI hierarchy:\n\(app.debugDescription)"
        )
        submitButton.tap()
    }

    private func assertElementExists(_ identifier: String, in app: XCUIApplication, timeout: TimeInterval) {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            "Element '\(identifier)' not found. UI hierarchy:\n\(app.debugDescription)"
        )
    }
}
