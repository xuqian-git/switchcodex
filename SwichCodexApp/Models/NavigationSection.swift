import Foundation

enum NavigationSection: String, CaseIterable, Identifiable {
    case accounts
    case instances
    case sessions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accounts: "账号"
        case .instances: "实例"
        case .sessions: "会话"
        }
    }

    var symbol: String {
        switch self {
        case .accounts: "person.2.crop.square.stack"
        case .instances: "square.grid.3x3.topleft.filled"
        case .sessions: "text.bubble"
        }
    }
}

