import SwiftUI

struct RootView: View {
    @ObservedObject var viewModel: RootViewModel

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            sectionContent
                .background(
                    LinearGradient(
                        colors: [Color(NSColor.windowBackgroundColor), Color(NSColor.controlBackgroundColor)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .navigationSplitViewStyle(.balanced)
        .alert(
            "发现新版本 \(viewModel.availableUpdate?.version ?? "")",
            isPresented: Binding(
                get: { viewModel.availableUpdate != nil },
                set: { if !$0 { viewModel.dismissUpdatePrompt() } }
            ),
            actions: {
                Button("立即更新") {
                    Task { await viewModel.installAvailableUpdate() }
                }
                Button("取消", role: .cancel) {
                    viewModel.dismissUpdatePrompt()
                }
            },
            message: {
                if let release = viewModel.availableUpdate {
                    Text("检测到 GitHub Release \(release.tagName)。点击“立即更新”后会自动下载安装并重启应用。")
                }
            }
        )
        .alert(
            "更新失败",
            isPresented: Binding(
                get: { viewModel.updateErrorMessage != nil },
                set: { if !$0 { viewModel.updateErrorMessage = nil } }
            ),
            actions: {
                Button("知道了", role: .cancel) {
                    viewModel.updateErrorMessage = nil
                }
            },
            message: {
                Text(viewModel.updateErrorMessage ?? "未知错误")
            }
        )
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("swichcodex")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Codex 原生控制台")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.lg)

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                ForEach(NavigationSection.allCases, id: \.self) { section in
                    Button {
                        viewModel.selection = section
                    } label: {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: section.symbol)
                                .frame(width: 18)
                            Text(section.title)
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                        }
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .background(viewModel.selection == section ? Color.accentColor.opacity(0.12) : .clear)
                        .foregroundStyle(viewModel.selection == section ? Color.accentColor : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppSpacing.sm)

            Spacer()

            updatePanel
                .padding(.horizontal, AppSpacing.md)
                .padding(.bottom, AppSpacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial)
        .navigationSplitViewColumnWidth(min: 240, ideal: 252, max: 280)
    }

    private var updatePanel: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("v\(viewModel.currentVersion)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Button {
                Task { await viewModel.checkForUpdates() }
            } label: {
                HStack(spacing: 6) {
                    if viewModel.isCheckingForUpdates || viewModel.isInstallingUpdate {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.down.circle")
                    }
                    Text(viewModel.isInstallingUpdate ? "正在更新…" : "检查更新")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.sm)
                .frame(maxWidth: .infinity)
                .background(AppSemanticColor.mutedFill)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isCheckingForUpdates || viewModel.isInstallingUpdate)

            if let updateStatusMessage = viewModel.updateStatusMessage {
                Text(updateStatusMessage)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch viewModel.selection {
        case .accounts:
            AccountsView(viewModel: viewModel.accountsViewModel)
        case .instances:
            InstancesView(viewModel: viewModel.instancesViewModel)
        case .sessions:
            SessionsView(viewModel: viewModel.sessionsViewModel)
        }
    }
}
