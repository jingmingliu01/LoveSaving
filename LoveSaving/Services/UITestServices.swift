import Foundation

enum UITestScenario: String, CaseIterable {
    case signedOut = "signed_out"
    case unlinked = "unlinked"
    case linked = "linked"
}

@MainActor
private final class UITestRealtimeSubscription: RealtimeSubscription {
    private var onCancel: (() -> Void)?

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        onCancel?()
        onCancel = nil
    }

    deinit {
        onCancel?()
    }
}

@MainActor
final class UITestStore {
    var users: [String: UserProfile]
    var invites: [String: Invite]
    var groups: [String: LoveGroup]
    var eventsByGroup: [String: [LoveEvent]]
    var authUser: AuthUser?
    private var inviteObservers: [UUID: InviteObserver] = [:]
    private var groupObservers: [UUID: GroupObserver] = [:]
    private var eventObservers: [UUID: EventObserver] = [:]

    init(
        users: [String: UserProfile],
        invites: [String: Invite],
        groups: [String: LoveGroup],
        eventsByGroup: [String: [LoveEvent]],
        authUser: AuthUser?
    ) {
        self.users = users
        self.invites = invites
        self.groups = groups
        self.eventsByGroup = eventsByGroup
        self.authUser = authUser
    }

    func addGroupObserver(
        groupId: String,
        onChange: @escaping @MainActor (Result<LoveGroup?, Error>) -> Void
    ) -> UUID {
        let id = UUID()
        groupObservers[id] = GroupObserver(groupId: groupId, onChange: onChange)
        return id
    }

    func removeGroupObserver(_ id: UUID) {
        groupObservers.removeValue(forKey: id)
    }

    func addInviteObserver(
        uid: String,
        onChange: @escaping @MainActor (Result<[Invite], Error>) -> Void
    ) -> UUID {
        let id = UUID()
        inviteObservers[id] = InviteObserver(uid: uid, onChange: onChange)
        return id
    }

    func removeInviteObserver(_ id: UUID) {
        inviteObservers.removeValue(forKey: id)
    }

    func addEventObserver(
        groupId: String,
        limit: Int,
        onChange: @escaping @MainActor (Result<[LoveEvent], Error>) -> Void
    ) -> UUID {
        let id = UUID()
        eventObservers[id] = EventObserver(groupId: groupId, limit: limit, onChange: onChange)
        return id
    }

    func removeEventObserver(_ id: UUID) {
        eventObservers.removeValue(forKey: id)
    }

    func emitGroupSnapshot(groupId: String) {
        let currentGroup = groups[groupId]
        for observer in groupObservers.values where observer.groupId == groupId {
            observer.onChange(.success(currentGroup))
        }
    }

    func emitInviteSnapshot(uid: String) {
        let currentInvites = invites.values
            .filter { $0.fromUid == uid || $0.toUid == uid }
            .sorted { $0.createdAt > $1.createdAt }
        for observer in inviteObservers.values where observer.uid == uid {
            observer.onChange(.success(currentInvites))
        }
    }

    func emitEventsSnapshot(groupId: String) {
        let currentEvents = (eventsByGroup[groupId] ?? []).sorted { $0.occurredAt > $1.occurredAt }
        for observer in eventObservers.values where observer.groupId == groupId {
            observer.onChange(.success(Array(currentEvents.prefix(observer.limit))))
        }
    }

    func activeGroupListenerCount(groupId: String? = nil) -> Int {
        guard let groupId else {
            return groupObservers.count
        }
        return groupObservers.values.filter { $0.groupId == groupId }.count
    }

    func activeEventListenerCount(groupId: String? = nil) -> Int {
        guard let groupId else {
            return eventObservers.count
        }
        return eventObservers.values.filter { $0.groupId == groupId }.count
    }

    private struct GroupObserver {
        let groupId: String
        let onChange: @MainActor (Result<LoveGroup?, Error>) -> Void
    }

    private struct InviteObserver {
        let uid: String
        let onChange: @MainActor (Result<[Invite], Error>) -> Void
    }

