import SwiftUI

struct AppEntryView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var onboardingFlow = OnboardingFlowController()

    var body: some View {
        Group {
            switch onboardingFlow.route {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white.ignoresSafeArea())
            case .part1:
                OnboardingFireIntroView {
                    onboardingFlow.startPart2()
                }
            case .part2:
                OnboardingPart2View {
                    Task {
                        await onboardingFlow.completeTutorial(using: session)
                    }
                }
            case .app:
                RootView()
            }
        }
        .task {
            await onboardingFlow.refresh(using: session)
        }
        .onChange(of: session.hasResolvedInitialAuthState) { _, _ in
            Task { await onboardingFlow.refresh(using: session) }
        }
        .onChange(of: session.profile?.hasCompletedOnboarding) { _, _ in
            Task { await onboardingFlow.refresh(using: session) }
        }
        .onChange(of: session.isSignedIn) { _, _ in
            Task { await onboardingFlow.refresh(using: session) }
        }
    }
}
