import CoreLocation
import Foundation
import Combine

@MainActor
final class AppSession: ObservableObject {
    enum RefreshScope: Hashable {
        case home
        case journey
        case profile
    }

    enum RefreshState: Equatable {
        case idle
        case loading
        case success(Date)
        case error(String)

        var errorMessage: String? {
            guard case .error(let message) = self else { return nil }
            return message
        }
    }

    @Published private(set) var authUser: AuthUser?
    @Published private(set) var profile: UserProfile?
    @Published private(set) var group: LoveGroup?
    @Published private(set) var inboundInvites: [Invite] = []
    @Published private(set) var events: [LoveEvent] = []
    @Published private(set) var aiInsightsAvailability: AIInsightsAvailability = .checking
    @Published private(set) var hasResolvedInitialAuthState = false

    @Published var globalErrorMessage: String?
    @Published var isBusy = false
    @Published private(set) var homeRefreshState: RefreshState = .idle
    @Published private(set) var journeyRefreshState: RefreshState = .idle
    @Published private(set) var profileRefreshState: RefreshState = .idle

    private let container: AppContainer
    private let crashReporter: any CrashlyticsReporting
    private let refreshDebounceInterval: TimeInterval = 0.6
    private var authTask: Task<Void, Never>?
    private var messagingTask: Task<Void, Never>?
    private var groupRealtimeSubscription: (any RealtimeSubscription)?
    private var eventsRealtimeSubscription: (any RealtimeSubscription)?
    private var realtimeGroupID: String?
    private var pendingRealtimeGroup: LoveGroup?
    private var pendingRealtimeEvents: [LoveEvent]?
    private var groupRealtimeDebounceTask: Task<Void, Never>?
    private var eventsRealtimeDebounceTask: Task<Void, Never>?
    private var inviteRealtimeRefreshTask: Task<Void, Never>?
    private var inFlightRefreshTasks: [RefreshScope: Task<Void, Never>] = [:]
    private var lastRefreshAt: [RefreshScope: Date] = [:]
    private var aiInsightsAvailabilityTask: Task<Void, Never>?
    private var crashRoute = "unknown"
    private var currentOperationContext = OperationContext.source("none")
    private let realtimeEventLimit = 200
    private let realtimeDebounceNanoseconds: UInt64 = 350_000_000

    init(container: AppContainer) {
        self.container = container
        self.crashReporter = container.crashReporter
        syncCrashlyticsContext()
        observeAuthState()
        observeMessagingToken()
        refreshAIInsightsAvailabilityIfNeeded()
    }

