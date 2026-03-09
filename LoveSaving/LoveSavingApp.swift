import FirebaseCore
import SwiftUI

@main
struct LoveSavingApp: App {
    @State private var hasCompletedOnboarding = false
    @StateObject private var session: AppSession
    @StateObject private var locationManager: LocationManager
    private let container: AppContainer

    init() {
        let runtimeMode = AppContainer.runtimeModeForCurrentProcess()
        if case .live = runtimeMode, FirebaseApp.app() == nil {
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
            Group {
                if hasCompletedOnboarding {
                    RootView()
                } else {
                    OnboardingFireIntroView {
                        hasCompletedOnboarding = true
                    }
                }
            }
                .environmentObject(session)
                .environmentObject(locationManager)
                .task {
                    guard hasCompletedOnboarding else { return }
                    guard !container.isUITestMode else { return }
                    locationManager.requestAuthorizationIfNeeded()
                    await session.requestNotifications(suppressErrors: true)
                }
        }
    }
}
