import Foundation

public enum InviteStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case accepted
    case rejected
    case expired
}

public enum GroupStatus: String, Codable, CaseIterable, Sendable {
    case active
    case inactive
}

public enum EventType: String, Codable, CaseIterable, Sendable {
    case deposit
    case withdraw
}

public struct UserProfile: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var displayName: String
    public var email: String
    public var photoURL: String?
    public var currentGroupId: String?
    public var hasCompletedOnboarding: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var fcmToken: String?

    public init(
        id: String,
        displayName: String,
        email: String,
        photoURL: String? = nil,
        currentGroupId: String? = nil,
        hasCompletedOnboarding: Bool = false,
        createdAt: Date,
        updatedAt: Date,
        fcmToken: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.photoURL = photoURL
        self.currentGroupId = currentGroupId
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.fcmToken = fcmToken
    }
}

public struct Invite: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var fromUid: String
    public var fromDisplayName: String?
    public var fromEmail: String?
    public var toUid: String
    public var status: InviteStatus
    public var createdAt: Date
    public var respondedAt: Date?
    public var expiresAt: Date?

    public init(
        id: String,
        fromUid: String,
        fromDisplayName: String? = nil,
        fromEmail: String? = nil,
        toUid: String,
        status: InviteStatus,
        createdAt: Date,
        respondedAt: Date? = nil,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.fromUid = fromUid
        self.fromDisplayName = fromDisplayName
        self.fromEmail = fromEmail
        self.toUid = toUid
        self.status = status
        self.createdAt = createdAt
        self.respondedAt = respondedAt
        self.expiresAt = expiresAt
    }
}

public struct LoveGroup: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var groupName: String
    public var memberIds: [String]
    public var createdBy: String
    public var status: GroupStatus
    public var loveBalance: Int
    public var lastEventAt: Date
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        groupName: String,
        memberIds: [String],
        createdBy: String,
        status: GroupStatus,
        loveBalance: Int,
        lastEventAt: Date,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.groupName = groupName
        self.memberIds = memberIds
        self.createdBy = createdBy
        self.status = status
        self.loveBalance = loveBalance
        self.lastEventAt = lastEventAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct EventMedia: Codable, Sendable, Equatable {
    public var storagePath: String
    public var contentType: String

    public init(storagePath: String, contentType: String) {
        self.storagePath = storagePath
        self.contentType = contentType
    }
}

public struct EventLocation: Codable, Sendable, Equatable {
    public var lat: Double
    public var lng: Double
    public var addressText: String?

    public init(lat: Double, lng: Double, addressText: String? = nil) {
        self.lat = lat
        self.lng = lng
        self.addressText = addressText
    }
}

public struct LoveEvent: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var createdBy: String
    public var type: EventType
    public var tapCount: Int
    public var delta: Int
    public var note: String?
    public var occurredAt: Date
    public var recordedAt: Date
    public var location: EventLocation
    public var media: [EventMedia]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        createdBy: String,
        type: EventType,
        tapCount: Int,
        delta: Int,
        note: String? = nil,
        occurredAt: Date,
        recordedAt: Date,
        location: EventLocation,
        media: [EventMedia] = [],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.createdBy = createdBy
        self.type = type
        self.tapCount = tapCount
        self.delta = delta
        self.note = note
        self.occurredAt = occurredAt
        self.recordedAt = recordedAt
        self.location = location
        self.media = media
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct EventDraft: Sendable {
    public var type: EventType
    public var tapCount: Int
    public var delta: Int
    public var note: String?
    public var occurredAt: Date
    public var location: EventLocation
    public var media: [EventMedia]

    public init(
        type: EventType,
        tapCount: Int,
        delta: Int,
        note: String?,
        occurredAt: Date,
        location: EventLocation,
        media: [EventMedia]
    ) {
        self.type = type
        self.tapCount = tapCount
        self.delta = delta
        self.note = note
        self.occurredAt = occurredAt
        self.location = location
        self.media = media
    }
}
