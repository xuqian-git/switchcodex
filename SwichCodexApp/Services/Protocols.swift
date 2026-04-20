import Foundation

protocol CodexAccountServicing: Sendable {
    func listAccounts() async throws -> [CodexAccount]
    func importFromLocalAuth() async throws -> CodexAccount
    func importFromTokens(idToken: String, accessToken: String, refreshToken: String?) async throws -> CodexAccount
    func importFromAPIKey(apiKey: String, baseURL: String?) async throws -> CodexAccount
    func importAccounts(from url: URL) async throws -> Int
    func exportAccounts(ids: [String], to url: URL) async throws
    func switchAccount(id: String) async throws -> OperationFeedback
    func refreshAccount(id: String) async throws -> CodexAccount
    func refreshAllAccounts() async throws -> [CodexAccount]
    func deleteAccounts(ids: [String]) async throws -> Int
    func account(for id: String) async throws -> CodexAccount?
}

protocol CodexGroupServicing: Sendable {
    func listGroups() async throws -> [AccountGroup]
    func createGroup(name: String) async throws
    func assign(accountID: String, to groupID: String?) async throws
}

protocol CodexProcessServicing: Sendable {
    func resolveCodexApplicationURL() async throws -> URL
    func startInstance(at root: URL, isDefault: Bool, extraArgs: String) async throws -> Int32
    func stopInstance(pid: Int32?, root: URL, isDefault: Bool) async throws
    func focusInstance(pid: Int32?) async throws
    func isRunning(pid: Int32?, root: URL, isDefault: Bool) async -> Bool
}

protocol CodexInstanceServicing: Sendable {
    func listInstances() async throws -> [CodexInstance]
    func createInstance(name: String, directory: String, bindAccountID: String?) async throws
    func startInstance(id: String) async throws -> OperationFeedback
    func stopInstance(id: String) async throws -> OperationFeedback
    func deleteInstance(id: String) async throws -> OperationFeedback
    func focusInstance(id: String) async throws -> OperationFeedback
}

protocol CodexSessionServicing: Sendable {
    func listSessionsAcrossInstances() async throws -> [CodexSession]
    func loadTokenStats(for sessionIDs: [String]) async throws -> [String: TokenStats]
    func loadTokenStats(from locations: [SessionLocation]) async throws -> TokenStats?
    func moveToTrash(sessionIDs: [String]) async throws -> OperationFeedback
    func listTrash() async throws -> [TrashedSession]
    func restoreFromTrash(sessionIDs: [String]) async throws -> OperationFeedback
}

protocol AppUpdateServicing: Sendable {
    func currentVersion() -> String
    func checkForUpdates() async throws -> AppUpdateCheckResult
    func installUpdate(from release: AppReleaseInfo) async throws
}