    private struct EventObserver {
        let groupId: String
        let limit: Int
        let onChange: @MainActor (Result<[LoveEvent], Error>) -> Void
    }

    static func makeSeeded(scenario: UITestScenario) -> UITestStore {
        let now = Date()
        let ownerId = "owner"
        let partnerId = "partner"

        var users: [String: UserProfile] = [
            ownerId: UserProfile(
                id: ownerId,
                displayName: "Owner",
                email: "owner@example.com",
                currentGroupId: nil,
                createdAt: now,
                updatedAt: now
            ),
            partnerId: UserProfile(
                id: partnerId,
                displayName: "Partner",
                email: "partner@example.com",
                currentGroupId: nil,
                createdAt: now,
                updatedAt: now
            )
        ]

        var invites: [String: Invite] = [:]
        var groups: [String: LoveGroup] = [:]
        var eventsByGroup: [String: [LoveEvent]] = [:]
        var authUser: AuthUser?

        switch scenario {
        case .signedOut:
            authUser = nil
        case .unlinked:
            authUser = AuthUser(uid: ownerId, email: "owner@example.com", displayName: "Owner")
            let invite = Invite(
                id: "invite_pending_1",
                fromUid: partnerId,
                fromDisplayName: users[partnerId]?.displayName,
                fromEmail: users[partnerId]?.email,
                toUid: ownerId,
                status: .pending,
                createdAt: now.addingTimeInterval(-300),
                expiresAt: now.addingTimeInterval(7 * 24 * 3600)
            )
            invites[invite.id] = invite
        case .linked:
            authUser = AuthUser(uid: ownerId, email: "owner@example.com", displayName: "Owner")
            let groupId = "group_1"
            users[ownerId]?.currentGroupId = groupId
            users[partnerId]?.currentGroupId = groupId

            let group = LoveGroup(
                id: groupId,
                groupName: "LoveSaving Group",
                memberIds: [ownerId, partnerId],
                createdBy: ownerId,
                status: .active,
                loveBalance: 12,
                lastEventAt: now.addingTimeInterval(-60),
                createdAt: now.addingTimeInterval(-3600),
                updatedAt: now.addingTimeInterval(-60)
            )
            groups[groupId] = group

            let seedEvent = LoveEvent(
                id: "event_seed_1",
                createdBy: ownerId,
                type: .deposit,
                tapCount: 3,
                delta: 4,
                note: "Seed event",
                occurredAt: now.addingTimeInterval(-60),
                recordedAt: now.addingTimeInterval(-60),
                location: EventLocation(lat: 40.7128, lng: -74.0060, addressText: "New York"),
                media: [],
                createdAt: now.addingTimeInterval(-60),
                updatedAt: now.addingTimeInterval(-60)
            )
            eventsByGroup[groupId] = [seedEvent]
        }

        return UITestStore(
            users: users,
            invites: invites,
            groups: groups,
            eventsByGroup: eventsByGroup,
            authUser: authUser
        )
    }
}

@MainActor
final class UITestAuthService: AuthServicing {
    private let store: UITestStore
    private let stream: AsyncStream<AuthUser?>
    private let continuation: AsyncStream<AuthUser?>.Continuation

    init(store: UITestStore) {
        self.store = store
        var resolved: AsyncStream<AuthUser?>.Continuation?
        self.stream = AsyncStream(bufferingPolicy: .bufferingNewest(10)) { continuation in
            resolved = continuation
        }
        self.continuation = resolved!
    }

    var currentUser: AuthUser? {
        store.authUser
    }

    func authStateStream() -> AsyncStream<AuthUser?> {
        continuation.yield(store.authUser)
        return stream
    }

    func ensureSessionReady() async throws {
        guard store.authUser != nil else {
            throw AppError.missingAuthUser
        }
    }

    func currentIDToken() async throws -> String? {
        nil
    }

