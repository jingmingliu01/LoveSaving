import CoreLocation
import Foundation
import Combine

@MainActor
final class AppSession: ObservableObject {
    @Published private(set) var authUser: AuthUser?
    @Published private(set) var profile: UserProfile?
    @Published private(set) var group: LoveGroup?
    @Published private(set) var inboundInvites: [Invite] = []
    @Published private(set) var events: [LoveEvent] = []
    @Published private(set) var hasResolvedInitialAuthState = false

    @Published var globalErrorMessage: String?
    @Published var isBusy = false

    private let container: AppContainer
    private let crashReporter: any CrashlyticsReporting
    private var authTask: Task<Void, Never>?
    private var messagingTask: Task<Void, Never>?
    private var crashRoute = "unknown"
    private var currentOperationContext = OperationContext.source("none")

    init(container: AppContainer) {
        self.container = container
        self.crashReporter = container.crashReporter
        syncCrashlyticsContext()
        observeAuthState()
        observeMessagingToken()
    }

    deinit {
        authTask?.cancel()
        messagingTask?.cancel()
    }

    var isSignedIn: Bool {
        authUser != nil
    }

    var isLinked: Bool {
        group?.status == .active
    }

    func updateCrashlyticsRoute(_ route: String) {
        crashRoute = route
        syncCrashlyticsContext()
    }

    func signUp(email: String, password: String, displayName: String) async {
        await runBusyTask(context: .source("auth.signUp")) { [self] in
            let user = try await container.authService.signUp(email: email, password: password, displayName: displayName)
            let now = Date()
            let profile = UserProfile(
                id: user.uid,
                displayName: displayName,
                email: user.email,
                createdAt: now,
                updatedAt: now
            )
            try await container.userDataService.upsertUser(profile)
            try await refreshForAuthUser(user)
        }
    }

    func signIn(email: String, password: String) async {
        await runBusyTask(context: .source("auth.signIn")) { [self] in
            let user = try await container.authService.signIn(email: email, password: password)
            _ = try await ensureProfileExists(for: user)
            try await refreshForAuthUser(user)
        }
    }

    func signOut() {
        do {
            try container.authService.signOut()
            authUser = nil
            profile = nil
            group = nil
            inboundInvites = []
            events = []
            globalErrorMessage = nil
            syncCrashlyticsContext()
        } catch {
            handleError(error, source: "auth.signOut", presentToUser: true)
        }
    }

    func changePassword(_ newPassword: String) async {
        await runBusyTask(context: .source("auth.changePassword")) { [self] in
            try await container.authService.changePassword(newPassword: newPassword)
        }
    }

    func changeDisplayName(_ newDisplayName: String) async {
        await runBusyTask(context: .source("profile.changeDisplayName")) { [self] in
            guard var currentProfile = profile else {
                throw AppError.userNotFound
            }

            let trimmed = newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            currentProfile.displayName = trimmed
            currentProfile.updatedAt = Date()
            try await container.userDataService.upsertUser(currentProfile)
            profile = currentProfile
            if let currentAuth = authUser {
                authUser = AuthUser(uid: currentAuth.uid, email: currentAuth.email, displayName: trimmed)
            }
        }
    }

    func refreshInvites() async {
        guard let uid = authUser?.uid else { return }
        do {
            try await container.authService.ensureSessionReady()
            await refreshInboundInvites(for: uid, source: "invite.refresh", presentToUser: false)
        } catch {
            handleError(error, source: "invite.refresh", presentToUser: true)
        }
    }

    func sendInvite(to identifier: String) async {
        await runBusyTask(context: .source("invite.send")) { [self] in
            try await container.authService.ensureSessionReady()
            let currentUser = try await resolvedAuthUser()

            guard let targetUID = try await container.userDataService.resolveUserID(identifier: identifier) else {
                throw AppError.userNotFound
            }

            if targetUID == currentUser.uid {
                throw AppError.invalidInviteState
            }

            _ = try await container.inviteService.sendInvite(
                fromUid: currentUser.uid,
                toUid: targetUID,
                expiresAt: Calendar.current.date(byAdding: .day, value: 7, to: Date()),
                fromDisplayName: profile?.displayName ?? currentUser.displayName,
                fromEmail: profile?.email ?? currentUser.email
            )

            // Post-send refresh should never mask a successful send.
            do {
                inboundInvites = try await fetchActiveInboundInvites(for: currentUser.uid)
            } catch {
                handleError(error, source: "invite.send.postRefresh", presentToUser: false)
            }
        }
    }

