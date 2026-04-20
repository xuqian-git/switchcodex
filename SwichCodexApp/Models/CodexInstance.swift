import Foundation

enum LaunchMode: String, Codable, Hashable {
    case app
}

struct CodexInstance: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var userDataDir: String
    var workingDir: String?
    var extraArgs: String
    var bindAccountID: String?
    var launchMode: LaunchMode
    var createdAt: Date
    var lastLaunchedAt: Date?
    var lastPID: Int32?
    var isDefault: Bool
    var followCurrentAccount: Bool
    var isRunning: Bool
    var isInitialized: Bool
}

struct InstanceStore: Codable {
    struct DefaultSettings: Codable {
        var bindAccountID: String?
        var extraArgs: String
        var lastPID: Int32?
        var followCurrentAccount: Bool
    }

    var defaultSettings: DefaultSettings
    var managedInstances: [CodexInstance]

    static let empty = InstanceStore(
        defaultSettings: .init(bindAccountID: nil, extraArgs: "", lastPID: nil, followCurrentAccount: true),
        managedInstances: []
    )
}