    func signUp(email: String, password: String, displayName: String) async throws -> AuthUser {
        let uid = "user_\(UUID().uuidString.prefix(8))"
        let user = AuthUser(uid: uid, email: email, displayName: displayName)
        store.authUser = user
        continuation.yield(user)
        return user
    }

    func signIn(email: String, password: String) async throws -> AuthUser {
        if let existing = store.users.values.first(where: { $0.email.caseInsensitiveCompare(email) == .orderedSame }) {
            let user = AuthUser(uid: existing.id, email: existing.email, displayName: existing.displayName)
            store.authUser = user
            continuation.yield(user)
            return user
        }

        let uid = "user_\(UUID().uuidString.prefix(8))"
        let user = AuthUser(uid: uid, email: email, displayName: "LoveSaving User")
        store.authUser = user
        continuation.yield(user)
        return user
    }

    func signOut() throws {
        store.authUser = nil
        continuation.yield(nil)
    }

    func changePassword(newPassword: String) async throws {
        // No-op for deterministic UI testing.
    }
}

@MainActor
final class UITestUserDataService: UserDataServicing {
    private let store: UITestStore

    init(store: UITestStore) {
        self.store = store
    }

    func upsertUser(_ user: UserProfile) async throws {
        store.users[user.id] = user
    }

    func fetchUser(uid: String) async throws -> UserProfile? {
        store.users[uid]
    }

    func findUser(email: String) async throws -> UserProfile? {
        store.users.values.first { $0.email.caseInsensitiveCompare(email) == .orderedSame }
    }

    func resolveUser(identifier: String) async throws -> ResolvedUserIdentity? {
        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        if normalized.contains("@") {
            guard let user = store.users.values.first(where: {
                $0.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
            }) else {
                return nil
            }
            return ResolvedUserIdentity(uid: user.id, displayName: user.displayName, email: user.email)
        }

        guard let user = store.users[normalized] else { return nil }
        return ResolvedUserIdentity(uid: user.id, displayName: user.displayName, email: user.email)
    }