    func respond(invite: Invite, accept: Bool) async {
        await runBusyTask(context: .inviteResponse(accept, source: "invite.respond")) { [self] in
            let respondedAt = Date()
            if let expiresAt = invite.expiresAt, expiresAt <= respondedAt {
                try await container.inviteService.respondInvite(
                    inviteId: invite.id,
                    status: .expired,
                    respondedAt: respondedAt
                )
                if let current = authUser {
                    try await refreshForAuthUser(current)
                }
                throw AppError.invalidInviteState
            }

            let status: InviteStatus = accept ? .accepted : .rejected
            try await container.inviteService.respondInvite(
                inviteId: invite.id,
                status: status,
                respondedAt: respondedAt
            )

            if accept {
                let acceptedInvite = Invite(
                    id: invite.id,
                    fromUid: invite.fromUid,
                    fromDisplayName: invite.fromDisplayName,
                    fromEmail: invite.fromEmail,
                    toUid: invite.toUid,
                    status: .accepted,
                    createdAt: invite.createdAt,
                    respondedAt: respondedAt,
                    expiresAt: invite.expiresAt
                )
                _ = try await container.groupService.createGroupAndLinkUsers(
                    invite: acceptedInvite,
                    groupName: "LoveSaving Group"
                )
            }

            if let current = authUser {
                try await refreshForAuthUser(current)
            }
        }
    }

    @discardableResult
    func submitTapBurst(
        tapCount: Int,
        type: EventType,
        note: String?,
        imageData: Data?,
        imageFileExtension: String = "jpg",
        coordinate: CLLocationCoordinate2D?,
        addressText: String?
    ) async -> Bool {
        await runBusyTask(
            context: .tapBurst(
                source: "event.submitTapBurst",
                eventType: type,
                tapCount: tapCount,
                hasImage: imageData != nil
            )
        ) { [self] in
            guard tapCount > 0 else {
                throw AppError.emptyTapBurst
            }
            guard let currentUser = authUser else {
                throw AppError.missingAuthUser
            }
            guard let group else {
                throw AppError.missingGroup
            }
            guard let coordinate else {
                throw AppError.locationUnavailable
            }

            let occurredAt = Date()
            let delta = LoveDeltaCalculator.signedDelta(forTapCount: tapCount, type: type)
            let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedNote = (trimmedNote?.isEmpty == false)
                ? trimmedNote
                : NoteBuilder.defaultNote(occurredAt: occurredAt, addressText: addressText)

            var draft = EventDraft(
                type: type,
                tapCount: tapCount,
                delta: delta,
                note: resolvedNote,
                occurredAt: occurredAt,
                location: EventLocation(
                    lat: coordinate.latitude,
                    lng: coordinate.longitude,
                    addressText: addressText
                ),
                media: []
            )

            let eventId = UUID().uuidString

            if let imageData {
                let media = try await container.mediaService.uploadImageData(
                    imageData,
                    groupId: group.id,
                    eventId: eventId,
                    fileExtension: imageFileExtension
                )
                draft.media = [media]
            }

            _ = try await container.eventService.createEventAndUpdateGroup(
                groupId: group.id,
                createdBy: currentUser.uid,
                draft: draft,
                eventId: eventId
            )

            if let refreshedGroup = try await container.groupService.fetchGroup(groupId: group.id) {
                self.group = refreshedGroup
            }
            events = try await container.eventService.fetchEvents(groupId: group.id, limit: 200)
            syncCrashlyticsContext()
        }
    }

