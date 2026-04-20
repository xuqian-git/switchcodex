import Foundation

struct CodexSessionService: CodexSessionServicing, @unchecked Sendable {
    private let fileStore: FileStore
    private let backupService: BackupService
    private let mutationCoordinator: DirectoryMutationCoordinator
    private let instanceService: CodexInstanceServicing
    private let processService: CodexProcessServicing
    private let sqliteStore = SQLiteStore()

    init(
        fileStore: FileStore,
        backupService: BackupService,
        mutationCoordinator: DirectoryMutationCoordinator,
        instanceService: CodexInstanceServicing,
        processService: CodexProcessServicing
    ) {
        self.fileStore = fileStore
        self.backupService = backupService
        self.mutationCoordinator = mutationCoordinator
        self.instanceService = instanceService
        self.processService = processService
    }

    func listSessionsAcrossInstances() async throws -> [CodexSession] {
        var map: [String: CodexSession] = [:]
        for instance in try await instanceService.listInstances() {
            let root = URL(fileURLWithPath: instance.userDataDir)
            let dbURL = root.appendingPathComponent("state_5.sqlite")
            guard fileStore.fileExists(dbURL) else { continue }
            let rows = try sqliteStore.readThreads(at: dbURL)
            for row in rows {
                let location = SessionLocation(
                    instanceID: instance.id,
                    instanceName: instance.name,
                    running: instance.isRunning,
                    rolloutPath: row.rolloutPath,
                    instanceRoot: root.path
                )
                if var existing = map[row.id] {
                    existing.locations.append(location)
                    if existing.updatedAt == nil || (Date(timeIntervalSince1970: TimeInterval(row.updatedAt)) > existing.updatedAt ?? .distantPast) {
                        existing.updatedAt = Date(timeIntervalSince1970: TimeInterval(row.updatedAt))
                        existing.title = row.title
                    }
                    map[row.id] = existing
                } else {
                    map[row.id] = CodexSession(
                        id: row.id,
                        title: row.title,
                        cwd: row.cwd,
                        updatedAt: Date(timeIntervalSince1970: TimeInterval(row.updatedAt)),
                        locations: [location],
                        tokenStats: nil
                    )
                }
            }
        }
        return map.values.sorted {
            ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
        }
    }

    func loadTokenStats(for sessionIDs: [String]) async throws -> [String: TokenStats] {
        let sessions = try await listSessionsAcrossInstances()
        let targets = sessions.filter { sessionIDs.contains($0.id) }
        var result: [String: TokenStats] = [:]
        for session in targets {
            guard let path = session.locations.first?.rolloutPath else { continue }
            if let stats = readTokenStats(from: URL(fileURLWithPath: path)) {
                result[session.id] = stats
            }
        }
        return result
    }

    func loadTokenStats(from locations: [SessionLocation]) async throws -> TokenStats? {
        for location in locations {
            let url = URL(fileURLWithPath: location.rolloutPath)
            if let stats = readTokenStats(from: url) {
                return stats
            }
        }
        return nil
    }

    func moveToTrash(sessionIDs: [String]) async throws -> OperationFeedback {
        let sessions = try await listSessionsAcrossInstances().filter { sessionIDs.contains($0.id) }
        guard !sessions.isEmpty else {
            return OperationFeedback(level: .error, message: "没有可删除的会话。")
        }
        try AppPaths.ensureBaseDirectories()
        let warning = sessions.flatMap(\.locations).contains(where: \.running)
        for session in sessions {
            let trashID = UUID()
            let trashRoot = AppPaths.sessionTrashDirectory.appendingPathComponent(trashID.uuidString, isDirectory: true)
            try fileStore.createDirectory(trashRoot)
            var manifests: [TrashedSessionManifest] = []
            for location in session.locations {
                let instanceRoot = URL(fileURLWithPath: location.instanceRoot)
                let dbURL = instanceRoot.appendingPathComponent("state_5.sqlite")
                let indexURL = instanceRoot.appendingPathComponent("session_index.jsonl")
                _ = try backupService.backup(urls: [dbURL, indexURL], operation: "trash-session")
                let row = try sqliteStore.readThreads(at: dbURL).first(where: { $0.id == session.id })
                guard let row else { continue }
                let backup = TrashedSessionManifest.ThreadRowBackup(
                    id: row.id,
                    rolloutPath: row.rolloutPath,
                    createdAt: row.createdAt,
                    updatedAt: row.updatedAt,
                    source: row.source,
                    modelProvider: row.modelProvider,
                    cwd: row.cwd,
                    title: row.title,
                    sandboxPolicy: row.sandboxPolicy,
                    approvalMode: row.approvalMode,
                    tokensUsed: row.tokensUsed,
                    hasUserEvent: row.hasUserEvent,
                    archived: row.archived,
                    archivedAt: row.archivedAt,
                    gitSHA: row.gitSHA,
                    gitBranch: row.gitBranch,
                    gitOriginURL: row.gitOriginURL,
                    cliVersion: row.cliVersion,
                    firstUserMessage: row.firstUserMessage,
                    agentNickname: row.agentNickname,
                    agentRole: row.agentRole,
                    memoryMode: row.memoryMode,
                    model: row.model,
                    reasoningEffort: row.reasoningEffort,
                    agentPath: row.agentPath,
                    createdAtMS: row.createdAtMS,
                    updatedAtMS: row.updatedAtMS
                )
                let sessionIndexEntry = try readSessionIndexLine(for: session.id, at: indexURL)
                let rolloutSource = URL(fileURLWithPath: row.rolloutPath)
                let rolloutTrash = trashRoot.appendingPathComponent(rolloutSource.lastPathComponent)
                try mutationCoordinator.perform(directory: instanceRoot) {
                    if fileStore.fileExists(rolloutSource) {
                        try fileStore.moveItem(at: rolloutSource, to: rolloutTrash)
                    }
                    try sqliteStore.deleteThread(id: session.id, at: dbURL)
                    try rewriteSessionIndex(removing: session.id, at: indexURL)
                }
                manifests.append(TrashedSessionManifest(
                    instanceID: location.instanceID,
                    instanceName: location.instanceName,
                    instanceRoot: location.instanceRoot,
                    rolloutOriginalPath: row.rolloutPath,
                    rolloutTrashPath: rolloutTrash.path,
                    sessionIndexEntry: sessionIndexEntry,
                    threadRow: backup
                ))
            }
            let trashed = TrashedSession(id: trashID, sessionID: session.id, title: session.title, cwd: session.cwd, deletedAt: Date(), manifests: manifests)
            try fileStore.writeJSON(trashed, to: trashRoot.appendingPathComponent("manifest.json"))
        }
        let level: OperationFeedback.Level = warning ? .warning : .success
        let message = warning ? "会话已移入废纸篓；运行中的实例可能需要重启后才会反映变化。" : "会话已移入废纸篓。"
        return OperationFeedback(level: level, message: message)
    }

