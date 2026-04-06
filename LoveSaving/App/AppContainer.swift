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
    let aiInsightsAvailabilityService: AIInsightsAvailabilityServicing
    let aiInsightsService: AIInsightsServicing
    let crashReporter: any CrashlyticsReporting
    let runtimeMode: AppRuntimeMode

    init(
        authService: AuthServicing,
        userDataService: UserDataServicing,
        inviteService: InviteServicing,
        groupService: GroupServicing,
        eventService: EventServicing,
        mediaService: MediaServicing,
        messagingService: MessagingServicing,
        aiInsightsAvailabilityService: AIInsightsAvailabilityServicing,
        aiInsightsService: AIInsightsServicing,
        crashReporter: any CrashlyticsReporting,
        runtimeMode: AppRuntimeMode = .live
    ) {
        self.authService = authService
        self.userDataService = userDataService
        self.inviteService = inviteService
        self.groupService = groupService
        self.eventService = eventService
        self.mediaService = mediaService
        self.messagingService = messagingService
        self.aiInsightsAvailabilityService = aiInsightsAvailabilityService
        self.aiInsightsService = aiInsightsService
        self.crashReporter = crashReporter
        self.runtimeMode = runtimeMode
    }

    var isUITestMode: Bool {
        switch runtimeMode {
        case .uiTest:
            return true
        case .live:
            return false
        }
    }

    static let live: AppContainer = {
        let authService = FirebaseAuthService()
        return .init(
            authService: authService,
            userDataService: FirebaseUserDataService(),
            inviteService: FirebaseInviteService(),
            groupService: FirebaseGroupService(),
            eventService: FirebaseEventService(),
            mediaService: FirebaseStorageMediaService(),
            messagingService: FirebaseMessagingService(),
            aiInsightsAvailabilityService: BackendAIInsightsAvailabilityService(),
            aiInsightsService: BackendAIInsightsService(authService: authService),
            crashReporter: FirebaseCrashlyticsReporter(),
            runtimeMode: .live
        )
    }()

    static func runtimeModeForCurrentProcess(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        runningUnderTests: Bool? = nil
    ) -> AppRuntimeMode {
        let isRunningTests = runningUnderTests ?? isRunningUnderTests(environment: environment)

        if environment["LOVESAVING_MODE"] == "LIVE" {
            return .live
        }

        if environment["LOVESAVING_MODE"] == "UI_TEST" {
            let scenario = UITestScenario(rawValue: environment["LOVESAVING_SCENARIO"] ?? "") ?? .linked
            return .uiTest(scenario)
        }

        if isRunningTests {
            return .uiTest(.linked)
        }

        return .live
    }

    static func make(runtimeMode: AppRuntimeMode) -> AppContainer {
        switch runtimeMode {
        case .live:
            return .live
        case .uiTest(let scenario):
            return .uiTest(scenario: scenario)
        }
    }

    static func forCurrentProcess() -> AppContainer {
        make(runtimeMode: runtimeModeForCurrentProcess())
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
            aiInsightsAvailabilityService: UITestAIInsightsAvailabilityService(),
            aiInsightsService: UITestAIInsightsService(),
            crashReporter: NoopCrashlyticsReporter(),
            runtimeMode: .uiTest(scenario)
        )
    }

    private static func isRunningUnderTests(environment: [String: String]) -> Bool {
        if environment["XCTestConfigurationFilePath"] != nil {
            return true
        }
        if environment["XCTestBundlePath"] != nil {
            return true
        }
        return NSClassFromString("XCTestCase") != nil
    }
}

extension AppRuntimeMode {
    var crashlyticsValue: String {
        switch self {
        case .live:
            return "live"
        case .uiTest(let scenario):
            return "ui_test.\(scenario.rawValue)"
        }
    }
}
