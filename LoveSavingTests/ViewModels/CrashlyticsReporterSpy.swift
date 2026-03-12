import Foundation
@testable import LoveSaving

final class CrashlyticsReporterSpy: CrashlyticsReporting {
    private(set) var userIDs: [String] = []
    private(set) var customValues: [String: Any] = [:]
    private(set) var logs: [String] = []
    private(set) var recordedErrorTypes: [String] = []

    func setUserID(_ userID: String) {
        userIDs.append(userID)
    }

    func setCustomValue(_ value: Any, forKey key: String) {
        customValues[key] = value
    }

    func log(_ message: String) {
        logs.append(message)
    }

    func record(error: Error) {
        recordedErrorTypes.append(String(reflecting: type(of: error)))
    }
}
