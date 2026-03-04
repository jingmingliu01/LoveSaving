import Foundation

struct AuthUser: Equatable {
    let uid: String
    let email: String
    let displayName: String?
}

enum AppError: LocalizedError {
    case missingAuthUser
    case missingGroup
    case userNotFound
    case profileNotReady
    case invalidInviteState
    case invalidGroupState
    case locationUnavailable
    case emptyTapBurst
    case imageTooLargeForUpload

    var errorDescription: String? {
        switch self {
        case .missingAuthUser:
            return "You need to sign in before performing this action."
        case .missingGroup:
            return "Please link with your partner first."
        case .userNotFound:
            return "Recipient user was not found."
        case .profileNotReady:
            return "Your profile is still initializing. Please try again."
        case .invalidInviteState:
            return "Invite is no longer pending."
        case .invalidGroupState:
            return "Group is inactive or invalid."
        case .locationUnavailable:
            return "Current location is not available yet."
        case .emptyTapBurst:
            return "Tap at least once before submitting."
        case .imageTooLargeForUpload:
            return "Image is too large. Please choose a smaller image."
        }
    }
}

@MainActor
protocol AuthServicing {
    var currentUser: AuthUser? { get }
    func authStateStream() -> AsyncStream<AuthUser?>
    func ensureSessionReady() async throws
    func signUp(email: String, password: String, displayName: String) async throws -> AuthUser
    func signIn(email: String, password: String) async throws -> AuthUser
    func signOut() throws
    func changePassword(newPassword: String) async throws
}

@MainActor
protocol UserDataServicing {
    func upsertUser(_ user: UserProfile) async throws
    func fetchUser(uid: String) async throws -> UserProfile?
    func findUser(email: String) async throws -> UserProfile?
    func resolveUserID(identifier: String) async throws -> String?
    func setCurrentGroup(uid: String, groupId: String?) async throws
    func updateFcmToken(uid: String, token: String) async throws
}

@MainActor
protocol InviteServicing {
    func sendInvite(
        fromUid: String,
        toUid: String,
        expiresAt: Date?,
        fromDisplayName: String?,
        fromEmail: String?
    ) async throws -> Invite
    func fetchInboundInvites(for uid: String) async throws -> [Invite]
    func respondInvite(inviteId: String, status: InviteStatus, respondedAt: Date) async throws
}

@MainActor
protocol GroupServicing {
    func fetchGroup(groupId: String) async throws -> LoveGroup?
    func createGroupAndLinkUsers(invite: Invite, groupName: String) async throws -> LoveGroup
    func softUnlink(group: LoveGroup) async throws
}

@MainActor
protocol EventServicing {
    func createEventAndUpdateGroup(groupId: String, createdBy: String, draft: EventDraft, eventId: String?) async throws -> LoveEvent
    func fetchEvents(groupId: String, limit: Int) async throws -> [LoveEvent]
    func appendMedia(groupId: String, eventId: String, media: EventMedia) async throws
}

@MainActor
protocol MediaServicing {
    func uploadImageData(_ data: Data, groupId: String, eventId: String, fileExtension: String) async throws -> EventMedia
}

@MainActor
protocol MessagingServicing {
    func requestNotificationAuthorization() async throws
    func scheduleDailyReflectionReminder() async throws
    var tokenStream: AsyncStream<String> { get }
}