    func refreshEvents() async {
        guard let group else { return }
        do {
            events = try await container.eventService.fetchEvents(groupId: group.id, limit: 200)
            syncCrashlyticsContext()
        } catch {
            handleError(error, source: "event.refresh", presentToUser: true)
        }
    }

    @discardableResult
    func updateJourneyEvent(
        _ event: LoveEvent,
        note: String,
        imageData: Data?,
        imageFileExtension: String = "jpg",
        removeExistingImage: Bool
    ) async -> Bool {
        await runBusyTask(context: .source("event.updateJourneyEvent")) { [self] in
            guard let currentUser = authUser else {
                throw AppError.missingAuthUser
            }
            guard let group else {
                throw AppError.missingGroup
            }
            guard event.createdBy == currentUser.uid else {
                throw AppError.eventPermissionDenied
            }

            let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedNote = trimmedNote.isEmpty ? nil : trimmedNote
            let shouldReplaceExistingMedia = !event.media.isEmpty && (removeExistingImage || imageData != nil)
            let obsoleteMedia = shouldReplaceExistingMedia ? event.media : []
            var updatedMedia = shouldReplaceExistingMedia ? [] : event.media
            var uploadedReplacement: EventMedia?

            do {
                if let imageData {
                    let uploaded = try await container.mediaService.uploadImageData(
                        imageData,
                        groupId: group.id,
                        eventId: event.id,
                        fileExtension: imageFileExtension
                    )
                    uploadedReplacement = uploaded
                    updatedMedia = [uploaded]
                }

                try await container.eventService.updateEvent(
                    groupId: group.id,
                    eventId: event.id,
                    note: resolvedNote,
                    media: updatedMedia
                )
            } catch {
                if let uploadedReplacement {
                    try? await container.mediaService.deleteMedia(at: uploadedReplacement.storagePath)
                }
                throw error
            }

            if let refreshedGroup = try await container.groupService.fetchGroup(groupId: group.id) {
                self.group = refreshedGroup
            }
            events = try await container.eventService.fetchEvents(groupId: group.id, limit: 200)
            await deleteMediaBestEffort(obsoleteMedia, source: "event.updateJourneyEvent.cleanup")
            syncCrashlyticsContext()
        }
    }

    @discardableResult
    func deleteJourneyEvent(_ event: LoveEvent) async -> Bool {
        await runBusyTask(context: .source("event.deleteJourneyEvent")) { [self] in
            guard let currentUser = authUser else {
                throw AppError.missingAuthUser
            }
            guard let group else {
                throw AppError.missingGroup
            }
            guard event.createdBy == currentUser.uid else {
                throw AppError.eventPermissionDenied
            }

            try await container.eventService.deleteEventAndUpdateGroup(groupId: group.id, eventId: event.id)
            if let refreshedGroup = try await container.groupService.fetchGroup(groupId: group.id) {
                self.group = refreshedGroup
            }
            events = try await container.eventService.fetchEvents(groupId: group.id, limit: 200)
            await deleteMediaBestEffort(event.media, source: "event.deleteJourneyEvent.cleanup")
            syncCrashlyticsContext()
        }
    }

    @discardableResult
    func markOnboardingCompleted() async -> Bool {
        guard let uid = authUser?.uid ?? container.authService.currentUser?.uid else {
            return false
        }

        do {
            applyOperationContext(.source("profile.markOnboardingCompleted"))
            try await container.userDataService.setHasCompletedOnboarding(uid: uid, completed: true)
            if var currentProfile = profile {
                currentProfile.hasCompletedOnboarding = true
                currentProfile.updatedAt = Date()
                profile = currentProfile
            }
            syncCrashlyticsContext()
            return true
        } catch {
            handleError(error, source: "profile.markOnboardingCompleted", presentToUser: false)
            return false
        }
    }

    func softUnlinkCurrentGroup() async {
        await runBusyTask(context: .source("group.softUnlink")) { [self] in
            guard let group else {
                throw AppError.missingGroup
            }

            try await container.groupService.softUnlink(group: group)
            if let current = authUser {
                try await refreshForAuthUser(current)
            }
        }
    }

