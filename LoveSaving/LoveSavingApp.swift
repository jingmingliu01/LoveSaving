import FirebaseCore
import SwiftUI

private enum FirebaseLoggerMode: String {
    case none
    case firebase

    init(environment: [String: String]) {
        let value = environment["LOVESAVING_LOGGER"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        self = FirebaseLoggerMode(rawValue: value ?? "") ?? .none
    }
}

@main
struct LoveSavingApp: App {
    @StateObject private var session: AppSession
    @StateObject private var locationManager: LocationManager
    @State private var requestedPermissionsUserID: String?
    private let container: AppContainer

    init() {
        let environment = ProcessInfo.processInfo.environment
        let runtimeMode = AppContainer.runtimeModeForCurrentProcess()

        #if DEBUG
        let loggerMode = FirebaseLoggerMode(environment: environment)
        #else
        let loggerMode: FirebaseLoggerMode = .none
        #endif

        if case .live = runtimeMode, FirebaseApp.app() == nil {
            // Supported values for LOVESAVING_LOGGER: none, firebase.
            if loggerMode == .firebase {
                FirebaseConfiguration.shared.setLoggerLevel(.debug)
            }

            FirebaseApp.configure()
        }
        let resolvedContainer = AppContainer.make(runtimeMode: runtimeMode)
        self.container = resolvedContainer

        let resolvedLocationManager = LocationManager(isUITestMode: resolvedContainer.isUITestMode)
        if resolvedContainer.isUITestMode {
            resolvedLocationManager.setMockLocationForUITests()
        }

        _locationManager = StateObject(wrappedValue: resolvedLocationManager)
        _session = StateObject(wrappedValue: AppSession(container: resolvedContainer))
    }

    var body: some Scene {
        WindowGroup {
            AppEntryView()
                .environmentObject(session)
                .environmentObject(locationManager)
                .task {
                    await maybeRequestPostOnboardingPermissions()
                }
                .onChange(of: session.hasResolvedInitialAuthState) { _, _ in
                    Task { await maybeRequestPostOnboardingPermissions() }
                }
                .onChange(of: session.profile?.hasCompletedOnboarding) { _, _ in
                    Task { await maybeRequestPostOnboardingPermissions() }
                }
                .onChange(of: session.authUser?.uid) { _, _ in
                    Task { await maybeRequestPostOnboardingPermissions() }
                }
        }
    }

    @MainActor
    private func maybeRequestPostOnboardingPermissions() async {
        guard !container.isUITestMode else { return }
        guard session.hasResolvedInitialAuthState else { return }
        guard session.profile?.hasCompletedOnboarding == true else { return }
        guard let uid = session.authUser?.uid else { return }
        guard requestedPermissionsUserID != uid else { return }

        requestedPermissionsUserID = uid
        locationManager.requestAuthorizationIfNeeded()
        await session.requestNotifications(suppressErrors: true)
    }
}
