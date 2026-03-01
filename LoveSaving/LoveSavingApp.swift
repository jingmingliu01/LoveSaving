import FirebaseCore
import SwiftUI

@main
struct LoveSavingApp: App {
    @StateObject private var session: AppSession
    @StateObject private var locationManager: LocationManager
    private let container: AppContainer

    init() {
        let isUITestMode = ProcessInfo.processInfo.environment["LOVEBANK_MODE"] == "UI_TEST"
        if !isUITestMode, FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }

        let resolvedContainer = AppContainer.forCurrentProcess()
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
            RootView()
                .environmentObject(session)
                .environmentObject(locationManager)
                .task {
                    guard !container.isUITestMode else { return }
                    locationManager.requestAuthorizationIfNeeded()
                    await session.requestNotifications()
                }
        }
    }
}
