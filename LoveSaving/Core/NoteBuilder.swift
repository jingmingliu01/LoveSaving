import Foundation

public enum AppDisplayTime {
    public static func estDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

public enum NoteBuilder {
    public static func defaultNote(occurredAt: Date, addressText: String?) -> String {
        let dateText = AppDisplayTime.estDateTime(occurredAt)
        let address = addressText?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let address, !address.isEmpty {
            return "\(dateText) at \(address)"
        }

        return "\(dateText) at current location"
    }
}
