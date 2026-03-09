import SwiftUI

private struct PreviewShell<Content: View>: View {
    @StateObject private var session: AppSession
    @StateObject private var locationManager: LocationManager
    private let content: Content

    init(
        scenario: UITestScenario = .linked,
        @ViewBuilder content: () -> Content
    ) {
        let container = AppContainer.uiTest(scenario: scenario)
        let previewLocationManager = LocationManager(isUITestMode: true)
        previewLocationManager.setMockLocationForUITests()
        _session = StateObject(wrappedValue: AppSession(container: container))
        _locationManager = StateObject(wrappedValue: previewLocationManager)
        self.content = content()
    }

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .ignoresSafeArea()
        .environmentObject(session)
        .environmentObject(locationManager)
    }
}

private struct FixedDevicePreview<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(width: 393, height: 852)
            .clipped()
    }
}

private struct TutorialHomePreview: View {
    let step: OnboardingPart2Step
    @StateObject private var viewModel = HomeViewModel(runtimeMode: .tutorial)

    var body: some View {
        HomeView(viewModel: viewModel, tutorialStep: step)
            .task {
                guard step == .submitDraft else { return }
                if viewModel.tapCount == 0 {
                    for _ in 0..<3 {
                        viewModel.registerTap()
                    }
                }
                viewModel.showComposer = true
            }
    }
}

#Preview("Onboarding Part 1", traits: .fixedLayout(width: 393, height: 852)) {
    FixedDevicePreview {
        OnboardingFireIntroView { }
    }
}

#Preview("Onboarding Part 2 Flow", traits: .fixedLayout(width: 393, height: 852)) {
    PreviewShell {
        OnboardingPart2View { }
    }
}

#Preview("Onboarding Part 2 Submit", traits: .fixedLayout(width: 393, height: 852)) {
    PreviewShell {
        TutorialHomePreview(step: .submitDraft)
    }
}
