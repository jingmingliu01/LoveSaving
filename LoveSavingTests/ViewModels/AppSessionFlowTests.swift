import CoreLocation
import XCTest
@testable import LoveSaving

@MainActor
final class AppSessionFlowTests: XCTestCase {
    func testSignUpCreatesProfileAndSignsIn() async {
        let session = makeSession(scenario: .signedOut).session

        await session.signUp(email: "new@example.com", password: "secret123", displayName: "New User")

        XCTAssertTrue(session.isSignedIn)
        XCTAssertEqual(session.profile?.email, "new@example.com")
        XCTAssertEqual(session.profile?.displayName, "New User")
        XCTAssertNil(session.globalErrorMessage)
    }

    func testSignInAndSendInviteSuccess() async {
        let session = makeSession(scenario: .linked).session

        session.signOut()
        await session.signIn(email: "owner@example.com", password: "pw")
        await session.sendInvite(to: "partner@example.com")

        XCTAssertNil(session.globalErrorMessage)
    }

    func testSendInviteToUnknownUserSetsError() async {
        let session = makeSession(scenario: .linked).session

        await session.sendInvite(to: "missing@example.com")

        XCTAssertEqual(session.globalErrorMessage, AppError.userNotFound.localizedDescription)
    }

    func testAcceptInviteLinksGroup() async {
        let session = makeSession(scenario: .unlinked).session
        await waitUntil("auth observer loads inbound invite") {
            session.isSignedIn && !session.inboundInvites.isEmpty
        }

        guard let invite = session.inboundInvites.first else {
            XCTFail("Expected seeded invite")
            return
        }

        await session.respond(invite: invite, accept: true)

        XCTAssertTrue(session.isLinked)
        XCTAssertNotNil(session.group)
        XCTAssertNil(session.globalErrorMessage)
    }

    func testSubmitTapBurstWithImageAddsEventMedia() async {
        let session = makeSession(scenario: .linked).session
        await waitUntil("auth observer loads linked group") {
            session.isSignedIn && session.group != nil
        }

        let result = await session.submitTapBurst(
            tapCount: 3,
            type: .deposit,
            note: "Nice job",
            imageData: Data("image".utf8),
            coordinate: CLLocationCoordinate2D(latitude: 37.7, longitude: -122.4),
            addressText: "San Francisco"
        )

        XCTAssertTrue(result)
        XCTAssertEqual(session.events.count, 2)
        XCTAssertEqual(session.events.first?.media.count, 1)
        XCTAssertNil(session.globalErrorMessage)
    }

    func testSubmitTapBurstWithoutCoordinateFails() async {
        let session = makeSession(scenario: .linked).session
        await waitUntil("auth observer loads linked group") {
            session.isSignedIn && session.group != nil
        }

        let result = await session.submitTapBurst(
            tapCount: 2,
            type: .deposit,
            note: nil,
            imageData: nil,
            coordinate: nil,
            addressText: nil
        )

        XCTAssertFalse(result)
        XCTAssertEqual(session.globalErrorMessage, AppError.locationUnavailable.localizedDescription)
    }

    func testSignOutClearsCrashlyticsUserID() async {
        let harness = makeSession(scenario: .linked)
        let session = harness.session
        let crashReporter = harness.crashReporter
        await waitUntil("auth observer loads linked user") {
            session.isSignedIn && session.group != nil
        }

        session.signOut()

        XCTAssertEqual(crashReporter.userIDs.last, "")
        XCTAssertEqual(crashReporter.customValues["is_signed_in"] as? Bool, false)
        XCTAssertEqual(crashReporter.customValues["group_id_present"] as? Bool, false)
    }

    func testMarkOnboardingCompletedUpdatesCrashlyticsContext() async {
        let harness = makeSession(scenario: .linked)
        let session = harness.session
        let crashReporter = harness.crashReporter
        await waitUntil("auth observer loads profile") {
            session.isSignedIn && session.profile != nil
        }

        let result = await session.markOnboardingCompleted()

        XCTAssertTrue(result)
        XCTAssertEqual(crashReporter.customValues["has_completed_onboarding"] as? Bool, true)
        XCTAssertEqual(crashReporter.customValues["last_operation"] as? String, "profile.markOnboardingCompleted")
    }

