import Foundation
@preconcurrency import FirebaseAuth
import FirebaseCore
@preconcurrency import FirebaseFirestore
import FirebaseFunctions
import FirebaseMessaging
import FirebasePerformance
import FirebaseStorage
#if canImport(UIKit)
import UIKit
import UserNotifications
#endif

@MainActor
final class FirebaseAuthService: AuthServicing {
    private let auth: Auth

    init(auth: Auth = .auth()) {
        self.auth = auth
    }

    var currentUser: AuthUser? {
        guard let user = auth.currentUser, let email = user.email else {
            return nil
        }

        return AuthUser(uid: user.uid, email: email, displayName: user.displayName)
    }

    func authStateStream() -> AsyncStream<AuthUser?> {
        AsyncStream { continuation in
            _ = auth.addStateDidChangeListener { _, user in
                if let user, let email = user.email {
                    continuation.yield(AuthUser(uid: user.uid, email: email, displayName: user.displayName))
                } else {
                    continuation.yield(nil)
                }
            }
        }
    }

    func ensureSessionReady() async throws {
        guard let user = auth.currentUser else {
            throw AppError.missingAuthUser
        }

        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AuthTokenResult, Error>) in
            user.getIDTokenResult(forcingRefresh: false) { tokenResult, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let tokenResult {
                    continuation.resume(returning: tokenResult)
                } else {
                    continuation.resume(throwing: AppError.missingAuthUser)
                }
            }
        }
    }

    func signUp(email: String, password: String, displayName: String) async throws -> AuthUser {
        try await withPerformanceTrace("auth_sign_up") {
            let result: AuthDataResult = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AuthDataResult, Error>) in
                auth.createUser(withEmail: email, password: password) { result, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let result {
                        continuation.resume(returning: result)
                    }
                }
            }

            let request = result.user.createProfileChangeRequest()
            request.displayName = displayName
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                request.commitChanges { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }

            return AuthUser(uid: result.user.uid, email: email, displayName: displayName)
        }
    }

    func signIn(email: String, password: String) async throws -> AuthUser {
        try await withPerformanceTrace("auth_sign_in") {
            let result: AuthDataResult = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AuthDataResult, Error>) in
                auth.signIn(withEmail: email, password: password) { result, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let result {
                        continuation.resume(returning: result)
                    }
                }
            }

            guard let resolvedEmail = result.user.email else {
                throw AppError.userNotFound
            }

            return AuthUser(uid: result.user.uid, email: resolvedEmail, displayName: result.user.displayName)
        }
    }

    func signOut() throws {
        try auth.signOut()
    }

    func changePassword(newPassword: String) async throws {
        guard let user = auth.currentUser else {
            throw AppError.missingAuthUser
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            user.updatePassword(to: newPassword) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

@MainActor
final class FirebaseUserDataService: UserDataServicing {
    private let db: Firestore
    private let functions: Functions

    init(db: Firestore = .firestore(), functions: Functions = .functions()) {
        self.db = db
        self.functions = functions
    }

    func upsertUser(_ user: UserProfile) async throws {
        try await withPerformanceTrace("user_upsert_profile") {
            let emailLower = user.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let userRef = db.collection("users").document(user.id)
            let snapshot = try await userRef.getDocument()
            let batch = db.batch()

            if snapshot.exists {
                var payload: [String: Any] = [
                    "displayName": user.displayName,
                    "email": user.email,
                    "emailLower": emailLower,
                    "photoURL": firestoreNullable(user.photoURL),
                    "currentGroupId": firestoreNullable(user.currentGroupId),
                    "hasCompletedOnboarding": user.hasCompletedOnboarding,
                    "updatedAt": FieldValue.serverTimestamp(),
                    "fcmToken": firestoreNullable(user.fcmToken)
                ]

                // Backfill legacy docs so strict rules and profile decoding remain stable.
                if snapshot.data()?["createdAt"] == nil {
                    payload["createdAt"] = FieldValue.serverTimestamp()
                }

                batch.setData(payload, forDocument: userRef, merge: true)
            } else {
                batch.setData([
                    "displayName": user.displayName,
                    "email": user.email,
                    "emailLower": emailLower,
                    "photoURL": firestoreNullable(user.photoURL),
                    "currentGroupId": firestoreNullable(user.currentGroupId),
                    "hasCompletedOnboarding": user.hasCompletedOnboarding,
                    "createdAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp(),
                    "fcmToken": firestoreNullable(user.fcmToken)
                ], forDocument: userRef, merge: true)
            }

            try await batch.commit()
        }
    }

    func fetchUser(uid: String) async throws -> UserProfile? {
        let snapshot = try await db.collection("users").document(uid).getDocument()
        guard snapshot.exists else {
            return nil
        }
        return snapshot.toUserProfile()
    }

    func findUser(email: String) async throws -> UserProfile? {
        try await withPerformanceTrace("user_find_by_identifier") {
            guard let resolved = try await resolveUserByIdentifier(email) else {
                return nil
            }
            let now = Date()
            return UserProfile(
                id: resolved.uid,
                displayName: resolved.displayName ?? "LoveSaving User",
                email: resolved.email ?? email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                currentGroupId: nil,
                createdAt: now,
                updatedAt: now
            )
        }
    }

    func resolveUserID(identifier: String) async throws -> String? {
        try await resolveUserByIdentifier(identifier)?.uid
    }

    func setCurrentGroup(uid: String, groupId: String?) async throws {
        try await db.collection("users").document(uid).setData([
            "currentGroupId": firestoreNullable(groupId),
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    func setHasCompletedOnboarding(uid: String, completed: Bool) async throws {
        try await db.collection("users").document(uid).setData([
            "hasCompletedOnboarding": completed,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    func updateFcmToken(uid: String, token: String) async throws {
        try await db.collection("users").document(uid).setData([
            "fcmToken": token,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    private func resolveUserByIdentifier(_ identifier: String) async throws -> ResolvedUser? {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let normalized = trimmed.contains("@") ? trimmed.lowercased() : trimmed
        let callable = functions.httpsCallable("resolveUserIdentifier")
        do {
            let result = try await callable.call(["identifier": normalized])
            guard let payload = result.data as? [String: Any],
                  let uid = payload["uid"] as? String else {
                return nil
            }
            return ResolvedUser(
                uid: uid,
                displayName: payload["displayName"] as? String,
                email: payload["email"] as? String
            )
        } catch {
            if let nsError = error as NSError?,
               nsError.domain == FunctionsErrorDomain,
               let code = FunctionsErrorCode(rawValue: nsError.code),
               code == .notFound {
                return nil
            }
            throw error
        }
    }

    private struct ResolvedUser {
        let uid: String
        let displayName: String?
        let email: String?
    }
}

@MainActor
final class FirebaseInviteService: InviteServicing {
    private let db: Firestore
    private let auth: Auth

    init(db: Firestore = .firestore(), auth: Auth = .auth()) {
        self.db = db
        self.auth = auth
    }

    func sendInvite(
        fromUid: String,
        toUid: String,
        expiresAt: Date?,
        fromDisplayName: String?,
        fromEmail: String?
    ) async throws -> Invite {
        guard let authUID = auth.currentUser?.uid, authUID == fromUid else {
            throw AppError.missingAuthUser
        }

        let ref = db.collection("invites").document()
        let createdAt = Date()
        let invite = Invite(
            id: ref.documentID,
            fromUid: fromUid,
            fromDisplayName: fromDisplayName,
            fromEmail: fromEmail,
            toUid: toUid,
            status: .pending,
            createdAt: createdAt,
            expiresAt: expiresAt
        )

        try await ref.setData([
            "fromUid": invite.fromUid,
            "fromDisplayName": firestoreNullable(invite.fromDisplayName),
            "fromEmail": firestoreNullable(invite.fromEmail),
            "toUid": invite.toUid,
            "status": invite.status.rawValue,
            "createdAt": FieldValue.serverTimestamp(),
            "expiresAt": (invite.expiresAt.map(Timestamp.init(date:)) ?? NSNull()) as Any
        ])

        return invite
    }

    func fetchInboundInvites(for uid: String) async throws -> [Invite] {
        let snapshot = try await db.collection("invites")
            .whereField("toUid", isEqualTo: uid)
            .whereField("status", isEqualTo: InviteStatus.pending.rawValue)
            .order(by: "createdAt", descending: true)
            .getDocuments()

        return snapshot.documents.compactMap { $0.toInvite() }
    }

    func respondInvite(inviteId: String, status: InviteStatus, respondedAt: Date) async throws {
        _ = respondedAt
        try await db.collection("invites").document(inviteId).updateData([
            "status": status.rawValue,
            "respondedAt": FieldValue.serverTimestamp()
        ])
    }
}

@MainActor
final class FirebaseGroupService: GroupServicing {
    private let db: Firestore

    init(db: Firestore = .firestore()) {
        self.db = db
    }

    func fetchGroup(groupId: String) async throws -> LoveGroup? {
        let snapshot = try await db.collection("groups").document(groupId).getDocument()
        guard snapshot.exists else {
            return nil
        }

        return snapshot.toLoveGroup()
    }

    func createGroupAndLinkUsers(invite: Invite, groupName: String) async throws -> LoveGroup {
        try await withPerformanceTrace("group_create_and_link_users") {
            guard invite.status == .pending || invite.status == .accepted else {
                throw AppError.invalidInviteState
            }

            let groupRef = db.collection("groups").document()
            let now = Date()

            let group = LoveGroup(
                id: groupRef.documentID,
                groupName: groupName,
                memberIds: [invite.fromUid, invite.toUid],
                createdBy: invite.fromUid,
                status: .active,
                loveBalance: 0,
                lastEventAt: now,
                createdAt: now,
                updatedAt: now
            )

            let batch = db.batch()
            batch.setData([
                "groupName": group.groupName,
                "memberIds": group.memberIds,
                "createdBy": group.createdBy,
                "sourceInviteId": invite.id,
                "status": group.status.rawValue,
                "loveBalance": group.loveBalance,
                "lastEventAt": Timestamp(date: group.lastEventAt),
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ], forDocument: groupRef)

            let fromRef = db.collection("users").document(invite.fromUid)
            let toRef = db.collection("users").document(invite.toUid)
            batch.setData([
                "currentGroupId": group.id,
                "updatedAt": FieldValue.serverTimestamp()
            ], forDocument: fromRef, merge: true)
            batch.setData([
                "currentGroupId": group.id,
                "updatedAt": FieldValue.serverTimestamp()
            ], forDocument: toRef, merge: true)

            try await batch.commit()
            return group
        }
    }

    func softUnlink(group: LoveGroup) async throws {
        let batch = db.batch()
        let groupRef = db.collection("groups").document(group.id)
        batch.updateData([
            "status": GroupStatus.inactive.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: groupRef)

        for uid in group.memberIds {
            let userRef = db.collection("users").document(uid)
            batch.setData([
                "currentGroupId": NSNull(),
                "updatedAt": FieldValue.serverTimestamp()
            ], forDocument: userRef, merge: true)
        }

        try await batch.commit()
    }
}

@MainActor
final class FirebaseEventService: EventServicing {
    private let db: Firestore

    init(db: Firestore = .firestore()) {
        self.db = db
    }

    func createEventAndUpdateGroup(groupId: String, createdBy: String, draft: EventDraft, eventId: String?) async throws -> LoveEvent {
        try await withPerformanceTrace("event_create_and_update_group") {
            let groupRef = db.collection("groups").document(groupId)
            let now = Date()

            let eventID: String = try await withCheckedThrowingContinuation { continuation in
                db.runTransaction({ transaction, errorPointer -> Any? in
                    do {
                        let groupSnapshot = try transaction.getDocument(groupRef)
                        guard let groupData = groupSnapshot.data(),
                              let statusRaw = groupData["status"] as? String,
                              statusRaw == GroupStatus.active.rawValue else {
                            throw AppError.invalidGroupState
                        }

                        let previousLastEvent = (groupData["lastEventAt"] as? Timestamp)?.dateValue() ?? draft.occurredAt
                        let nextLastEvent = max(previousLastEvent, draft.occurredAt)

                        let eventRef = eventId.map { groupRef.collection("events").document($0) }
                            ?? groupRef.collection("events").document()
                        transaction.setData([
                            "createdBy": createdBy,
                            "type": draft.type.rawValue,
                            "tapCount": draft.tapCount,
                            "delta": draft.delta,
                            "note": firestoreNullable(draft.note),
                            "occurredAt": Timestamp(date: draft.occurredAt),
                        "location": [
                                "lat": draft.location.lat,
                                "lng": draft.location.lng,
                                "addressText": firestoreNullable(draft.location.addressText)
                            ],
                            "media": draft.media.map { ["storagePath": $0.storagePath, "contentType": $0.contentType] },
                            "createdAt": FieldValue.serverTimestamp(),
                            "recordedAt": FieldValue.serverTimestamp(),
                            "updatedAt": FieldValue.serverTimestamp()
                        ], forDocument: eventRef)

                        transaction.updateData([
                            "loveBalance": FieldValue.increment(Int64(draft.delta)),
                            "lastEventAt": Timestamp(date: nextLastEvent),
                            "updatedAt": FieldValue.serverTimestamp()
                        ], forDocument: groupRef)

                        return eventRef.documentID
                    } catch {
                        errorPointer?.pointee = error as NSError
                        return nil
                    }
                }, completion: { value, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let eventID = value as? String {
                        continuation.resume(returning: eventID)
                    } else {
                        continuation.resume(throwing: AppError.invalidGroupState)
                    }
                })
            }

            return LoveEvent(
                id: eventID,
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
        }
    }

    func fetchEvents(groupId: String, limit: Int) async throws -> [LoveEvent] {
        try await withPerformanceTrace("event_fetch_history") {
            let snapshot = try await db.collection("groups")
                .document(groupId)
                .collection("events")
                .order(by: "occurredAt", descending: true)
                .limit(to: limit)
                .getDocuments()

            return snapshot.documents.compactMap { $0.toLoveEvent() }
        }
    }

    func appendMedia(groupId: String, eventId: String, media: EventMedia) async throws {
        let eventRef = db.collection("groups")
            .document(groupId)
            .collection("events")
            .document(eventId)

        try await eventRef.updateData([
            "media": FieldValue.arrayUnion([
                [
                    "storagePath": media.storagePath,
                    "contentType": media.contentType
                ]
            ]),
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }
}

@MainActor
final class FirebaseStorageMediaService: MediaServicing {
    private let storage: Storage
    private let maxUploadBytes: Int
    private let maxImageDimension: CGFloat

    // Client-side acceptance cap before processing.
    static let maxAcceptedInputBytes: Int = 20 * 1024 * 1024

    init(
        storage: Storage = .storage(),
        maxUploadBytes: Int = 8 * 1024 * 1024,
        maxImageDimension: CGFloat = 1_600
    ) {
        self.storage = storage
        self.maxUploadBytes = maxUploadBytes
        self.maxImageDimension = maxImageDimension
    }

    func uploadImageData(_ data: Data, groupId: String, eventId: String, fileExtension: String) async throws -> EventMedia {
        try await withPerformanceTrace("storage_upload_image") {
            guard data.count <= Self.maxAcceptedInputBytes else {
                throw AppError.imageTooLargeForUpload
            }

            let prepared = try prepareUpload(data: data, preferredExtension: fileExtension)
            let filename = "\(UUID().uuidString).\(prepared.fileExtension)"
            let path = "groups/\(groupId)/events/\(eventId)/\(filename)"
            let ref = storage.reference(withPath: path)
            let metadata = StorageMetadata()
            metadata.contentType = prepared.contentType

            _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<StorageMetadata, Error>) in
                ref.putData(prepared.data, metadata: metadata) { metadata, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let metadata {
                        continuation.resume(returning: metadata)
                    } else {
                        continuation.resume(throwing: AppError.imageTooLargeForUpload)
                    }
                }
            }

            return EventMedia(storagePath: path, contentType: prepared.contentType)
        }
    }

    private func prepareUpload(data: Data, preferredExtension: String) throws -> (data: Data, contentType: String, fileExtension: String) {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else {
            throw AppError.imageTooLargeForUpload
        }

        let resized = resizeIfNeeded(image)
        let normalizedExtension = preferredExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let wantsPNG = normalizedExtension == "png"

        if wantsPNG, let png = resized.pngData(), png.count <= maxUploadBytes {
            return (png, "image/png", "png")
        }

        var quality: CGFloat = 0.85
        while quality >= 0.2 {
            if let jpeg = resized.jpegData(compressionQuality: quality), jpeg.count <= maxUploadBytes {
                return (jpeg, "image/jpeg", "jpg")
            }
            quality -= 0.1
        }
        #endif

        throw AppError.imageTooLargeForUpload
    }

    #if canImport(UIKit)
    private func resizeIfNeeded(_ image: UIImage) -> UIImage {
        let maxSide = max(image.size.width, image.size.height)
        guard maxSide > maxImageDimension else {
            return image
        }

        let scale = maxImageDimension / maxSide
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
    #endif
}

@MainActor
final class FirebaseMessagingService: NSObject, MessagingServicing {
    private let stream: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation

    override init() {
        var resolvedContinuation: AsyncStream<String>.Continuation?
        stream = AsyncStream { continuation in
            resolvedContinuation = continuation
        }
        continuation = resolvedContinuation!

        super.init()
        Messaging.messaging().delegate = self
    }

    var tokenStream: AsyncStream<String> {
        stream
    }

    func requestNotificationAuthorization() async throws {
        #if canImport(UIKit)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }

        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
        #endif
    }

    func scheduleDailyReflectionReminder() async throws {
        #if canImport(UIKit)
        let content = UNMutableNotificationContent()
        content.title = "LoveSaving Reminder"
        content.body = "Take a moment to reflect and log a meaningful moment today."
        content.sound = .default

        var components = DateComponents()
        components.hour = 20
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: "daily_reflection", content: content, trigger: trigger)
        try await UNUserNotificationCenter.current().add(request)
        #endif
    }
}

extension FirebaseMessagingService: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        continuation.yield(fcmToken)
    }
}

private func firestoreNullable(_ value: String?) -> Any {
    value ?? NSNull()
}

private func withPerformanceTrace<T>(
    _ name: String,
    _ operation: () async throws -> T
) async throws -> T {
    let trace = Performance.startTrace(name: name)
    do {
        let value = try await operation()
        trace?.setValue("ok", forAttribute: "status")
        trace?.stop()
        return value
    } catch {
        trace?.setValue("error", forAttribute: "status")
        trace?.stop()
        throw error
    }
}

private extension DocumentSnapshot {
    func toUserProfile() -> UserProfile? {
        // Use estimated server timestamps to avoid transient nils right after writes.
        let resolvedData = data(with: .estimate) ?? data()
        guard let data = resolvedData,
              let displayName = data["displayName"] as? String,
              let email = data["email"] as? String else {
            return nil
        }

        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
            ?? (data["updatedAt"] as? Timestamp)?.dateValue()
            ?? Date()
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
            ?? createdAt

        return UserProfile(
            id: documentID,
            displayName: displayName,
            email: email,
            photoURL: data["photoURL"] as? String,
            currentGroupId: data["currentGroupId"] as? String,
            hasCompletedOnboarding: data["hasCompletedOnboarding"] as? Bool ?? false,
            createdAt: createdAt,
            updatedAt: updatedAt,
            fcmToken: data["fcmToken"] as? String
        )
    }

    func toInvite() -> Invite? {
        guard let data = data(),
              let fromUid = data["fromUid"] as? String,
              let toUid = data["toUid"] as? String,
              let statusRaw = data["status"] as? String,
              let status = InviteStatus(rawValue: statusRaw),
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() else {
            return nil
        }

        return Invite(
            id: documentID,
            fromUid: fromUid,
            fromDisplayName: data["fromDisplayName"] as? String,
            fromEmail: data["fromEmail"] as? String,
            toUid: toUid,
            status: status,
            createdAt: createdAt,
            respondedAt: (data["respondedAt"] as? Timestamp)?.dateValue(),
            expiresAt: (data["expiresAt"] as? Timestamp)?.dateValue()
        )
    }

    func toLoveGroup() -> LoveGroup? {
        guard let data = data(),
              let groupName = data["groupName"] as? String,
              let memberIds = data["memberIds"] as? [String],
              let createdBy = data["createdBy"] as? String,
              let statusRaw = data["status"] as? String,
              let status = GroupStatus(rawValue: statusRaw),
              let loveBalance = data["loveBalance"] as? Int,
              let lastEventAt = (data["lastEventAt"] as? Timestamp)?.dateValue(),
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
              let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() else {
            return nil
        }

        return LoveGroup(
            id: documentID,
            groupName: groupName,
            memberIds: memberIds,
            createdBy: createdBy,
            status: status,
            loveBalance: loveBalance,
            lastEventAt: lastEventAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func toLoveEvent() -> LoveEvent? {
        guard let data = data(),
              let createdBy = data["createdBy"] as? String,
              let typeRaw = data["type"] as? String,
              let type = EventType(rawValue: typeRaw),
              let tapCount = data["tapCount"] as? Int,
              let delta = data["delta"] as? Int,
              let occurredAt = (data["occurredAt"] as? Timestamp)?.dateValue(),
              let locationMap = data["location"] as? [String: Any],
              let lat = locationMap["lat"] as? Double,
              let lng = locationMap["lng"] as? Double,
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
              let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() else {
            return nil
        }
        let recordedAt = (data["recordedAt"] as? Timestamp)?.dateValue() ?? createdAt

        let mediaMap = data["media"] as? [[String: Any]] ?? []
        let media = mediaMap.compactMap { map -> EventMedia? in
            guard let storagePath = map["storagePath"] as? String,
                  let contentType = map["contentType"] as? String else {
                return nil
            }

            return EventMedia(storagePath: storagePath, contentType: contentType)
        }

        return LoveEvent(
            id: documentID,
            createdBy: createdBy,
            type: type,
            tapCount: tapCount,
            delta: delta,
            note: data["note"] as? String,
            occurredAt: occurredAt,
            recordedAt: recordedAt,
            location: EventLocation(lat: lat, lng: lng, addressText: locationMap["addressText"] as? String),
            media: media,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
