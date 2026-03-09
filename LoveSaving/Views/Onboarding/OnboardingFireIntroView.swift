import SwiftUI

struct OnboardingFireIntroView: View {
    let onFinish: () -> Void

    private let textFont = Font.system(size: 31, weight: .bold, design: .rounded)
    private let textLineHeight: CGFloat = 40
    private let textLineSpacing: CGFloat = 6

    @State private var phase: Phase = .firePast
    @State private var phaseRunToken = 0
    @State private var fullyRevealedLineCount = 0
    @State private var typingLineIndex: Int?
    @State private var revealedCharacterCount = 0
    @State private var showAnimation = false
    @State private var isAdvanceVisible = false

    private let isUITestMode = ProcessInfo.processInfo.environment["LOVEBANK_MODE"] == "UI_TEST"

    private struct DisplayLine: Identifiable {
        let id: Int
        let text: String
    }

    private enum Phase {
        case firePast
        case loveNow

        var lines: [String] {
            switch self {
            case .firePast:
                return [
                    "A long, long time ago,",
                    "we kept doing this,",
                    "making fire.",
                ]
            case .loveNow:
                return [
                    "Now,",
                    "we keep doing this,",
                    "making love.",
                ]
            }
        }

        var animationName: String {
            switch self {
            case .firePast:
                return "fire-idle"
            case .loveNow:
                return "phone-idle"
            }
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.white
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    copyBlock
                        .padding(.top, max(proxy.size.height * 0.235, 172))
                        .padding(.horizontal, 28)

                    Spacer(minLength: 24)

                    if showAnimation {
                        LottieLoopView(animationName: phase.animationName)
                            .frame(width: min(proxy.size.width * 0.5, 210))
                            .frame(height: min(proxy.size.height * 0.24, 215))
                            .frame(maxWidth: .infinity)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    } else {
                        Color.clear
                            .frame(height: min(proxy.size.height * 0.24, 215))
                    }

                    Spacer()
                }

                if isAdvanceVisible {
                    VStack {
                        Spacer()
                        HStack {
                            if phase == .loveNow {
                                Button(action: goBackToFirePhase) {
                                    Image(systemName: "arrow.left")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(.black)
                                        .frame(width: 56, height: 56)
                                        .background(.ultraThinMaterial, in: Circle())
                                        .overlay {
                                            Circle()
                                                .strokeBorder(Color.black.opacity(0.18), lineWidth: 1)
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("onboarding.back")
                            }

                            Spacer()

                            Button(action: advance) {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(.black)
                                    .frame(width: 56, height: 56)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .overlay {
                                        Circle()
                                            .strokeBorder(Color.black.opacity(0.18), lineWidth: 1)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("onboarding.next")
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 28)
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: showAnimation)
        .animation(.easeInOut(duration: 0.18), value: isAdvanceVisible)
        .animation(.easeInOut(duration: 0.3), value: fullyRevealedLineCount)
        .animation(.easeInOut(duration: 0.3), value: typingLineIndex)
        .task(id: phaseRunToken) {
            await playCurrentPhase()
        }
    }

    private var visibleLines: [DisplayLine] {
        var lines = Array(phase.lines.prefix(fullyRevealedLineCount).enumerated()).map { offset, text in
            DisplayLine(id: offset, text: text)
        }
        if let typingLineIndex, typingLineIndex < phase.lines.count {
            lines.append(
                DisplayLine(
                    id: typingLineIndex,
                    text: String(phase.lines[typingLineIndex].prefix(revealedCharacterCount))
                )
            )
        }
        return lines
    }

    private var characterStepNanos: UInt64 {
        isUITestMode ? 10_000_000 : 28_000_000
    }

    private var lineHoldNanos: UInt64 {
        isUITestMode ? 70_000_000 : 230_000_000
    }

    private var postRevealHoldNanos: UInt64 {
        isUITestMode ? 90_000_000 : 420_000_000
    }

    @ViewBuilder
    private var copyBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(visibleLines.enumerated()), id: \.element.id) { index, line in
                Text(line.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: textLineHeight, alignment: .leading)
                    .accessibilityIdentifier(index == visibleLines.count - 1 ? "onboarding.line.current" : "onboarding.line.previous")
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: (textLineHeight * 3) + (textLineSpacing * 2),
            alignment: .bottomLeading
        )
        .font(textFont)
        .lineSpacing(textLineSpacing)
        .foregroundStyle(.black)
        .multilineTextAlignment(.leading)
    }

    @MainActor
    private func playCurrentPhase() async {
        isAdvanceVisible = false
        showAnimation = false
        fullyRevealedLineCount = 0
        typingLineIndex = nil
        revealedCharacterCount = 0

        for index in phase.lines.indices {
            withAnimation(.easeInOut(duration: isUITestMode ? 0.05 : 0.28)) {
                typingLineIndex = index
            }
            revealedCharacterCount = 0

            if index == 1 {
                showAnimation = true
            }

            for count in 1...phase.lines[index].count {
                revealedCharacterCount = count
                try? await Task.sleep(nanoseconds: characterStepNanos)
                guard !Task.isCancelled else { return }
            }

            withAnimation(.easeInOut(duration: isUITestMode ? 0.05 : 0.28)) {
                fullyRevealedLineCount = index + 1
                typingLineIndex = nil
                revealedCharacterCount = 0
            }
            try? await Task.sleep(nanoseconds: lineHoldNanos)
            guard !Task.isCancelled else { return }
        }

        typingLineIndex = nil
        try? await Task.sleep(nanoseconds: postRevealHoldNanos)
        guard !Task.isCancelled else { return }
        isAdvanceVisible = true
    }

    private func advance() {
        switch phase {
        case .firePast:
            Task { await transitionToLovePhase() }
        case .loveNow:
            onFinish()
        }
    }

    private func goBackToFirePhase() {
        Task { await resetToFirePhase() }
    }

    @MainActor
    private func transitionToLovePhase() async {
        isAdvanceVisible = false
        showAnimation = false
        fullyRevealedLineCount = 0
        typingLineIndex = nil
        revealedCharacterCount = 0

        try? await Task.sleep(nanoseconds: isUITestMode ? 50_000_000 : 180_000_000)
        guard !Task.isCancelled else { return }

        phase = .loveNow
        phaseRunToken += 1
    }

    @MainActor
    private func resetToFirePhase() async {
        isAdvanceVisible = false
        showAnimation = false
        fullyRevealedLineCount = 0
        typingLineIndex = nil
        revealedCharacterCount = 0

        try? await Task.sleep(nanoseconds: isUITestMode ? 50_000_000 : 120_000_000)
        guard !Task.isCancelled else { return }

        phase = .firePast
        phaseRunToken += 1
    }
}
