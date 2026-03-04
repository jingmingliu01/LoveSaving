import XCTest
@testable import LoveSaving

@MainActor
final class AppSessionNotificationTests: XCTestCase {
    func testRequestNotificationsCallsMessagingService() async {
        let spy = MessagingSpy()
        let session = makeSession(messaging: spy)

        await session.requestNotifications()

        XCTAssertEqual(spy.requestAuthorizationCallCount, 1)
        XCTAssertEqual(spy.scheduleReminderCallCount, 1)
        XCTAssertNil(session.globalErrorMessage)
    }

    func testRequestNotificationsSurfacesError() async {
        let spy = MessagingSpy(shouldThrow: true)
        let session = makeSession(messaging: spy)

        await session.requestNotifications()

        XCTAssertEqual(session.globalErrorMessage, MessagingSpy.ErrorStub.denied.localizedDescription)
    }

    private func makeSession(messaging: MessagingSpy) -> AppSession {
        let store = UITestStore.makeSeeded(scenario: .linked)
        let auth = UITestAuthService(store: store)
        let container = AppContainer(
            authService: auth,
            userDataService: UITestUserDataService(store: store),
            inviteService: UITestInviteService(store: store),
            groupService: UITestGroupService(store: store),
            eventService: UITestEventService(store: store),
            mediaService: UITestMediaService(),
            messagingService: messaging,
            runtimeMode: .uiTest(.linked)
        )
        return AppSession(container: container)
    }
}

@MainActor
private final class MessagingSpy: MessagingServicing {
    enum ErrorStub: LocalizedError {
        case denied

        var errorDescription: String? {
            "Notifications denied"
        }
    }

    let shouldThrow: Bool
    private(set) var requestAuthorizationCallCount = 0
    private(set) var scheduleReminderCallCount = 0

    init(shouldThrow: Bool = false) {
        self.shouldThrow = shouldThrow
    }

    var tokenStream: AsyncStream<String> {
        AsyncStream { _ in }
    }

    func requestNotificationAuthorization() async throws {
        requestAuthorizationCallCount += 1
        if shouldThrow {
            throw ErrorStub.denied
        }
    }

    func scheduleDailyReflectionReminder() async throws {
        scheduleReminderCallCount += 1
    }
}
