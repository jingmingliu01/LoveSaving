import Combine
import Foundation

@MainActor
final class OnboardingFlowController: ObservableObject {
    enum Route: Equatable {
        case loading
        case part1
        case part2
        case app
    }

    @Published private(set) var route: Route = .loading

    private var isSyncingRemoteCompletion = false
    private var hasCompletedOnboardingThisSession = false
    private let shouldBypassOnboardingForTests =
        ProcessInfo.processInfo.environment["LOVESAVING_SKIP_ONBOARDING"] == "1"

    func refresh(using session: AppSession) async {
        guard session.hasResolvedInitialAuthState else {
            route = .loading
            return
        }

        if shouldBypassOnboardingForTests {
            route = .app
            return
        }

        let remoteCompleted = session.profile?.hasCompletedOnboarding == true

        if remoteCompleted {
            route = .app
            return
        }

        if hasCompletedOnboardingThisSession {
            route = .app
            if session.isSignedIn {
                await syncRemoteCompletionIfNeeded(using: session)
            }
            return
        }

        switch route {
        case .part2:
            break
        case .loading, .app, .part1:
            route = .part1
        }
    }

    func startPart2() {
        route = .part2
    }

    func completeTutorial(using session: AppSession) async {
        hasCompletedOnboardingThisSession = true
        route = .app
        await syncRemoteCompletionIfNeeded(using: session)
    }

    private func syncRemoteCompletionIfNeeded(using session: AppSession) async {
        guard !isSyncingRemoteCompletion else { return }
        guard session.profile?.hasCompletedOnboarding != true else { return }
        guard session.isSignedIn else { return }

        isSyncingRemoteCompletion = true
        defer { isSyncingRemoteCompletion = false }

        _ = await session.markOnboardingCompleted()
    }
}
