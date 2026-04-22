import Foundation
import Combine

@MainActor
final class HomeViewModel: ObservableObject {
    enum RuntimeMode {
        case normal
        case tutorial
    }

    @Published var type: EventType = .deposit
    @Published private(set) var tapCount = 0
    @Published var note = ""
    @Published var showComposer = false
    @Published var selectedImageData: Data?
    @Published var selectedImageExtension = "jpg"
    @Published private(set) var didTutorialSubmit = false

    private var debounceTask: Task<Void, Never>?
    private let debounceNanoseconds: UInt64 = 1_500_000_000
    private let runtimeMode: RuntimeMode

    init(runtimeMode: RuntimeMode = .normal) {
        self.runtimeMode = runtimeMode
        if runtimeMode == .tutorial {
            self.type = .deposit
        }
    }

    deinit {
        debounceTask?.cancel()
    }

    var isTutorialMode: Bool {
        runtimeMode == .tutorial
    }

    func registerTap() {
        if isTutorialMode {
            type = .deposit
        }
        tapCount += 1
        scheduleComposer()
    }

    func resetBurst() {
        tapCount = 0
        note = ""
        selectedImageData = nil
        selectedImageExtension = "jpg"
        showComposer = false
        didTutorialSubmit = false
        debounceTask?.cancel()
    }

    func submit(using session: AppSession, location: EventLocation?) async {
        guard runtimeMode == .normal else {
            resetBurst()
            didTutorialSubmit = true
            return
        }

        let didSubmit = await session.submitTapBurst(
            tapCount: tapCount,
            type: type,
            note: note,
            imageData: selectedImageData,
            imageFileExtension: selectedImageExtension,
            location: location
        )
        if didSubmit {
            resetBurst()
        }
    }

    var predictedDelta: Int {
        LoveDeltaCalculator.signedDelta(forTapCount: max(1, tapCount), type: type)
    }

    func consumeTutorialSubmitFlag() {
        didTutorialSubmit = false
    }

    private func scheduleComposer() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard !Task.isCancelled, tapCount > 0 else { return }
            showComposer = true
        }
    }
}
