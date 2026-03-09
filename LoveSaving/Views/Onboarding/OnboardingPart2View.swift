import SwiftUI

enum OnboardingPart2Step: Equatable {
    case revealHome
    case focusHeart
    case submitDraft
    case completion
}

enum OnboardingTutorialTarget: Hashable {
    case tapButton
    case balanceValue
    case submit
}

struct TutorialTargetPreferenceKey: PreferenceKey {
    static var defaultValue: [OnboardingTutorialTarget: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [OnboardingTutorialTarget: Anchor<CGRect>],
        nextValue: () -> [OnboardingTutorialTarget: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func tutorialTarget(_ target: OnboardingTutorialTarget) -> some View {
        anchorPreference(key: TutorialTargetPreferenceKey.self, value: .bounds) {
            [target: $0]
        }
    }
}

struct TutorialHighlightCutout: Identifiable {
    let id: OnboardingTutorialTarget
    let rect: CGRect
    let cornerRadius: CGFloat
}

struct OnboardingPart2View: View {
    let onFinish: () -> Void

    @StateObject private var homeViewModel = HomeViewModel(runtimeMode: .tutorial)
    @State private var step: OnboardingPart2Step = .revealHome
    @State private var revealOverlayOpacity = 1.0
    @State private var transitionToken = UUID()

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            NavigationStack {
                HomeView(viewModel: homeViewModel, tutorialStep: step)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlayPreferenceValue(TutorialTargetPreferenceKey.self) { anchors in
            GeometryReader { proxy in
                TutorialOverlayView(
                    step: step,
                    targetFrames: resolvedFrames(from: anchors, in: proxy),
                    size: proxy.size
                )
                .background(Color.clear)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }
        }
        .overlay {
            Color.white
                .opacity(revealOverlayOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .task {
            await startTutorial()
        }
        .onChange(of: homeViewModel.showComposer) { _, showComposer in
            guard showComposer, step == .focusHeart else { return }
            transition(to: .submitDraft)
        }
        .onChange(of: homeViewModel.didTutorialSubmit) { _, didSubmit in
            guard didSubmit, step == .submitDraft else { return }
            homeViewModel.consumeTutorialSubmitFlag()
            transition(to: .completion)
        }
        .onChange(of: step) { _, newStep in
            switch newStep {
            case .completion:
                let token = refreshTransitionToken()
                Task {
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    guard !Task.isCancelled, token == transitionToken else { return }
                    onFinish()
                }
            default:
                break
            }
        }
    }

    @MainActor
    private func startTutorial() async {
        let token = refreshTransitionToken()
        withAnimation(.easeOut(duration: 0.25)) {
            revealOverlayOpacity = 0
        }
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard !Task.isCancelled, token == transitionToken else { return }
        transition(to: .focusHeart)
    }

    private func transition(to nextStep: OnboardingPart2Step) {
        refreshTransitionToken()
        withAnimation(.easeInOut(duration: 0.22)) {
            step = nextStep
        }
    }

    private func scheduleTransition(to nextStep: OnboardingPart2Step, after nanoseconds: UInt64) {
        let token = refreshTransitionToken()
        Task {
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled, token == transitionToken else { return }
            transition(to: nextStep)
        }
    }

    @discardableResult
    private func refreshTransitionToken() -> UUID {
        let token = UUID()
        transitionToken = token
        return token
    }

    private func resolvedFrames(
        from anchors: [OnboardingTutorialTarget: Anchor<CGRect>],
        in proxy: GeometryProxy
    ) -> [OnboardingTutorialTarget: CGRect] {
        anchors.mapValues { proxy[$0] }
    }
}

struct TutorialOverlayView: View {
    let step: OnboardingPart2Step
    let targetFrames: [OnboardingTutorialTarget: CGRect]
    let size: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            if shouldShowScrim {
                Rectangle()
                    .fill(Color.black.opacity(0.5))
                    .ignoresSafeArea()
                    .overlay {
                        ZStack {
                            ForEach(cutoutRects) { cutout in
                                RoundedRectangle(cornerRadius: cutout.cornerRadius, style: .continuous)
                                    .frame(width: cutout.rect.width, height: cutout.rect.height)
                                    .position(x: cutout.rect.midX, y: cutout.rect.midY)
                                    .blendMode(.destinationOut)
                            }
                        }
                    }
                    .compositingGroup()

                ForEach(cutoutRects) { cutout in
                    RoundedRectangle(cornerRadius: cutout.cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        .frame(width: cutout.rect.width, height: cutout.rect.height)
                        .position(x: cutout.rect.midX, y: cutout.rect.midY)
                }
            }

            if let copy = overlayCopy {
                VStack(alignment: .leading, spacing: 6) {
                    Text(copy.title)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    if let subtitle = copy.subtitle {
                        Text(subtitle)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityIdentifier(overlayCopyIdentifier)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: copyAlignment)
                .padding(copyEdgeInsets)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: step)
    }

    private var shouldShowScrim: Bool {
        step != .revealHome && step != .completion
    }

    private var cutoutRects: [TutorialHighlightCutout] {
        activeTargets.compactMap { target -> TutorialHighlightCutout? in
            guard let frame = targetFrames[target] else { return nil }
            return cutout(for: target, frame: frame)
        }
    }

    private var activeTargets: [OnboardingTutorialTarget] {
        switch step {
        case .focusHeart:
            return [.balanceValue, .tapButton]
        case .submitDraft:
            return [.submit]
        default:
            return []
        }
    }

    private func cutout(for target: OnboardingTutorialTarget, frame: CGRect) -> TutorialHighlightCutout {
        switch target {
        case .tapButton:
            return TutorialHighlightCutout(id: target, rect: frame, cornerRadius: 18)
        case .balanceValue:
            return TutorialHighlightCutout(id: target, rect: frame, cornerRadius: 18)
        case .submit:
            return TutorialHighlightCutout(id: target, rect: frame.insetBy(dx: -14, dy: -10), cornerRadius: 18)
        }
    }

    private var overlayCopy: (title: String, subtitle: String?)? {
        switch step {
        case .revealHome:
            return nil
        case .focusHeart:
            return ("Tap the heart a few times.", nil)
        case .submitDraft:
            return ("Submit to save the moment.", nil)
        case .completion:
            return nil
        }
    }

    private var overlayCopyIdentifier: String {
        switch step {
        case .focusHeart:
            return "onboarding.part2.copy.focusHeart"
        case .submitDraft:
            return "onboarding.part2.copy.submit"
        case .revealHome, .completion:
            return "onboarding.part2.copy.none"
        }
    }

    private var copyAlignment: Alignment {
        switch step {
        case .focusHeart:
            return .bottom
        case .submitDraft:
            return .top
        default:
            return .top
        }
    }

    private var copyEdgeInsets: EdgeInsets {
        switch step {
        case .focusHeart:
            return EdgeInsets(top: 0, leading: 0, bottom: 112, trailing: 0)
        case .submitDraft:
            return EdgeInsets(top: 118, leading: 0, bottom: 0, trailing: 0)
        default:
            return EdgeInsets()
        }
    }
}
