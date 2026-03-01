import Foundation

public struct TapBurstState: Sendable, Equatable {
    public private(set) var count: Int = 0
    public private(set) var lastTapAt: Date?

    public init() {}

    public mutating func registerTap(at date: Date) {
        count += 1
        lastTapAt = date
    }

    public mutating func reset() {
        count = 0
        lastTapAt = nil
    }
}
