import Foundation

enum AppDateFormatting {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter
    }()

    static func display(_ date: Date?) -> String {
        guard let date else { return "未知" }
        return formatter.string(from: date)
    }
}