    func requestNotifications(suppressErrors: Bool = false) async {
        do {
            applyOperationContext(.source("notifications.request"))
            try await container.messagingService.requestNotificationAuthorization()
            try await container.messagingService.scheduleDailyReflectionReminder()
        } catch {
            handleError(
                error,
                source: "notifications.request",
                presentToUser: !suppressErrors
            )
        }
    }

    private func observeAuthState() {
        authTask = Task { [weak self] in
            guard let self else { return }
            for await authState in container.authService.authStateStream() {
                guard !Task.isCancelled else { break }
                do {
                    if let authState {
                        try await refreshForAuthUser(authState)
                    } else {
                        authUser = nil
                        profile = nil
                        group = nil
                        inboundInvites = []
                        events = []
                    }
                    hasResolvedInitialAuthState = true
                    syncCrashlyticsContext()
                } catch {
                    handleError(error, source: "auth.observe", presentToUser: true)
                    hasResolvedInitialAuthState = true
                    syncCrashlyticsContext()
                }
            }
        }
    }

    private func observeMessagingToken() {
        messagingTask = Task { [weak self] in
            guard let self else { return }
            for await token in container.messagingService.tokenStream {
                guard !Task.isCancelled else { break }
                guard let uid = authUser?.uid else { continue }
                do {
                    try await container.userDataService.updateFcmToken(uid: uid, token: token)
                } catch {
                    handleError(error, source: "messaging.tokenUpload", presentToUser: false)
                }
            }
        }
    }

    private func refreshForAuthUser(_ user: AuthUser) async throws {
        try await container.authService.ensureSessionReady()
        authUser = user

        let profile = try await ensureProfileExists(for: user)
        self.profile = profile

        if let currentGroupId = profile.currentGroupId,
           let group = try await container.groupService.fetchGroup(groupId: currentGroupId),
           group.status == .active {
            self.group = group
            inboundInvites = []
            events = try await container.eventService.fetchEvents(groupId: currentGroupId, limit: 200)
        } else {
            self.group = nil
            events = []
            await refreshInboundInvites(
                for: user.uid,
                source: "auth.refresh.inboundInvites",
                presentToUser: false
            )
        }

        syncCrashlyticsContext()
    }

    private func refreshInboundInvites(
        for uid: String,
        source: String,
        presentToUser: Bool
    ) async {
        do {
            inboundInvites = try await fetchActiveInboundInvites(for: uid)
        } catch {
            inboundInvites = []
            handleError(error, source: source, presentToUser: presentToUser)
        }
        syncCrashlyticsContext()
    }

    private func fetchActiveInboundInvites(for uid: String) async throws -> [Invite] {
        let invites = try await container.inviteService.fetchInboundInvites(for: uid)
        let now = Date()
        var active: [Invite] = []

        for invite in invites {
            if let expiresAt = invite.expiresAt, expiresAt <= now {
                try await container.inviteService.respondInvite(
                    inviteId: invite.id,
                    status: .expired,
                    respondedAt: now
                )
            } else {
                active.append(invite)
            }
        }

        return active
    }

    private func deleteMediaBestEffort(_ media: [EventMedia], source: String) async {
        for item in media {
            do {
                try await container.mediaService.deleteMedia(at: item.storagePath)
            } catch {
                let nsError = error as NSError
                crashReporter.log(
                    "source=\(source) route=\(crashRoute) cleanup=media_delete path=\(item.storagePath) domain=\(nsError.domain) code=\(nsError.code)"
                )
            }
        }
    }

    private func ensureProfileExists(for user: AuthUser) async throws -> UserProfile {
        if let existing = try await container.userDataService.fetchUser(uid: user.uid) {
            return existing
        }

        let now = Date()
        let fallbackProfile = UserProfile(
            id: user.uid,
            displayName: user.displayName ?? "LoveSaving User",
            email: user.email,
            currentGroupId: nil,
            createdAt: now,
            updatedAt: now
        )
        try await container.userDataService.upsertUser(fallbackProfile)

        // Firestore server timestamps can take a short moment to become readable.
        for attempt in 0..<5 {
            if let created = try await container.userDataService.fetchUser(uid: user.uid) {
                return created
            }
            if attempt < 4 {
                let delay = UInt64((attempt + 1) * 150_000_000)
                try await Task.sleep(nanoseconds: delay)
            }
        }

        throw AppError.profileNotReady
    }

