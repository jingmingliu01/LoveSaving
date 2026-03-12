import Foundation
import FirebaseCrashlytics

protocol CrashlyticsReporting {
    func setUserID(_ userID: String)
    func setCustomValue(_ value: Any, forKey key: String)
    func log(_ message: String)
    func record(error: Error)
}

struct FirebaseCrashlyticsReporter: CrashlyticsReporting {
    func setUserID(_ userID: String) {
        Crashlytics.crashlytics().setUserID(userID)
    }

    func setCustomValue(_ value: Any, forKey key: String) {
        Crashlytics.crashlytics().setCustomValue(value, forKey: key)
    }

    func log(_ message: String) {
        Crashlytics.crashlytics().log(message)
    }

    func record(error: Error) {
        Crashlytics.crashlytics().record(error: error)
    }
}

struct NoopCrashlyticsReporter: CrashlyticsReporting {
    func setUserID(_ userID: String) {}

    func setCustomValue(_ value: Any, forKey key: String) {}

    func log(_ message: String) {}

    func record(error: Error) {}
}
