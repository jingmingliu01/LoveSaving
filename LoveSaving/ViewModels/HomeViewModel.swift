import Foundation
import Combine
import CoreLocation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var type: EventType = .deposit
    @Published private(set) var tapCount = 0
    @Published var note = ""
    @Published var showComposer = false
    @Published var selectedImageData: Data?
    @Published var selectedImageExtension = "jpg"

    private var debounceTask: Task<Void, Never>?
    private let debounceNanoseconds: UInt64 = 1_500_000_000

    deinit {
        debounceTask?.cancel()
    }

    func registerTap() {
        tapCount += 1
        scheduleComposer()
    }

    func resetBurst() {
        tapCount = 0
        note = ""
        selectedImageData = nil
        selectedImageExtension = "jpg"
        showComposer = false
        debounceTask?.cancel()
    }

    func submit(using session: AppSession, coordinate: (lat: Double, lng: Double)?, addressText: String?) async {
        let didSubmit = await session.submitTapBurst(
            tapCount: tapCount,
            type: type,
            note: note,
            imageData: selectedImageData,
            imageFileExtension: selectedImageExtension,
            coordinate: coordinate.map { .init(latitude: $0.lat, longitude: $0.lng) },
            addressText: addressText
        )
        if didSubmit {
            resetBurst()
        }
    }

    var predictedDelta: Int {
        LoveDeltaCalculator.signedDelta(forTapCount: max(1, tapCount), type: type)
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
