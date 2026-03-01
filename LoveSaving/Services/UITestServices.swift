import Foundation

enum UITestScenario: String, CaseIterable {
    case signedOut = "signed_out"
    case unlinked = "unlinked"
    case linked = "linked"
}

@MainActor
final class UITestStore {
    var users: [String: UserProfile]
    var invites: [String: Invite]
    var groups: [String: LoveGroup]
    var eventsByGroup: [String: [LoveEvent]]
    var authUser: AuthUser?

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
                groupName: "LoveBank Group",
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
        let user = AuthUser(uid: uid, email: email, displayName: "LoveBank User")
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
        fromEmail: String?
    ) async throws -> Invite {
        let invite = Invite(
            id: "invite_\(UUID().uuidString.prefix(8))",
            fromUid: fromUid,
            fromDisplayName: fromDisplayName,
            fromEmail: fromEmail,
            toUid: toUid,
            status: .pending,
            createdAt: Date(),
            expiresAt: expiresAt
        )
        store.invites[invite.id] = invite
        return invite
    }

    func fetchInboundInvites(for uid: String) async throws -> [Invite] {
        store.invites.values
            .filter { $0.toUid == uid && $0.status == .pending }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func respondInvite(inviteId: String, status: InviteStatus, respondedAt: Date) async throws {
        guard var invite = store.invites[inviteId] else { return }
        invite.status = status
        invite.respondedAt = respondedAt
        store.invites[inviteId] = invite
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

        return event
    }

    func fetchEvents(groupId: String, limit: Int) async throws -> [LoveEvent] {
        Array((store.eventsByGroup[groupId] ?? []).sorted(by: { $0.occurredAt > $1.occurredAt }).prefix(limit))
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

@MainActor
final class UITestMediaService: MediaServicing {
    func uploadImageData(_ data: Data, groupId: String, eventId: String, fileExtension: String) async throws -> EventMedia {
        EventMedia(storagePath: "data:image/jpeg;base64,\(data.base64EncodedString())", contentType: "image/jpeg")
    }
}

@MainActor
final class UITestMessagingService: MessagingServicing {
    var tokenStream: AsyncStream<String> {
        AsyncStream { _ in }
    }

    func requestNotificationAuthorization() async throws {}
    func scheduleDailyReflectionReminder() async throws {}
}
