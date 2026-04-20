import Foundation

struct CodexGroupService: CodexGroupServicing, @unchecked Sendable {
    private let fileStore: FileStore

    init(fileStore: FileStore) {
        self.fileStore = fileStore
    }

    func listGroups() async throws -> [AccountGroup] {
        try AppPaths.ensureBaseDirectories()
        return ((try? fileStore.readJSON([AccountGroup].self, at: AppPaths.groupsURL)) ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    func createGroup(name: String) async throws {
        var groups = try await listGroups()
        let nextOrder = (groups.map(\.sortOrder).max() ?? 0) + 1
        groups.append(AccountGroup(id: UUID().uuidString, name: name, sortOrder: nextOrder, accountIDs: [], createdAt: Date()))
        try fileStore.writeJSON(groups, to: AppPaths.groupsURL)
    }

    func assign(accountID: String, to groupID: String?) async throws {
        var groups = try await listGroups()
        for index in groups.indices {
            groups[index].accountIDs.removeAll { $0 == accountID }
            if groups[index].id == groupID {
                groups[index].accountIDs.append(accountID)
            }
        }
        try fileStore.writeJSON(groups, to: AppPaths.groupsURL)
    }
}
