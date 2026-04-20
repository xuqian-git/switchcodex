import AppKit
import SwiftUI

@MainActor
final class MenuBarPanelViewModel: ObservableObject {
    @Published var accounts: [CodexAccount] = []
    @Published var isRefreshing = false

    private let accountService: CodexAccountServicing
    private var hasLoaded = false

    init(accountService: CodexAccountServicing) {
        self.accountService = accountService
    }

    static func live() -> MenuBarPanelViewModel {
        let fileStore = FileStore()
        let backupService = BackupService(fileStore: fileStore)
        let mutationCoordinator = DirectoryMutationCoordinator()
        let accountService = CodexAccountService(
            fileStore: fileStore,
            backupService: backupService,
            mutationCoordinator: mutationCoordinator
        )
        return MenuBarPanelViewModel(accountService: accountService)
    }

    func load(forceRefresh: Bool = false) async {
        guard !isRefreshing else { return }
        if hasLoaded && !forceRefresh { return }

        isRefreshing = true
        defer {
            isRefreshing = false
            hasLoaded = true
        }

        do {
            accounts = try await accountService.listAccounts()
            let missingQuotaIDs = accounts
                .filter { $0.authMode != .apikey && $0.quota == nil && $0.quotaError == nil }
                .map(\.id)

            if !missingQuotaIDs.isEmpty {
                for accountID in missingQuotaIDs {
                    _ = try await accountService.refreshAccount(id: accountID)
                }
                accounts = try await accountService.listAccounts()
            }
        } catch {
            accounts = []
        }
    }

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            hasLoaded = true
        }

        do {
            _ = try await accountService.refreshAllAccounts()
            accounts = try await accountService.listAccounts()
        } catch {
            accounts = (try? await accountService.listAccounts()) ?? []
        }
    }

    func switchAccount(_ account: CodexAccount) async {
        do {
            _ = try await accountService.switchAccount(id: account.id)
        } catch {
            return
        }
        await load(forceRefresh: true)
    }
}

struct MenuBarPanelView: View {
    @ObservedObject var rootViewModel: RootViewModel
    @Environment(\.openWindow) private var openWindow
    @StateObject private var viewModel: MenuBarPanelViewModel

    init(rootViewModel: RootViewModel) {
        self.rootViewModel = rootViewModel
        _viewModel = StateObject(wrappedValue: MenuBarPanelViewModel.live())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            header
            Divider()
            accountsSection
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.bottom, AppSpacing.lg)
        .padding(.top, AppSpacing.xl)
        .frame(width: 380, height: 580)
        .task {
            await viewModel.load()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SwichCodex")
                    .font(.system(size: 15, weight: .semibold))
                if let current = viewModel.accounts.first(where: { $0.isCurrent }) {
                    Text("当前账号：\(current.resolvedDisplayName)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if viewModel.isRefreshing {
                    Text("正在读取账号与配额…")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text("暂无账号")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                rootViewModel.selection = .accounts
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            } label: {
                Text("主界面")
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("退出")
            }
            .buttonStyle(.bordered)

            Button {
                Task {
                    await viewModel.refreshAll()
                    await rootViewModel.accountsViewModel.load()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isRefreshing)
            .help("刷新账号和配额")
        }
    }

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("账号与配额")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            if viewModel.accounts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.isRefreshing ? "正在加载…" : "暂无账号")
                        .font(.system(size: 12, weight: .medium))
                    Text("菜单栏面板会直接读取本地 Codex 账号，并在需要时自动刷新配额。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, AppSpacing.sm)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        ForEach(viewModel.accounts) { account in
                            accountRow(account)
                        }
                    }
                }
                .frame(minHeight: 480, maxHeight: 480)
            }
        }
    }

    private func accountRow(_ account: CodexAccount) -> some View {
        let presentation = CodexAccountPresentation.make(for: account, hideEmail: true)

        return VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: AppSpacing.xs) {
                        Text(account.resolvedDisplayName)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        if account.isCurrent {
                            AppStatusBadge(text: "当前", color: .accentColor)
                        }
                    }
                    Text(Masking.maskEmail(account.email))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button(account.isCurrent ? "已切换" : "切换") {
                    Task {
                        await viewModel.switchAccount(account)
                        await rootViewModel.accountsViewModel.load()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(account.isCurrent || viewModel.isRefreshing)
            }

            if let quotaError = presentation.quotaErrorLine {
                Label(quotaError, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppSemanticColor.warning)
                    .lineLimit(2)
            } else if account.authMode == .apikey {
                Text("API Key 账号不展示 ChatGPT 配额")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else if presentation.quotaItems.isEmpty {
                Text("暂无配额数据")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: AppSpacing.sm) {
                    ForEach(Array(presentation.quotaItems.prefix(2))) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.label)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(item.valueText)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(quotaColor(item.tone))
                            if let resetText = item.resetText {
                                Text(resetText)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, 8)
                        .background(AppSemanticColor.mutedFill)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(account.isCurrent ? Color.accentColor.opacity(0.08) : AppSemanticColor.mutedFill.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func quotaColor(_ tone: CodexQuotaTone) -> Color {
        switch tone {
        case .high:
            return AppSemanticColor.success
        case .medium:
            return Color.blue
        case .low:
            return AppSemanticColor.warning
        case .critical:
            return AppSemanticColor.danger
        }
    }
}
