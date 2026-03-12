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
                    .onAppear {
                        session.updateCrashlyticsRoute("entry.loading")
                    }
            case .part1:
                OnboardingFireIntroView {
                    onboardingFlow.startPart2()
                }
                .onAppear {
                    session.updateCrashlyticsRoute("entry.onboarding.part1")
                }
            case .part2:
                OnboardingPart2View {
                    Task {
                        await onboardingFlow.completeTutorial(using: session)
                    }
                }
                .onAppear {
                    session.updateCrashlyticsRoute("entry.onboarding.part2")
                }
            case .app:
                RootView()
                    .onAppear {
                        session.updateCrashlyticsRoute("entry.app")
                    }
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