    func testUnexpectedInviteRefreshRecordsNonFatalWithContext() async {
        let store = UITestStore.makeSeeded(scenario: .signedOut)
        let auth = UITestAuthService(store: store)
        let crashReporter = CrashlyticsReporterSpy()
        let container = AppContainer(
            authService: auth,
            userDataService: UITestUserDataService(store: store),
            inviteService: InviteFetchFailingService(),
            groupService: UITestGroupService(store: store),
            eventService: UITestEventService(store: store),
            mediaService: UITestMediaService(),
            messagingService: UITestMessagingService(),
            crashReporter: crashReporter,
            runtimeMode: .uiTest(.signedOut)
        )
        let session = AppSession(container: container)

        await session.signUp(
            email: "invite-failure@example.com",
            password: "secret123",
            displayName: "Invite Failure"
        )

        XCTAssertEqual(
            crashReporter.customValues["runtime_mode"] as? String,
            AppRuntimeMode.uiTest(.signedOut).crashlyticsValue
        )
        XCTAssertEqual(crashReporter.customValues["group_id_present"] as? Bool, false)
        XCTAssertEqual(crashReporter.recordedErrorTypes, [String(reflecting: InviteFetchFailingService.Failure.self)])
        XCTAssertTrue(crashReporter.logs.contains { $0.contains("auth.refresh.inboundInvites") })
        XCTAssertEqual(crashReporter.customValues["last_operation"] as? String, "auth.refresh.inboundInvites")
        XCTAssertEqual(crashReporter.customValues["operation_event_type"] as? String, "none")
        XCTAssertEqual(crashReporter.customValues["operation_tap_count"] as? Int, -1)
    }

    func testSubmitTapBurstAppErrorSetsOperationContextWithoutRecordingNonFatal() async {
        let harness = makeSession(scenario: .linked)
        let session = harness.session
        let crashReporter = harness.crashReporter
        await waitUntil("auth observer loads linked group") {
            session.isSignedIn && session.group != nil
        }

        _ = await session.submitTapBurst(
            tapCount: 2,
            type: .deposit,
            note: nil,
            imageData: nil,
            coordinate: nil,
            addressText: nil
        )

        XCTAssertEqual(crashReporter.customValues["last_operation"] as? String, "event.submitTapBurst")
        XCTAssertEqual(crashReporter.customValues["operation_event_type"] as? String, "deposit")
        XCTAssertEqual(crashReporter.customValues["operation_tap_count"] as? Int, 2)
        XCTAssertEqual(crashReporter.customValues["operation_has_image"] as? Bool, false)
        XCTAssertTrue(crashReporter.recordedErrorTypes.isEmpty)
    }

    func testSignUpSucceedsWhenInboundInviteRefreshFails() async {
        let store = UITestStore.makeSeeded(scenario: .signedOut)
        let auth = UITestAuthService(store: store)
        let container = AppContainer(
            authService: auth,
            userDataService: UITestUserDataService(store: store),
            inviteService: InviteFetchFailingService(),
            groupService: UITestGroupService(store: store),
            eventService: UITestEventService(store: store),
            mediaService: UITestMediaService(),
            messagingService: UITestMessagingService(),
            crashReporter: CrashlyticsReporterSpy(),
            runtimeMode: .uiTest(.signedOut)
        )
        let session = AppSession(container: container)

        await session.signUp(
            email: "invite-failure@example.com",
            password: "secret123",
            displayName: "Invite Failure"
        )

        XCTAssertTrue(session.isSignedIn)
        XCTAssertEqual(session.profile?.email, "invite-failure@example.com")
        XCTAssertEqual(session.inboundInvites, [])
        XCTAssertNil(session.globalErrorMessage)
    }

    private func makeSession(
        scenario: UITestScenario,
        crashReporter: CrashlyticsReporterSpy? = nil
    ) -> (session: AppSession, crashReporter: CrashlyticsReporterSpy) {
        let crashReporter = crashReporter ?? CrashlyticsReporterSpy()
        let store = UITestStore.makeSeeded(scenario: scenario)
        let auth = UITestAuthService(store: store)
        let container = AppContainer(
            authService: auth,
            userDataService: UITestUserDataService(store: store),
            inviteService: UITestInviteService(store: store),
            groupService: UITestGroupService(store: store),
            eventService: UITestEventService(store: store),
            mediaService: UITestMediaService(),
            messagingService: UITestMessagingService(),
            crashReporter: crashReporter,
            runtimeMode: .uiTest(scenario)
        )
        return (AppSession(container: container), crashReporter)
    }

    private func waitUntil(
        _ description: String,
        timeoutNanoseconds: UInt64 = 5_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now + .nanoseconds(Int64(timeoutNanoseconds))
        while clock.now < deadline {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTFail("Timed out waiting for condition: \(description)")
    }
}

@MainActor
private struct InviteFetchFailingService: InviteServicing {
    struct Failure: LocalizedError {
        var errorDescription: String? {
            "Missing or insufficient permissions."
        }
    }

    func sendInvite(
        fromUid: String,
        toUid: String,
        expiresAt: Date?,
        fromDisplayName: String?,
        fromEmail: String?
    ) async throws -> Invite {
        fatalError("sendInvite should not be called in this test")
    }

    func fetchInboundInvites(for uid: String) async throws -> [Invite] {
        throw Failure()
    }

    func respondInvite(inviteId: String, status: InviteStatus, respondedAt: Date) async throws {
        fatalError("respondInvite should not be called in this test")
    }
}