    private func resolvedAuthUser() async throws -> AuthUser {
        if let current = authUser {
            return current
        }
        if let current = container.authService.currentUser {
            try await refreshForAuthUser(current)
            return current
        }
        throw AppError.missingAuthUser
    }

    @discardableResult
    private func runBusyTask(
        context: OperationContext,
        _ operation: @escaping () async throws -> Void
    ) async -> Bool {
        globalErrorMessage = nil
        isBusy = true
        applyOperationContext(context)
        defer {
            isBusy = false
        }

        do {
            try await operation()
            return true
        } catch {
            handleError(error, source: context.source, presentToUser: true)
            return false
        }
    }

    private func handleError(_ error: Error, source: String, presentToUser: Bool) {
        if currentOperationContext.source != source {
            applyOperationContext(.source(source))
        }
        syncCrashlyticsContext()
        let nsError = error as NSError
        crashReporter.log(
            "source=\(source) route=\(crashRoute) type=\(String(reflecting: type(of: error))) domain=\(nsError.domain) code=\(nsError.code)"
        )
        if !(error is AppError) {
            crashReporter.record(error: error)
        }
        print("[AppSession][\(source)] \(error.localizedDescription)")
        if presentToUser {
            globalErrorMessage = error.localizedDescription
        }
    }

    private func syncCrashlyticsContext() {
        crashReporter.setUserID(authUser?.uid ?? "")
        crashReporter.setCustomValue(container.runtimeMode.crashlyticsValue, forKey: "runtime_mode")
        crashReporter.setCustomValue(crashRoute, forKey: "app_route")
        crashReporter.setCustomValue(hasResolvedInitialAuthState, forKey: "has_resolved_initial_auth_state")
        crashReporter.setCustomValue(isSignedIn, forKey: "is_signed_in")
        crashReporter.setCustomValue(profile?.hasCompletedOnboarding == true, forKey: "has_completed_onboarding")
        crashReporter.setCustomValue(isLinked, forKey: "is_linked")
        crashReporter.setCustomValue(group != nil, forKey: "group_id_present")
        crashReporter.setCustomValue(inboundInvites.count, forKey: "inbound_invite_count")
        crashReporter.setCustomValue(events.count, forKey: "cached_event_count")
    }

    private func applyOperationContext(_ context: OperationContext) {
        currentOperationContext = context
        crashReporter.setCustomValue(context.source, forKey: "last_operation")
        crashReporter.setCustomValue(context.eventType, forKey: "operation_event_type")
        crashReporter.setCustomValue(context.tapCount, forKey: "operation_tap_count")
        crashReporter.setCustomValue(context.hasImage, forKey: "operation_has_image")
        crashReporter.setCustomValue(context.inviteResponse, forKey: "operation_invite_response")
    }
}

private struct OperationContext {
    let source: String
    let eventType: String
    let tapCount: Int
    let hasImage: Bool
    let inviteResponse: String

    init(
        source: String,
        eventType: String = "none",
        tapCount: Int = -1,
        hasImage: Bool = false,
        inviteResponse: String = "none"
    ) {
        self.source = source
        self.eventType = eventType
        self.tapCount = tapCount
        self.hasImage = hasImage
        self.inviteResponse = inviteResponse
    }

    static func source(_ source: String) -> OperationContext {
        OperationContext(source: source)
    }

    static func tapBurst(
        source: String,
        eventType: EventType,
        tapCount: Int,
        hasImage: Bool
    ) -> OperationContext {
        OperationContext(
            source: source,
            eventType: eventType.rawValue,
            tapCount: tapCount,
            hasImage: hasImage
        )
    }

    static func inviteResponse(_ accept: Bool, source: String) -> OperationContext {
        OperationContext(
            source: source,
            inviteResponse: accept ? "accept" : "reject"
        )
    }
}
