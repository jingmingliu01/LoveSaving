import XCTest
@testable import LoveSaving

@MainActor
final class AppSessionNotificationTests: XCTestCase {
    func testRequestNotificationsCallsMessagingService() async {
        let spy = MessagingSpy()
        let session = makeSession(messaging: spy)

        await session.requestNotifications()

        XCTAssertEqual(spy.requestAuthorizationCallCount, 1)
        XCTAssertEqual(spy.updateReminderCallCount, 1)
        XCTAssertNil(session.globalErrorMessage)
        XCTAssertEqual(session.notificationSettings.authorizationStatus, .authorized)
    }

    func testRequestNotificationsSurfacesError() async {
        let spy = MessagingSpy(shouldThrow: true)
        let session = makeSession(messaging: spy)

        await session.requestNotifications()

        XCTAssertEqual(session.globalErrorMessage, MessagingSpy.ErrorStub.denied.localizedDescription)
    }

    func testSyncNotificationSettingsOnLaunchLoadsCurrentPreferences() async {
        let spy = MessagingSpy()
        spy.stubbedSettings = NotificationSettingsState(
            authorizationStatus: .authorized,
            dailyReminderEnabled: false,
            reminderHour: 21,
            reminderMinute: 30
        )
        let session = makeSession(messaging: spy)

        await session.syncNotificationSettingsOnLaunch()

        XCTAssertEqual(spy.syncCallCount, 1)
        XCTAssertEqual(session.notificationSettings.dailyReminderEnabled, false)
        XCTAssertEqual(session.notificationSettings.reminderHour, 21)
        XCTAssertEqual(session.notificationSettings.reminderMinute, 30)
    }

    func testSetDailyReminderEnabledPersistsViaMessagingService() async {
        let spy = MessagingSpy()
        let session = makeSession(messaging: spy)

        await session.refreshNotificationSettings()
        await session.setDailyReminderEnabled(false)

        XCTAssertEqual(spy.updateReminderCallCount, 1)
        XCTAssertEqual(spy.lastUpdatedEnabled, false)
        XCTAssertEqual(session.notificationSettings.dailyReminderEnabled, false)
    }

    func testSetDailyReminderTimePersistsViaMessagingService() async {
        let spy = MessagingSpy()
        let session = makeSession(messaging: spy)
        let calendar = Calendar.current
        let date = calendar.date(from: DateComponents(hour: 9, minute: 45)) ?? Date()

        await session.refreshNotificationSettings()
        await session.setDailyReminderTime(date)

        XCTAssertEqual(spy.updateReminderCallCount, 1)
        XCTAssertEqual(spy.lastUpdatedHour, 9)
        XCTAssertEqual(spy.lastUpdatedMinute, 45)
        XCTAssertEqual(session.notificationSettings.reminderHour, 9)
        XCTAssertEqual(session.notificationSettings.reminderMinute, 45)
    }

    func testAuthRefreshUploadsCurrentMessagingTokenWhenAvailable() async {
        let spy = MessagingSpy()
        spy.stubbedCurrentToken = "fcm-token-123"
        let store = UITestStore.makeSeeded(scenario: .linked)
        let auth = UITestAuthService(store: store)
        let container = AppContainer(
            authService: auth,
            userDataService: UITestUserDataService(store: store),
            inviteService: UITestInviteService(store: store),
            groupService: UITestGroupService(store: store),
            eventService: UITestEventService(store: store),
            mediaService: UITestMediaService(),
            messagingService: spy,
            aiInsightsAvailabilityService: UITestAIInsightsAvailabilityService(),
            aiInsightsService: UITestAIInsightsService(),
            crashReporter: CrashlyticsReporterSpy(),
            runtimeMode: .uiTest(.linked)
        )
        let session = AppSession(container: container)

        await waitUntil("auth refresh uploads current FCM token") {
            store.users["owner"]?.fcmToken == "fcm-token-123"
        }

        XCTAssertNotNil(session.profile)
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
            aiInsightsAvailabilityService: UITestAIInsightsAvailabilityService(),
            aiInsightsService: UITestAIInsightsService(),
            crashReporter: CrashlyticsReporterSpy(),
            runtimeMode: .uiTest(.linked)
        )
        return AppSession(container: container)
    }

    private func waitUntil(
        _ description: String,
        timeoutNanoseconds: UInt64 = 3_000_000_000,
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
private final class MessagingSpy: MessagingServicing {
    enum ErrorStub: LocalizedError {
        case denied

        var errorDescription: String? {
            "Notifications denied"
        }
    }

    let shouldThrow: Bool
    var stubbedSettings = NotificationSettingsState(
        authorizationStatus: .notDetermined,
        dailyReminderEnabled: true,
        reminderHour: 20,
        reminderMinute: 0
    )
    var stubbedCurrentToken: String?
    private(set) var requestAuthorizationCallCount = 0
    private(set) var updateReminderCallCount = 0
    private(set) var syncCallCount = 0
    private(set) var lastUpdatedEnabled: Bool?
    private(set) var lastUpdatedHour: Int?
    private(set) var lastUpdatedMinute: Int?

    init(shouldThrow: Bool = false) {
        self.shouldThrow = shouldThrow
    }

    var tokenStream: AsyncStream<String> {
        AsyncStream { _ in }
    }

    func fetchCurrentToken() async -> String? {
        stubbedCurrentToken
    }

    func fetchNotificationSettings() async -> NotificationSettingsState {
        stubbedSettings
    }

    func requestNotificationAuthorization() async throws -> NotificationSettingsState {
        requestAuthorizationCallCount += 1
        if shouldThrow {
            throw ErrorStub.denied
        }
        stubbedSettings.authorizationStatus = .authorized
        return stubbedSettings
    }

    func updateDailyReflectionReminder(
        enabled: Bool,
        hour: Int,
        minute: Int
    ) async throws -> NotificationSettingsState {
        updateReminderCallCount += 1
        lastUpdatedEnabled = enabled
        lastUpdatedHour = hour
        lastUpdatedMinute = minute
        stubbedSettings.dailyReminderEnabled = enabled
        stubbedSettings.reminderHour = hour
        stubbedSettings.reminderMinute = minute
        return stubbedSettings
    }

    func syncNotificationSettings() async throws -> NotificationSettingsState {
        syncCallCount += 1
        return stubbedSettings
    }
}
