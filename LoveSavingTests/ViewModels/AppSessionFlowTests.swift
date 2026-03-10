import CoreLocation
import XCTest
@testable import LoveSaving

@MainActor
final class AppSessionFlowTests: XCTestCase {
    func testSignUpCreatesProfileAndSignsIn() async {
        let session = makeSession(scenario: .signedOut)

        await session.signUp(email: "new@example.com", password: "secret123", displayName: "New User")

        XCTAssertTrue(session.isSignedIn)
        XCTAssertEqual(session.profile?.email, "new@example.com")
        XCTAssertEqual(session.profile?.displayName, "New User")
        XCTAssertNil(session.globalErrorMessage)
    }

    func testSignInAndSendInviteSuccess() async {
        let session = makeSession(scenario: .linked)

        session.signOut()
        await session.signIn(email: "owner@example.com", password: "pw")
        await session.sendInvite(to: "partner@example.com")

        XCTAssertNil(session.globalErrorMessage)
    }

    func testSendInviteToUnknownUserSetsError() async {
        let session = makeSession(scenario: .linked)

        await session.sendInvite(to: "missing@example.com")

        XCTAssertEqual(session.globalErrorMessage, AppError.userNotFound.localizedDescription)
    }

    func testAcceptInviteLinksGroup() async {
        let session = makeSession(scenario: .unlinked)
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
        let session = makeSession(scenario: .linked)
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
        let session = makeSession(scenario: .linked)
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

    private func makeSession(scenario: UITestScenario) -> AppSession {
        AppSession(container: .uiTest(scenario: scenario))
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