    deinit {
        authTask?.cancel()
        messagingTask?.cancel()
        inviteRealtimeRefreshTask?.cancel()
        inFlightRefreshTasks.values.forEach { $0.cancel() }
        aiInsightsAvailabilityTask?.cancel()
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
            resetSession()
        } catch {
            handleError(error, source: "auth.signOut", presentToUser: true)
        }
    }

    func resetSession() {
        stopRealtimeObservers()
        resetRefreshStates()
        authUser = nil
        profile = nil
        group = nil
        inboundInvites = []
        events = []
        globalErrorMessage = nil
        syncCrashlyticsContext()
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

    func refreshHome() async {
        await refresh(scope: .home, source: "home.refresh") { [self] in
            guard let groupId = group?.id ?? profile?.currentGroupId else {
                stopRealtimeObservers()
                group = nil
                events = []
                if let uid = authUser?.uid {
                    await refreshInboundInvites(
                        for: uid,
                        source: "home.refresh.inboundInvites",
                        presentToUser: false
                    )
                }
                syncCrashlyticsContext()
                return
            }

            if let refreshedGroup = try await container.groupService.fetchGroup(groupId: groupId),
               refreshedGroup.status == .active {
                group = refreshedGroup
                startRealtimeObserversIfNeeded(for: groupId)
            } else {
                stopRealtimeObservers()
                group = nil
                events = []
                if let uid = authUser?.uid {
                    await refreshInboundInvites(
                        for: uid,
                        source: "home.refresh.inboundInvites",
                        presentToUser: false
                    )
                }
            }
            syncCrashlyticsContext()
        }
    }

    func refreshJourney() async {
        await refresh(scope: .journey, source: "journey.refresh") { [self] in
            guard let groupId = group?.id ?? profile?.currentGroupId else {
                stopRealtimeObservers()
                group = nil
                events = []
                syncCrashlyticsContext()
                return
            }

            events = try await container.eventService.fetchEvents(groupId: groupId, limit: 200)
            syncCrashlyticsContext()
        }
    }

    func refreshProfile() async {
        await refresh(scope: .profile, source: "profile.refresh") { [self] in
            guard let currentUser = authUser ?? container.authService.currentUser else { return }

            try await container.authService.ensureSessionReady()
            let refreshedProfile = try await ensureProfileExists(for: currentUser)
            profile = refreshedProfile

            if let currentGroupId = refreshedProfile.currentGroupId,
               let refreshedGroup = try await container.groupService.fetchGroup(groupId: currentGroupId),
               refreshedGroup.status == .active {
                group = refreshedGroup
                startRealtimeObserversIfNeeded(for: currentGroupId)
            } else {
                stopRealtimeObservers()
                group = nil
                events = []
                await refreshInboundInvites(
                    for: currentUser.uid,
                    source: "profile.refresh.inboundInvites",
                    presentToUser: false
                )
            }
            syncCrashlyticsContext()
        }
    }

    func refreshState(for scope: RefreshScope) -> RefreshState {
        switch scope {
        case .home:
            return homeRefreshState
        case .journey:
            return journeyRefreshState
        case .profile:
            return profileRefreshState
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
            guard let group else {
                throw AppError.missingGroup
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
            guard let group else {
                throw AppError.missingGroup
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

    func refreshAIInsightsAvailability() async {
        aiInsightsAvailability = .checking
        aiInsightsAvailability = await container.aiInsightsAvailabilityService.fetchAvailability()
        syncCrashlyticsContext()
    }

    func refreshAIInsightsAvailabilityIfNeeded() {
        aiInsightsAvailabilityTask?.cancel()
        aiInsightsAvailabilityTask = Task { [weak self] in
            guard let self else { return }
            await refreshAIInsightsAvailability()
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
                        resetSession()
                    }
                    refreshAIInsightsAvailabilityIfNeeded()
                    hasResolvedInitialAuthState = true
                    syncCrashlyticsContext()
                } catch {
                    handleError(error, source: "auth.observe", presentToUser: true)
                    refreshAIInsightsAvailabilityIfNeeded()
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
            events = try await container.eventService.fetchEvents(groupId: currentGroupId, limit: realtimeEventLimit)
            startRealtimeObserversIfNeeded(for: currentGroupId)
        } else {
            stopRealtimeObservers()
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

    private func refresh(
        scope: RefreshScope,
        source: String,
        operation: @escaping @MainActor () async throws -> Void
    ) async {
        if let existingTask = inFlightRefreshTasks[scope] {
            await existingTask.value
            return
        }

        let now = Date()
        if let lastRefreshAt = lastRefreshAt[scope],
           now.timeIntervalSince(lastRefreshAt) < refreshDebounceInterval {
            return
        }

        lastRefreshAt[scope] = now
        setRefreshState(.loading, for: scope)

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            applyOperationContext(.source(source))
            defer {
                inFlightRefreshTasks[scope] = nil
            }

            do {
                try await operation()
                guard !Task.isCancelled else { return }
                setRefreshState(.success(Date()), for: scope)
            } catch is CancellationError {
                // Sign-out/reset intentionally cancels in-flight refreshes.
            } catch {
                guard !Task.isCancelled else { return }
                setRefreshState(.error(error.localizedDescription), for: scope)
                handleError(error, source: source, presentToUser: false)
            }
        }

        inFlightRefreshTasks[scope] = task
        await task.value
    }

    private func resetRefreshStates() {
        homeRefreshState = .idle
        journeyRefreshState = .idle
        profileRefreshState = .idle
        inFlightRefreshTasks.values.forEach { $0.cancel() }
        inFlightRefreshTasks.removeAll()
        lastRefreshAt.removeAll()
    }

    private func setRefreshState(_ state: RefreshState, for scope: RefreshScope) {
        switch scope {
        case .home:
            homeRefreshState = state
        case .journey:
            journeyRefreshState = state
        case .profile:
            profileRefreshState = state
        }
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
        crashReporter.setCustomValue(aiInsightsAvailability.isEnabled, forKey: "ai_insights_enabled")
    }

    private func applyOperationContext(_ context: OperationContext) {
        currentOperationContext = context
        crashReporter.setCustomValue(context.source, forKey: "last_operation")
        crashReporter.setCustomValue(context.eventType, forKey: "operation_event_type")
        crashReporter.setCustomValue(context.tapCount, forKey: "operation_tap_count")
        crashReporter.setCustomValue(context.hasImage, forKey: "operation_has_image")
        crashReporter.setCustomValue(context.inviteResponse, forKey: "operation_invite_response")
    }

    private func startRealtimeObserversIfNeeded(for groupId: String) {
        guard authUser != nil else {
            stopRealtimeObservers()
            return
        }

        guard realtimeGroupID != groupId || groupRealtimeSubscription == nil || eventsRealtimeSubscription == nil else {
            return
        }

        stopRealtimeObservers()
        realtimeGroupID = groupId

        groupRealtimeSubscription = container.groupService.observeGroup(groupId: groupId) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let observedGroup):
                guard self.realtimeGroupID == groupId else { return }
                guard let observedGroup, observedGroup.status == .active else {
                    self.handleRealtimeGroupUnavailable(groupId: groupId)
                    return
                }
                self.scheduleRealtimeGroupUpdate(observedGroup, groupId: groupId)
            case .failure(let error):
                self.handleError(error, source: "realtime.group", presentToUser: false)
            }
        }

        eventsRealtimeSubscription = container.eventService.observeRecentEvents(
            groupId: groupId,
            limit: realtimeEventLimit
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let observedEvents):
                guard self.realtimeGroupID == groupId else { return }
                self.scheduleRealtimeEventsUpdate(observedEvents, groupId: groupId)
            case .failure(let error):
                self.handleError(error, source: "realtime.events", presentToUser: false)
            }
        }
    }

    private func stopRealtimeObservers() {
        groupRealtimeDebounceTask?.cancel()
        groupRealtimeDebounceTask = nil
        eventsRealtimeDebounceTask?.cancel()
        eventsRealtimeDebounceTask = nil
        inviteRealtimeRefreshTask?.cancel()
        inviteRealtimeRefreshTask = nil
        pendingRealtimeGroup = nil
        pendingRealtimeEvents = nil
        groupRealtimeSubscription?.cancel()
        groupRealtimeSubscription = nil
        eventsRealtimeSubscription?.cancel()
        eventsRealtimeSubscription = nil
        realtimeGroupID = nil
    }

    private func scheduleRealtimeGroupUpdate(_ updatedGroup: LoveGroup, groupId: String) {
        pendingRealtimeGroup = updatedGroup
        groupRealtimeDebounceTask?.cancel()
        groupRealtimeDebounceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: realtimeDebounceNanoseconds)
            guard !Task.isCancelled,
                  realtimeGroupID == groupId,
                  let pendingRealtimeGroup else {
                return
            }

            self.pendingRealtimeGroup = nil
            if group != pendingRealtimeGroup {
                group = pendingRealtimeGroup
                syncCrashlyticsContext()
            }
        }
    }

    private func scheduleRealtimeEventsUpdate(_ updatedEvents: [LoveEvent], groupId: String) {
        pendingRealtimeEvents = updatedEvents
        eventsRealtimeDebounceTask?.cancel()
        eventsRealtimeDebounceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: realtimeDebounceNanoseconds)
            guard !Task.isCancelled,
                  realtimeGroupID == groupId,
                  let pendingRealtimeEvents else {
                return
            }

            self.pendingRealtimeEvents = nil
            if events != pendingRealtimeEvents {
                events = pendingRealtimeEvents
                syncCrashlyticsContext()
            }
        }
    }

    private func handleRealtimeGroupUnavailable(groupId: String) {
        guard realtimeGroupID == groupId else { return }
        stopRealtimeObservers()
        group = nil
        events = []
        syncCrashlyticsContext()

        if let uid = authUser?.uid {
            inviteRealtimeRefreshTask?.cancel()
            inviteRealtimeRefreshTask = Task { @MainActor [weak self] in
                await self?.refreshInboundInvites(
                    for: uid,
                    source: "realtime.group.unlinked",
                    presentToUser: false
                )
            }
        }
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
