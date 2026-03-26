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
        await waitUntil("auth observer loads profile", timeoutNanoseconds: 15_000_000_000) {
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

    func testJourneyRefreshDeduplicatesConcurrentCalls() async {
        let store = UITestStore.makeSeeded(scenario: .linked)
        let auth = UITestAuthService(store: store)
        let eventService = CountingEventService(store: store, fetchDelayNanoseconds: 100_000_000)
        let container = AppContainer(
            authService: auth,
            userDataService: CountingUserDataService(store: store),
            inviteService: UITestInviteService(store: store),
            groupService: CountingGroupService(store: store),
            eventService: eventService,
            mediaService: UITestMediaService(),
            messagingService: UITestMessagingService(),
            runtimeMode: .uiTest(.linked)
        )
        let session = AppSession(container: container)

        await waitUntil("auth observer loads linked events") {
            session.isSignedIn && session.group != nil && !session.events.isEmpty
        }

        let baselineFetchCount = eventService.fetchEventsCallCount

        async let firstRefresh: Void = session.refreshJourney()
        async let secondRefresh: Void = session.refreshJourney()
        _ = await (firstRefresh, secondRefresh)

        XCTAssertEqual(eventService.fetchEventsCallCount - baselineFetchCount, 1)
        XCTAssertNil(session.globalErrorMessage)
    }

    func testPageScopedRefreshesOnlyFetchTheirOwnData() async {
        let store = UITestStore.makeSeeded(scenario: .linked)
        let auth = UITestAuthService(store: store)
        let userDataService = CountingUserDataService(store: store)
        let groupService = CountingGroupService(store: store)
        let eventService = CountingEventService(store: store)
        let container = AppContainer(
            authService: auth,
            userDataService: userDataService,
            inviteService: UITestInviteService(store: store),
            groupService: groupService,
            eventService: eventService,
            mediaService: UITestMediaService(),
            messagingService: UITestMessagingService(),
            runtimeMode: .uiTest(.linked)
        )
        let session = AppSession(container: container)

        await waitUntil("auth observer loads linked session") {
            session.isSignedIn && session.group != nil && session.profile != nil
        }

        let userBaseline = userDataService.fetchUserCallCount
        let groupBaseline = groupService.fetchGroupCallCount
        let eventBaseline = eventService.fetchEventsCallCount

        await session.refreshJourney()

        XCTAssertEqual(userDataService.fetchUserCallCount - userBaseline, 0)
        XCTAssertEqual(groupService.fetchGroupCallCount - groupBaseline, 0)
        XCTAssertEqual(eventService.fetchEventsCallCount - eventBaseline, 1)

        let groupAfterJourney = groupService.fetchGroupCallCount
        let eventAfterJourney = eventService.fetchEventsCallCount

        await session.refreshHome()

        XCTAssertEqual(userDataService.fetchUserCallCount - userBaseline, 0)
        XCTAssertEqual(groupService.fetchGroupCallCount - groupAfterJourney, 1)
        XCTAssertEqual(eventService.fetchEventsCallCount - eventAfterJourney, 0)

        let groupAfterHome = groupService.fetchGroupCallCount
        let eventAfterHome = eventService.fetchEventsCallCount

        await session.refreshProfile()

        XCTAssertEqual(userDataService.fetchUserCallCount - userBaseline, 1)
        XCTAssertEqual(groupService.fetchGroupCallCount - groupAfterHome, 1)
        XCTAssertEqual(eventService.fetchEventsCallCount - eventAfterHome, 0)
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

@MainActor
private final class CountingUserDataService: UserDataServicing {
    private let store: UITestStore
    private(set) var fetchUserCallCount = 0

    init(store: UITestStore) {
        self.store = store
    }

    func upsertUser(_ user: UserProfile) async throws {
        store.users[user.id] = user
    }

    func fetchUser(uid: String) async throws -> UserProfile? {
        fetchUserCallCount += 1
        return store.users[uid]
    }

    func findUser(email: String) async throws -> UserProfile? {
        store.users.values.first { $0.email.caseInsensitiveCompare(email) == .orderedSame }
    }

    func resolveUserID(identifier: String) async throws -> String? {
        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        if normalized.contains("@") {
            return store.users.values.first {
                $0.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
            }?.id
        }

        return store.users[normalized] == nil ? nil : normalized
    }

    func setCurrentGroup(uid: String, groupId: String?) async throws {
        guard var user = store.users[uid] else { return }
        user.currentGroupId = groupId
        user.updatedAt = Date()
        store.users[uid] = user
    }

    func setHasCompletedOnboarding(uid: String, completed: Bool) async throws {
        guard var user = store.users[uid] else { return }
        user.hasCompletedOnboarding = completed
        user.updatedAt = Date()
        store.users[uid] = user
    }

    func updateFcmToken(uid: String, token: String) async throws {
        guard var user = store.users[uid] else { return }
        user.fcmToken = token
        user.updatedAt = Date()
        store.users[uid] = user
    }
}

@MainActor
private final class CountingGroupService: GroupServicing {
    private let store: UITestStore
    private(set) var fetchGroupCallCount = 0

    init(store: UITestStore) {
        self.store = store
    }

    func fetchGroup(groupId: String) async throws -> LoveGroup? {
        fetchGroupCallCount += 1
        return store.groups[groupId]
    }

    func createGroupAndLinkUsers(invite: Invite, groupName: String) async throws -> LoveGroup {
        let now = Date()
        let group = LoveGroup(
            id: "group_\(UUID().uuidString.prefix(8))",
            groupName: groupName,
            memberIds: [invite.fromUid, invite.toUid],
            createdBy: invite.toUid,
            status: .active,
            loveBalance: 0,
            lastEventAt: now,
            createdAt: now,
            updatedAt: now
        )
        store.groups[group.id] = group

        if var fromUser = store.users[invite.fromUid] {
            fromUser.currentGroupId = group.id
            fromUser.updatedAt = now
            store.users[invite.fromUid] = fromUser
        }
        if var toUser = store.users[invite.toUid] {
            toUser.currentGroupId = group.id
            toUser.updatedAt = now
            store.users[invite.toUid] = toUser
        }

        return group
    }

    func softUnlink(group: LoveGroup) async throws {
        guard let existing = store.groups[group.id] else { return }
        var updatedGroup = existing
        updatedGroup.status = .inactive
        updatedGroup.updatedAt = Date()
        store.groups[group.id] = updatedGroup

        for memberId in existing.memberIds {
            guard var user = store.users[memberId] else { continue }
            user.currentGroupId = nil
            user.updatedAt = Date()
            store.users[memberId] = user
        }
    }
}

@MainActor
private final class CountingEventService: EventServicing {
    private let store: UITestStore
    private let fetchDelayNanoseconds: UInt64
    private(set) var fetchEventsCallCount = 0

    init(store: UITestStore, fetchDelayNanoseconds: UInt64 = 0) {
        self.store = store
        self.fetchDelayNanoseconds = fetchDelayNanoseconds
    }

    func createEventAndUpdateGroup(
        groupId: String,
        createdBy: String,
        draft: EventDraft,
        eventId: String?
    ) async throws -> LoveEvent {
        let now = Date()
        let event = LoveEvent(
            id: eventId ?? UUID().uuidString,
            createdBy: createdBy,
            type: draft.type,
            tapCount: draft.tapCount,
            delta: draft.delta,
            note: draft.note,
            occurredAt: draft.occurredAt,
            recordedAt: now,
            location: draft.location,
            media: draft.media,
            createdAt: now,
            updatedAt: now
        )
        store.eventsByGroup[groupId, default: []].insert(event, at: 0)

        if var group = store.groups[groupId] {
            group.loveBalance += draft.delta
            group.lastEventAt = draft.occurredAt
            group.updatedAt = now
            store.groups[groupId] = group
        }

        return event
    }

    func fetchEvents(groupId: String, limit: Int) async throws -> [LoveEvent] {
        fetchEventsCallCount += 1
        if fetchDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: fetchDelayNanoseconds)
        }
        return Array(store.eventsByGroup[groupId, default: []].prefix(limit))
    }

    func appendMedia(groupId: String, eventId: String, media: EventMedia) async throws {
        guard var events = store.eventsByGroup[groupId],
              let index = events.firstIndex(where: { $0.id == eventId }) else {
            return
        }

        events[index].media.append(media)
        events[index].updatedAt = Date()
        store.eventsByGroup[groupId] = events
    }
}
