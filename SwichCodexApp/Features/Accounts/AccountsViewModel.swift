import Foundation

@MainActor
final class AccountsViewModel: ObservableObject {
    enum GroupFilter: String, CaseIterable, Identifiable {
        case all
        case ungrouped

        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "全部账号"
            case .ungrouped: "未分组"
            }
        }
    }

    @Published var accounts: [CodexAccount] = []
    @Published var groups: [AccountGroup] = []
    @Published var selectedAccountID: String?
    @Published var searchText = ""
    @Published var hideEmail = true
    @Published var isGrid = true
    @Published var feedback: OperationFeedback?
    @Published var isPresentingAddSheet = false
    @Published var selectedGroupID: String?
    @Published var isBatchMode = false
    @Published var selectedAccountIDs: Set<String> = []

    private let accountService: CodexAccountServicing
    private let groupService: CodexGroupServicing
    private var isRefreshingMissingQuota = false
    private var feedbackDismissTask: Task<Void, Never>?
    private var autoRefreshTask: Task<Void, Never>?

    init(accountService: CodexAccountServicing, groupService: CodexGroupServicing) {
        self.accountService = accountService
        self.groupService = groupService
    }

    var filteredAccounts: [CodexAccount] {
        accounts.filter { account in
            let matchesSearch = searchText.isEmpty
                || account.resolvedDisplayName.localizedCaseInsensitiveContains(searchText)
                || account.email.localizedCaseInsensitiveContains(searchText)
                || (account.teamName?.localizedCaseInsensitiveContains(searchText) == true)
                || (account.accountName?.localizedCaseInsensitiveContains(searchText) == true)
                || (account.accountStructure?.localizedCaseInsensitiveContains(searchText) == true)
                || account.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
            return matchesSearch
        }
    }

    func load() async {
        do {
            try await reloadData()
        } catch {
            showFeedback(OperationFeedback(level: .error, message: error.localizedDescription))
        }
    }

    func startAutoRefresh() {
        guard autoRefreshTask == nil else { return }
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { break }
                await self?.performAutoRefresh()
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    func addLocalAccount() async {
        do {
            let account = try await accountService.importFromLocalAuth()
            showFeedback(OperationFeedback(level: .success, message: "已导入 \(account.resolvedDisplayName)。"))
            await load()
        } catch {
            showFeedback(OperationFeedback(level: .error, message: error.localizedDescription))
        }
    }

    func addTokens(idToken: String, accessToken: String, refreshToken: String?) async {
        do {
            _ = try await accountService.importFromTokens(idToken: idToken, accessToken: accessToken, refreshToken: refreshToken)
            showFeedback(OperationFeedback(level: .success, message: "Token 账号已添加。"))
            await load()
        } catch {
            showFeedback(OperationFeedback(level: .error, message: error.localizedDescription))
        }
    }

    func addAPIKey(_ apiKey: String, baseURL: String?) async {
        do {
            _ = try await accountService.importFromAPIKey(apiKey: apiKey, baseURL: baseURL)
            showFeedback(OperationFeedback(level: .success, message: "API Key 账号已添加。"))
            await load()
        } catch {
            showFeedback(OperationFeedback(level: .error, message: error.localizedDescription))
        }
    }

    func switchAccount(_ account: CodexAccount) async {
        do {
            showFeedback(try await accountService.switchAccount(id: account.id))
            await load()
        } catch {
            showFeedback(OperationFeedback(level: .error, message: error.localizedDescription))
        }
    }

    func refreshAccount(_ account: CodexAccount) async {
        do {
            _ = try await accountService.refreshAccount(id: account.id)
            showFeedback(OperationFeedback(level: .success, message: "账号已刷新。"))
            await load()
        } catch {
            showFeedback(OperationFeedback(level: .error, message: error.localizedDescription))
        }
    }

    func refreshAll() async {
        do {
            _ = try await accountService.refreshAllAccounts()
            showFeedback(OperationFeedback(level: .success, message: "全部账号已刷新。"))
            await load()
        } catch {
            showFeedback(OperationFeedback(level: .error, message: error.localizedDescription))
        }
    }

    var selectedAccount: CodexAccount? {
        accounts.first(where: { $0.id == selectedAccountID })
    }

    var selectedAccountsCount: Int {
        selectedAccountIDs.count
    }

    func toggleBatchMode() {
        isBatchMode.toggle()
        if !isBatchMode {
            selectedAccountIDs.removeAll()
        }
    }

    func toggleAccountSelection(_ accountID: String) {
        if selectedAccountIDs.contains(accountID) {
            selectedAccountIDs.remove(accountID)
        } else {
            selectedAccountIDs.insert(accountID)
        }
    }

    func selectAllFilteredAccounts() {
        selectedAccountIDs = Set(filteredAccounts.map(\.id))
    }

    func clearSelection() {
        selectedAccountIDs.removeAll()
    }

    func importAccounts(from url: URL) async {
        do {
            let count = try await accountService.importAccounts(from: url)
            showFeedback(OperationFeedback(level: .success, message: "已导入 \(count) 个账号。"))
            await load()
        } catch {
            showFeedback(OperationFeedback(level: .error, message: error.localizedDescription))
        }
    }

    func exportSelectedAccounts(to url: URL) async {
        do {
            try await accountService.exportAccounts(ids: Array(selectedAccountIDs), to: url)
            showFeedback(OperationFeedback(level: .success, message: "已导出 \(selectedAccountIDs.count) 个账号。"))
        } catch {
            showFeedback(OperationFeedback(level: .error, message: error.localizedDescription))
        }
    }

    func deleteAccount(_ account: CodexAccount) async {
        await deleteAccounts(ids: [account.id])
    }

    func deleteSelectedAccounts() async {
        await deleteAccounts(ids: Array(selectedAccountIDs))
    }

    private func deleteAccounts(ids: [String]) async {
        do {
            let deletedCount = try await accountService.deleteAccounts(ids: ids)
            selectedAccountIDs.subtract(ids)
            showFeedback(OperationFeedback(level: .success, message: "已删除 \(deletedCount) 个账号。"))
            await load()
        } catch {
            showFeedback(OperationFeedback(level: .error, message: error.localizedDescription))
        }
    }

    private func refreshMissingQuotaIfNeeded() {
        guard !isRefreshingMissingQuota else { return }

        let pendingAccountIDs = accounts
            .filter { account in
                account.authMode != .apikey
                    && account.quota == nil
                    && account.quotaError == nil
            }
            .map(\.id)

        guard !pendingAccountIDs.isEmpty else { return }
        isRefreshingMissingQuota = true

        Task {
            defer { isRefreshingMissingQuota = false }
            do {
                for accountID in pendingAccountIDs {
                    _ = try await accountService.refreshAccount(id: accountID)
                }
                let refreshedAccounts = try await accountService.listAccounts()
                accounts = refreshedAccounts
                if selectedAccountID == nil || !refreshedAccounts.contains(where: { $0.id == selectedAccountID }) {
                    selectedAccountID = refreshedAccounts.first?.id
                }
            } catch {
                showFeedback(OperationFeedback(level: .error, message: error.localizedDescription))
            }
        }
    }

    private func reloadData() async throws {
        async let loadedAccounts = accountService.listAccounts()
        async let loadedGroups = groupService.listGroups()
        accounts = try await loadedAccounts
        groups = try await loadedGroups
        selectedAccountID = selectedAccountID ?? accounts.first?.id
        selectedAccountIDs.formIntersection(Set(accounts.map(\.id)))
        refreshMissingQuotaIfNeeded()
    }

    private func performAutoRefresh() async {
        do {
            _ = try await accountService.refreshAllAccounts()
            try await reloadData()
        } catch {
            AppLogger.error("Automatic account refresh failed: \(error.localizedDescription)")
        }
    }

    private func showFeedback(_ value: OperationFeedback) {
        feedbackDismissTask?.cancel()
        feedback = value
        feedbackDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, feedback?.id == value.id else { return }
            feedback = nil
        }
    }
}
