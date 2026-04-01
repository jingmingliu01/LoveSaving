import Foundation

struct AuthUser: Equatable {
    let uid: String
    let email: String
    let displayName: String?
}

struct AIInsightsCapabilities: Equatable, Decodable {
    let enabled: Bool
    let streamingSupported: Bool
    let multimodalSupported: Bool
    let environment: String
    let primaryModelProvider: String
    let primaryTextModel: String
    let primaryMultimodalModel: String
    let status: String
    let reason: String?
}

struct AIInsightThread: Identifiable, Codable, Equatable, Sendable {
    var chatId: String
    var title: String
    var lastMessagePreview: String?
    var lastMessageRole: String?
    var lastMessageAt: Date?
    var contextGroupId: String
    var groupNameAtCreation: String?
    var isDeleted: Bool

    var id: String { chatId }
}

struct AIInsightMessage: Identifiable, Codable, Equatable, Sendable {
    var messageId: String
    var role: String
    var messageType: String
    var content: String
    var createdAt: Date

    var id: String { messageId }

    var isUser: Bool {
        role == "user"
    }
}

struct AIInsightRenameResult: Equatable, Codable, Sendable {
    let chatId: String
    let title: String
}

enum AIInsightStreamEvent: Equatable, Sendable {
    case metadata(chatId: String, uid: String, groupId: String)
    case delta(String)
    case done(title: String)
}

enum AIInsightsAvailability: Equatable {
    case checking
    case unavailable(reason: String)
    case available(AIInsightsCapabilities)

    var isEnabled: Bool {
        if case .available = self {
            return true
        }
        return false
    }

    var title: String {
        switch self {
        case .checking:
            return "Checking Insights"
        case .unavailable:
            return "Insights Unavailable"
        case .available:
            return "Insights Available"
        }
    }

    var message: String {
        switch self {
        case .checking:
            return "Checking whether the AI Insights backend is configured for this build."
        case .unavailable(let reason):
            return reason
        case .available(let capabilities):
            return "Backend is configured with \(capabilities.primaryModelProvider) / \(capabilities.primaryTextModel). The streaming chat UI will replace this placeholder next."
        }
    }
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
    case eventNotFound

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
        case .eventNotFound:
            return "That journey item could not be found."
        }
    }
}

@MainActor
protocol RealtimeSubscription: AnyObject {
    func cancel()
}

@MainActor
protocol AuthServicing {
    var currentUser: AuthUser? { get }
    func authStateStream() -> AsyncStream<AuthUser?>
    func ensureSessionReady() async throws
    func currentIDToken() async throws -> String?
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
    func setHasCompletedOnboarding(uid: String, completed: Bool) async throws
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
    func observeGroup(
        groupId: String,
        onChange: @escaping @MainActor (Result<LoveGroup?, Error>) -> Void
    ) -> any RealtimeSubscription
}

@MainActor
protocol EventServicing {
    func createEventAndUpdateGroup(groupId: String, createdBy: String, draft: EventDraft, eventId: String?) async throws -> LoveEvent
    func fetchEvents(groupId: String, limit: Int) async throws -> [LoveEvent]
    func updateEvent(groupId: String, eventId: String, note: String?, media: [EventMedia]) async throws
    func deleteEventAndUpdateGroup(groupId: String, eventId: String) async throws
    func appendMedia(groupId: String, eventId: String, media: EventMedia) async throws
    func observeRecentEvents(
        groupId: String,
        limit: Int,
        onChange: @escaping @MainActor (Result<[LoveEvent], Error>) -> Void
    ) -> any RealtimeSubscription
}

@MainActor
protocol MediaServicing {
    func uploadImageData(_ data: Data, groupId: String, eventId: String, fileExtension: String) async throws -> EventMedia
    func deleteMedia(at storagePath: String) async throws
}

@MainActor
protocol MessagingServicing {
    func requestNotificationAuthorization() async throws
    func scheduleDailyReflectionReminder() async throws
    var tokenStream: AsyncStream<String> { get }
}

protocol AIInsightsAvailabilityServicing {
    func fetchAvailability() async -> AIInsightsAvailability
}

protocol AIInsightsServicing {
    func fetchThreads() async throws -> [AIInsightThread]
    func fetchMessages(chatId: String) async throws -> [AIInsightMessage]
    func streamReply(chatId: String, contextGroupId: String, message: String) -> AsyncThrowingStream<AIInsightStreamEvent, Error>
    func renameThread(chatId: String, title: String) async throws -> AIInsightRenameResult
    func softDeleteThread(chatId: String) async throws
}