    func listTrash() async throws -> [TrashedSession] {
        try AppPaths.ensureBaseDirectories()
        let directories = (try? FileManager.default.contentsOfDirectory(at: AppPaths.sessionTrashDirectory, includingPropertiesForKeys: nil)) ?? []
        return try directories.compactMap { directory in
            let manifest = directory.appendingPathComponent("manifest.json")
            guard fileStore.fileExists(manifest) else { return nil }
            return try fileStore.readJSON(TrashedSession.self, at: manifest)
        }.sorted { $0.deletedAt > $1.deletedAt }
    }

    func restoreFromTrash(sessionIDs: [String]) async throws -> OperationFeedback {
        let trashItems = try await listTrash().filter { sessionIDs.contains($0.sessionID) }
        guard !trashItems.isEmpty else {
            return OperationFeedback(level: .error, message: "废纸篓中没有可恢复的会话。")
        }
        var warning = false
        for item in trashItems {
            for manifest in item.manifests {
                let instanceRoot = URL(fileURLWithPath: manifest.instanceRoot)
                let dbURL = instanceRoot.appendingPathComponent("state_5.sqlite")
                let indexURL = instanceRoot.appendingPathComponent("session_index.jsonl")
                _ = try backupService.backup(urls: [dbURL, indexURL], operation: "restore-session")
                if try sqliteStore.threadExists(id: item.sessionID, at: dbURL) {
                    return OperationFeedback(level: .error, message: "目标实例已存在同名会话，已阻止恢复。")
                }
                try mutationCoordinator.perform(directory: instanceRoot) {
                    try sqliteStore.insertThread(manifest.threadRow, at: dbURL)
                    let trashURL = URL(fileURLWithPath: manifest.rolloutTrashPath)
                    if fileStore.fileExists(trashURL) {
                        try fileStore.moveItem(at: trashURL, to: URL(fileURLWithPath: manifest.rolloutOriginalPath))
                    }
                    if let line = manifest.sessionIndexEntry {
                        try appendSessionIndexLine(line, at: indexURL)
                    }
                }
                let instanceRunning = await processService.isRunning(pid: nil, root: instanceRoot, isDefault: manifest.instanceID == "default")
                warning = warning || instanceRunning
            }
            try? fileStore.removeItem(at: AppPaths.sessionTrashDirectory.appendingPathComponent(item.id.uuidString))
        }
        return OperationFeedback(level: warning ? .warning : .success, message: warning ? "会话已恢复；运行中的实例可能需要重启后才会显示。" : "会话已恢复。")
    }

    private func readSessionIndexLine(for sessionID: String, at url: URL) throws -> String? {
        guard fileStore.fileExists(url) else { return nil }
        let lines = try fileStore.readString(at: url).split(separator: "\n").map(String.init)
        return lines.first { line in
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            return (json["id"] as? String) == sessionID
        }
    }

    private func rewriteSessionIndex(removing sessionID: String, at url: URL) throws {
        guard fileStore.fileExists(url) else { return }
        let filtered = try fileStore.readString(at: url)
            .split(separator: "\n")
            .map(String.init)
            .filter { line in
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return true }
                return (json["id"] as? String) != sessionID
            }
            .joined(separator: "\n")
        try fileStore.writeString(filtered.isEmpty ? "" : filtered + "\n", to: url)
    }

    private func appendSessionIndexLine(_ line: String, at url: URL) throws {
        let current = (try? fileStore.readString(at: url)) ?? ""
        let next = current + (current.hasSuffix("\n") || current.isEmpty ? "" : "\n") + line + "\n"
        try fileStore.writeString(next, to: url)
    }

    private func readTokenStats(from url: URL) -> TokenStats? {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let data = try? handle.readToEnd() else { return nil }
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n").reversed()
        for line in lines {
            guard line.contains("\"token_count\""), line.contains("\"total_token_usage\""),
                  let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  (json["type"] as? String) == "event_msg",
                  let payload = json["payload"] as? [String: Any],
                  (payload["type"] as? String) == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let usage = info["total_token_usage"] as? [String: Any] else { continue }
            let input = usage["input_tokens"] as? UInt64 ?? 0
            let output = usage["output_tokens"] as? UInt64 ?? 0
            let total = usage["total_tokens"] as? UInt64 ?? 0
            return TokenStats(inputTokens: input, outputTokens: output, totalTokens: total)
        }
        return nil
    }
}
