import Foundation

enum AppRuntimeMode: Equatable {
    case live
    case uiTest(UITestScenario)
}

@MainActor
struct AppContainer {
    let authService: AuthServicing
    let userDataService: UserDataServicing
    let inviteService: InviteServicing
    let groupService: GroupServicing
    let eventService: EventServicing
    let mediaService: MediaServicing
    let messagingService: MessagingServicing
    let runtimeMode: AppRuntimeMode

    init(
        authService: AuthServicing,
        userDataService: UserDataServicing,
        inviteService: InviteServicing,
        groupService: GroupServicing,
        eventService: EventServicing,
        mediaService: MediaServicing,
        messagingService: MessagingServicing,
        runtimeMode: AppRuntimeMode = .live
    ) {
        self.authService = authService
        self.userDataService = userDataService
        self.inviteService = inviteService
        self.groupService = groupService
        self.eventService = eventService
        self.mediaService = mediaService
        self.messagingService = messagingService
        self.runtimeMode = runtimeMode
    }

    var isUITestMode: Bool {
        if case .uiTest = runtimeMode {
            return true
        }
        return false
    }

    static let live: AppContainer = .init(
        authService: FirebaseAuthService(),
        userDataService: FirebaseUserDataService(),
        inviteService: FirebaseInviteService(),
        groupService: FirebaseGroupService(),
        eventService: FirebaseEventService(),
        mediaService: FirebaseStorageMediaService(),
        messagingService: FirebaseMessagingService(),
        runtimeMode: .live
    )

    static func forCurrentProcess() -> AppContainer {
        let env = ProcessInfo.processInfo.environment
        guard env["LOVEBANK_MODE"] == "UI_TEST" else {
            return .live
        }

        let scenario = UITestScenario(rawValue: env["LOVEBANK_SCENARIO"] ?? "") ?? .linked
        return .uiTest(scenario: scenario)
    }

    static func uiTest(scenario: UITestScenario) -> AppContainer {
        let store = UITestStore.makeSeeded(scenario: scenario)
        let auth = UITestAuthService(store: store)
        return .init(
            authService: auth,
            userDataService: UITestUserDataService(store: store),
            inviteService: UITestInviteService(store: store),
            groupService: UITestGroupService(store: store),
            eventService: UITestEventService(store: store),
            mediaService: UITestMediaService(),
            messagingService: UITestMessagingService(),
            runtimeMode: .uiTest(scenario)
        )
    }
}