    func resolveUserID(identifier: String) async throws -> String? {
        try await resolveUser(identifier: identifier)?.uid
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
final class UITestInviteService: InviteServicing {
    private let store: UITestStore

    init(store: UITestStore) {
        self.store = store
    }

    func sendInvite(
        fromUid: String,
        toUid: String,
        expiresAt: Date?,
        fromDisplayName: String?,
        fromEmail: String?,
        toDisplayName: String?,
        toEmail: String?
    ) async throws -> Invite {
        let invite = Invite(
            id: "invite_\(UUID().uuidString.prefix(8))",
            fromUid: fromUid,
            fromDisplayName: fromDisplayName,
            fromEmail: fromEmail,
            toUid: toUid,
            toDisplayName: toDisplayName,
            toEmail: toEmail,
            status: .pending,
            createdAt: Date(),
            expiresAt: expiresAt
        )
        store.invites[invite.id] = invite
        store.emitInviteSnapshot(uid: fromUid)
        store.emitInviteSnapshot(uid: toUid)
        return invite
    }

    func fetchInvites(for uid: String) async throws -> [Invite] {
        store.invites.values
            .filter { $0.toUid == uid || $0.fromUid == uid }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func observeInvites(
        for uid: String,
        onChange: @escaping @MainActor (Result<[Invite], Error>) -> Void
    ) -> any RealtimeSubscription {
        let id = store.addInviteObserver(uid: uid, onChange: onChange)
        store.emitInviteSnapshot(uid: uid)
        return UITestRealtimeSubscription { [weak store] in
            Task { @MainActor in
                store?.removeInviteObserver(id)
            }
        }
    }

    func respondInvite(inviteId: String, status: InviteStatus, respondedAt: Date) async throws {
        guard var invite = store.invites[inviteId] else { return }
        guard invite.status == .pending else {
            throw AppError.invalidInviteState
        }
        invite.status = status
        invite.respondedAt = respondedAt
        store.invites[inviteId] = invite

        if status == .accepted {
            let group = LoveGroup(
                id: "group_\(UUID().uuidString.prefix(8))",
                groupName: "LoveSaving Group",
                memberIds: [invite.fromUid, invite.toUid],
                createdBy: invite.fromUid,
                status: .active,
                loveBalance: 0,
                lastEventAt: respondedAt,
                createdAt: respondedAt,
                updatedAt: respondedAt
            )
            store.groups[group.id] = group
            store.eventsByGroup[group.id] = []

            if var fromUser = store.users[invite.fromUid] {
                fromUser.currentGroupId = group.id
                fromUser.updatedAt = respondedAt
                store.users[invite.fromUid] = fromUser
            }

            if var toUser = store.users[invite.toUid] {
                toUser.currentGroupId = group.id
                toUser.updatedAt = respondedAt
                store.users[invite.toUid] = toUser
            }

            store.emitGroupSnapshot(groupId: group.id)
            store.emitEventsSnapshot(groupId: group.id)
        }

        store.emitInviteSnapshot(uid: invite.fromUid)
        store.emitInviteSnapshot(uid: invite.toUid)
    }
}

@MainActor
final class UITestGroupService: GroupServicing {
    private let store: UITestStore

    init(store: UITestStore) {
        self.store = store
    }

    func fetchGroup(groupId: String) async throws -> LoveGroup? {
        store.groups[groupId]
    }

    func createGroupAndLinkUsers(invite: Invite, groupName: String) async throws -> LoveGroup {
        let now = Date()
        let group = LoveGroup(
            id: "group_\(UUID().uuidString.prefix(8))",
            groupName: groupName,
            memberIds: [invite.fromUid, invite.toUid],
            createdBy: invite.fromUid,
            status: .active,
            loveBalance: 0,
            lastEventAt: now,
            createdAt: now,
            updatedAt: now
        )
        store.groups[group.id] = group
        store.eventsByGroup[group.id] = []
        try await UITestUserDataService(store: store).setCurrentGroup(uid: invite.fromUid, groupId: group.id)
        try await UITestUserDataService(store: store).setCurrentGroup(uid: invite.toUid, groupId: group.id)
        store.emitGroupSnapshot(groupId: group.id)
        store.emitEventsSnapshot(groupId: group.id)
        return group
    }

    func softUnlink(group: LoveGroup) async throws {
        guard var current = store.groups[group.id] else { return }
        current.status = .inactive
        current.updatedAt = Date()
        store.groups[group.id] = current

        for uid in current.memberIds {
            try await UITestUserDataService(store: store).setCurrentGroup(uid: uid, groupId: nil)
        }
        store.emitGroupSnapshot(groupId: group.id)
        store.emitEventsSnapshot(groupId: group.id)
    }

    func observeGroup(
        groupId: String,
        onChange: @escaping @MainActor (Result<LoveGroup?, Error>) -> Void
    ) -> any RealtimeSubscription {
        let id = store.addGroupObserver(groupId: groupId, onChange: onChange)
        store.emitGroupSnapshot(groupId: groupId)
        return UITestRealtimeSubscription { [weak store] in
            Task { @MainActor in
                store?.removeGroupObserver(id)
            }
        }
    }
}

@MainActor
final class UITestEventService: EventServicing {
    private let store: UITestStore

    init(store: UITestStore) {
        self.store = store
    }

    func createEventAndUpdateGroup(groupId: String, createdBy: String, draft: EventDraft, eventId: String?) async throws -> LoveEvent {
        guard var group = store.groups[groupId], group.status == .active else {
            throw AppError.invalidGroupState
        }

        let now = Date()
        let event = LoveEvent(
            id: eventId ?? "event_\(UUID().uuidString.prefix(8))",
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

        var events = store.eventsByGroup[groupId] ?? []
        events.append(event)
        store.eventsByGroup[groupId] = events

        group.loveBalance += draft.delta
        group.lastEventAt = max(group.lastEventAt, draft.occurredAt)
        group.updatedAt = now
        store.groups[groupId] = group
        store.emitGroupSnapshot(groupId: groupId)
        store.emitEventsSnapshot(groupId: groupId)

        return event
    }

    func fetchEvents(groupId: String, limit: Int) async throws -> [LoveEvent] {
        Array((store.eventsByGroup[groupId] ?? []).sorted(by: { $0.occurredAt > $1.occurredAt }).prefix(limit))
    }

    func updateEvent(groupId: String, eventId: String, note: String?, media: [EventMedia]) async throws {
        guard var events = store.eventsByGroup[groupId],
              let index = events.firstIndex(where: { $0.id == eventId }) else {
            throw AppError.eventNotFound
        }

        events[index].note = note
        events[index].media = media
        events[index].updatedAt = Date()
        store.eventsByGroup[groupId] = events
        store.emitEventsSnapshot(groupId: groupId)
    }

    func deleteEventAndUpdateGroup(groupId: String, eventId: String) async throws {
        guard var group = store.groups[groupId], group.status == .active else {
            throw AppError.invalidGroupState
        }
        guard var events = store.eventsByGroup[groupId],
              let index = events.firstIndex(where: { $0.id == eventId }) else {
            throw AppError.eventNotFound
        }

        let removedEvent = events.remove(at: index)
        store.eventsByGroup[groupId] = events

        group.loveBalance -= removedEvent.delta
        group.lastEventAt = events.map(\.occurredAt).max() ?? group.createdAt
        group.updatedAt = Date()
        store.groups[groupId] = group
        store.emitGroupSnapshot(groupId: groupId)
        store.emitEventsSnapshot(groupId: groupId)
    }

    func appendMedia(groupId: String, eventId: String, media: EventMedia) async throws {
        guard var events = store.eventsByGroup[groupId],
              let index = events.firstIndex(where: { $0.id == eventId }) else {
            return
        }
        events[index].media.append(media)
        events[index].updatedAt = Date()
        store.eventsByGroup[groupId] = events
        store.emitEventsSnapshot(groupId: groupId)
    }

    func observeRecentEvents(
        groupId: String,
        limit: Int,
        onChange: @escaping @MainActor (Result<[LoveEvent], Error>) -> Void
    ) -> any RealtimeSubscription {
        let id = store.addEventObserver(groupId: groupId, limit: limit, onChange: onChange)
        store.emitEventsSnapshot(groupId: groupId)
        return UITestRealtimeSubscription { [weak store] in
            Task { @MainActor in
                store?.removeEventObserver(id)
            }
        }
    }
}

@MainActor
final class UITestMediaService: MediaServicing {
    func uploadImageData(_ data: Data, groupId: String, eventId: String, fileExtension: String) async throws -> EventMedia {
        EventMedia(storagePath: "data:image/jpeg;base64,\(data.base64EncodedString())", contentType: "image/jpeg")
    }

    func deleteMedia(at storagePath: String) async throws {}
}

@MainActor
final class UITestMessagingService: MessagingServicing {
    var tokenStream: AsyncStream<String> {
        AsyncStream { _ in }
    }

    func requestNotificationAuthorization() async throws {}
    func scheduleDailyReflectionReminder() async throws {}
}

@MainActor
final class UITestAIInsightsAvailabilityService: AIInsightsAvailabilityServicing {
    func fetchAvailability() async -> AIInsightsAvailability {
        .unavailable(reason: "AI Insights backend is disabled in UI test mode.")
    }
}

struct UITestAIInsightsService: AIInsightsServicing {
    func fetchThreads() async throws -> [AIInsightThread] { [] }
    func fetchMessages(chatId: String) async throws -> [AIInsightMessage] { [] }
    func streamReply(chatId: String, contextGroupId: String, message: String) -> AsyncThrowingStream<AIInsightStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
    func renameThread(chatId: String, title: String) async throws -> AIInsightRenameResult {
        AIInsightRenameResult(chatId: chatId, title: title)
    }
    func softDeleteThread(chatId: String) async throws {}
}
