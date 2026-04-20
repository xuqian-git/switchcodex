import Foundation

struct OperationFeedback: Identifiable, Equatable {
    enum Level {
        case success
        case warning
        case error
    }

    let id = UUID()
    let level: Level
    let message: String
}

