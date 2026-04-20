import AppKit
import SwiftUI

struct MenuBarPanelView: View {
    @ObservedObject var rootViewModel: RootViewModel
    @Environment(\.openWindow) private var openWindow

    private var accountsViewModel: AccountsViewModel {
        rootViewModel.accountsViewModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            header
            Divider()
            accountsSection
            Divider()
            footerActions
        }
        .padding(AppSpacing.lg)
        .frame(width: 380)
        .task {
            await accountsViewModel.load()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SwichCodex")
                    .font(.system(size: 15, weight: .semibold))
                if let current = accountsViewModel.accounts.first(where: { $0.isCurrent }) {
                    Text("当前账号：\(current.resolvedDisplayName)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("暂无当前账号")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                Task { await accountsViewModel.refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .help("刷新账号和配额")
        }
    }

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("账号与配额")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            if accountsViewModel.accounts.isEmpty {
                Text("暂无账号")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, AppSpacing.sm)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        ForEach(accountsViewModel.accounts) { account in
                            accountRow(account)
                        }
                    }
                }
                .frame(maxHeight: 320)
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
                    Task { await accountsViewModel.switchAccount(account) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(account.isCurrent)
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

    private var footerActions: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Button {
                rootViewModel.selection = .accounts
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            } label: {
                Label("打开主面板", systemImage: "rectangle.on.rectangle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("退出软件", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
        }
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
