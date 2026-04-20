import Foundation

struct CodexInstanceService: CodexInstanceServicing, @unchecked Sendable {
    private let fileStore: FileStore
    private let backupService: BackupService
    private let mutationCoordinator: DirectoryMutationCoordinator
    private let accountService: CodexAccountServicing
    private let processService: CodexProcessServicing

    init(
        fileStore: FileStore,
        backupService: BackupService,
        mutationCoordinator: DirectoryMutationCoordinator,
        accountService: CodexAccountServicing,
        processService: CodexProcessServicing
    ) {
        self.fileStore = fileStore
        self.backupService = backupService
        self.mutationCoordinator = mutationCoordinator
        self.accountService = accountService
        self.processService = processService
    }

    func listInstances() async throws -> [CodexInstance] {
        try AppPaths.ensureBaseDirectories()
        let store = try loadStore()
        let currentAccount = try await accountService.listAccounts().first(where: \.isCurrent)
        let defaultRoot = AppPaths.codexHome
        let defaultBindID = store.defaultSettings.followCurrentAccount ? currentAccount?.id : store.defaultSettings.bindAccountID
        let defaultInstance = CodexInstance(
            id: "default",
            name: "默认实例",
            userDataDir: defaultRoot.path,
            workingDir: nil,
            extraArgs: store.defaultSettings.extraArgs,
            bindAccountID: defaultBindID,
            launchMode: .app,
            createdAt: Date.distantPast,
            lastLaunchedAt: nil,
            lastPID: store.defaultSettings.lastPID,
            isDefault: true,
            followCurrentAccount: store.defaultSettings.followCurrentAccount,
            isRunning: await processService.isRunning(pid: store.defaultSettings.lastPID, root: defaultRoot, isDefault: true),
            isInitialized: fileStore.fileExists(defaultRoot.appendingPathComponent("state_5.sqlite"))
        )
        var managed: [CodexInstance] = []
        for instance in store.managedInstances {
            var value = instance
            let root = URL(fileURLWithPath: value.userDataDir)
            value.isRunning = await processService.isRunning(pid: value.lastPID, root: root, isDefault: false)
            value.isInitialized = fileStore.fileExists(root.appendingPathComponent("state_5.sqlite"))
            managed.append(value)
        }
        return [defaultInstance] + managed.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func createInstance(name: String, directory: String, bindAccountID: String?) async throws {
        let normalized = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw NSError(domain: "SwichCodex", code: 400, userInfo: [NSLocalizedDescriptionKey: "实例目录不能为空。"])
        }
        var store = try loadStore()
        let root = URL(fileURLWithPath: normalized)
        try fileStore.createDirectory(root)
        store.managedInstances.append(CodexInstance(
            id: UUID().uuidString,
            name: name.isEmpty ? "新实例" : name,
            userDataDir: normalized,
            workingDir: nil,
            extraArgs: "",
            bindAccountID: bindAccountID,
            launchMode: .app,
            createdAt: Date(),
            lastLaunchedAt: nil,
            lastPID: nil,
            isDefault: false,
            followCurrentAccount: false,
            isRunning: false,
            isInitialized: false
        ))
        try saveStore(store)
    }

    func startInstance(id: String) async throws -> OperationFeedback {
        var store = try loadStore()
        if id == "default" {
            let root = AppPaths.codexHome
            let accountID = store.defaultSettings.followCurrentAccount
                ? try await accountService.listAccounts().first(where: \.isCurrent)?.id
                : store.defaultSettings.bindAccountID
            if let accountID {
                try await injectAccount(id: accountID, to: root)
            }
            let pid = try await processService.startInstance(at: root, isDefault: true, extraArgs: store.defaultSettings.extraArgs)
            store.defaultSettings.lastPID = pid
            try saveStore(store)
            return OperationFeedback(level: .success, message: "默认实例已启动。")
        }
        guard let index = store.managedInstances.firstIndex(where: { $0.id == id }) else {
            return OperationFeedback(level: .error, message: "实例不存在。")
        }
        let root = URL(fileURLWithPath: store.managedInstances[index].userDataDir)
        if let accountID = store.managedInstances[index].bindAccountID {
            try await injectAccount(id: accountID, to: root)
        }
        let pid = try await processService.startInstance(at: root, isDefault: false, extraArgs: store.managedInstances[index].extraArgs)
        store.managedInstances[index].lastPID = pid
        store.managedInstances[index].lastLaunchedAt = Date()
        try saveStore(store)
        return OperationFeedback(level: .success, message: "实例已启动。")
    }

    func stopInstance(id: String) async throws -> OperationFeedback {
        var store = try loadStore()
        if id == "default" {
            try await processService.stopInstance(pid: store.defaultSettings.lastPID, root: AppPaths.codexHome, isDefault: true)
            store.defaultSettings.lastPID = nil
            try saveStore(store)
            return OperationFeedback(level: .success, message: "默认实例已停止。")
        }
        guard let index = store.managedInstances.firstIndex(where: { $0.id == id }) else {
            return OperationFeedback(level: .error, message: "实例不存在。")
        }
        let root = URL(fileURLWithPath: store.managedInstances[index].userDataDir)
        try await processService.stopInstance(pid: store.managedInstances[index].lastPID, root: root, isDefault: false)
        store.managedInstances[index].lastPID = nil
        try saveStore(store)
        return OperationFeedback(level: .success, message: "实例已停止。")
    }

    func deleteInstance(id: String) async throws -> OperationFeedback {
        guard id != "default" else {
            return OperationFeedback(level: .error, message: "默认实例不能删除。")
        }

        var store = try loadStore()
        guard let index = store.managedInstances.firstIndex(where: { $0.id == id }) else {
            return OperationFeedback(level: .error, message: "实例不存在。")
        }

        let instance = store.managedInstances[index]
        let root = URL(fileURLWithPath: instance.userDataDir)
        let isRunning = await processService.isRunning(pid: instance.lastPID, root: root, isDefault: false)
        if isRunning {
            return OperationFeedback(level: .error, message: "请先停止实例，再执行删除。")
        }

        store.managedInstances.remove(at: index)
        try saveStore(store)
        return OperationFeedback(level: .success, message: "实例已从管理列表删除。")
    }

    func focusInstance(id: String) async throws -> OperationFeedback {
        let store = try loadStore()
        let pid: Int32?
        if id == "default" {
            pid = store.defaultSettings.lastPID
        } else {
            pid = store.managedInstances.first(where: { $0.id == id })?.lastPID
        }
        try await processService.focusInstance(pid: pid)
        return OperationFeedback(level: .success, message: "已尝试聚焦实例窗口。")
    }

    private func loadStore() throws -> InstanceStore {
        (try? fileStore.readJSON(InstanceStore.self, at: AppPaths.instancesURL)) ?? .empty
    }

    private func saveStore(_ store: InstanceStore) throws {
        try fileStore.writeJSON(store, to: AppPaths.instancesURL)
    }

    private func injectAccount(id: String, to root: URL) async throws {
        guard let account = try await accountService.account(for: id) else { return }
        _ = try backupService.backup(urls: [root.appendingPathComponent("auth.json")], operation: "inject-account")
        try mutationCoordinator.perform(directory: root) {
            try fileStore.writeString(account.rawAuthJSON, to: root.appendingPathComponent("auth.json"))
        }
    }
}
