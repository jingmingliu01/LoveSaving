import Foundation

public enum LoveDeltaCalculator {
    /// Produces a bounded score in [1, 20].
    public static func unsignedDelta(forTapCount tapCount: Int) -> Int {
        let safeTapCount = max(1, tapCount)
        let x = Double(safeTapCount)
        let maxScore = 20.0
        let steepness = 0.25
        let midpoint = 10.0
        let raw = maxScore / (1.0 + exp(-steepness * (x - midpoint)))
        let rounded = Int(raw.rounded())
        return max(1, min(20, rounded))
    }

    public static func signedDelta(forTapCount tapCount: Int, type: EventType) -> Int {
        let value = unsignedDelta(forTapCount: tapCount)
        switch type {
        case .deposit:
            return value
        case .withdraw:
            return -value
        }
    }
}
