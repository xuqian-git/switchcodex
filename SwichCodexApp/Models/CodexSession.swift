import Foundation

struct SessionLocation: Hashable, Codable {
    var instanceID: String
    var instanceName: String
    var running: Bool
    var rolloutPath: String
    var instanceRoot: String
}

struct TokenStats: Hashable, Codable {
    var inputTokens: UInt64
    var outputTokens: UInt64
    var totalTokens: UInt64
}

struct CodexSession: Identifiable, Hashable {
    var id: String
    var title: String
    var cwd: String
    var updatedAt: Date?
    var locations: [SessionLocation]
    var tokenStats: TokenStats?
}

struct TrashedSession: Identifiable, Codable, Hashable {
    var id: UUID
    var sessionID: String
    var title: String
    var cwd: String
    var deletedAt: Date
    var manifests: [TrashedSessionManifest]
}

struct TrashedSessionManifest: Codable, Hashable {
    struct ThreadRowBackup: Codable, Hashable {
        var id: String
        var rolloutPath: String
        var createdAt: Int64
        var updatedAt: Int64
        var source: String
        var modelProvider: String
        var cwd: String
        var title: String
        var sandboxPolicy: String
        var approvalMode: String
        var tokensUsed: Int64
        var hasUserEvent: Int64
        var archived: Int64
        var archivedAt: Int64?
        var gitSHA: String?
        var gitBranch: String?
        var gitOriginURL: String?
        var cliVersion: String?
        var firstUserMessage: String?
        var agentNickname: String?
        var agentRole: String?
        var memoryMode: String?
        var model: String?
        var reasoningEffort: String?
        var agentPath: String?
        var createdAtMS: Int64?
        var updatedAtMS: Int64?
    }

    var instanceID: String
    var instanceName: String
    var instanceRoot: String
    var rolloutOriginalPath: String
    var rolloutTrashPath: String
    var sessionIndexEntry: String?
    var threadRow: ThreadRowBackup
}

