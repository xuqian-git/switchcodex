import SwiftUI

struct SessionsView: View {
    @ObservedObject var viewModel: SessionsViewModel
    @State private var pendingTrashSession: CodexSession?

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            header

            if let feedback = viewModel.feedback {
                FeedbackBanner(feedback: feedback)
            }

            actionPanel

            HStack(alignment: .top, spacing: AppSpacing.lg) {
                groupRail
                    .frame(width: 260)
                sessionsPanel
            }
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.lg)
        .navigationTitle("会话")
        .sheet(isPresented: $viewModel.isPresentingTrash) {
            SessionTrashSheet(viewModel: viewModel)
                .frame(width: 760, height: 480)
        }
        .confirmationDialog(
            "移入废纸篓",
            isPresented: Binding(
                get: { pendingTrashSession != nil },
                set: { if !$0 { pendingTrashSession = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let session = pendingTrashSession {
                Button("移入废纸篓", role: .destructive) {
                    Task { await viewModel.moveToTrash(session) }
                    pendingTrashSession = nil
                }
            }
            Button("取消", role: .cancel) {
                pendingTrashSession = nil
            }
        } message: {
            if let session = pendingTrashSession {
                Text("会话“\(session.title.isEmpty ? "未命名会话" : session.title)”将被移入废纸篓，可在废纸篓中恢复。")
            }
        }
        .task { await viewModel.load() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SESSIONS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Codex 会话管理")
                    .font(.system(size: 22, weight: .semibold))
            }

            Spacer(minLength: AppSpacing.md)

            HStack(spacing: AppSpacing.sm) {
                headerMetric("会话", "\(viewModel.sessions.count)")
                headerMetric("分组", "\(max(viewModel.groups.count - 1, 0))")
                headerMetric("废纸篓", "\(viewModel.trash.count)")
            }
        }
    }

    private func headerMetric(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, 6)
        .background(AppSemanticColor.mutedFill)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .fixedSize(horizontal: true, vertical: false)
    }

    private var actionPanel: some View {
        HStack(spacing: AppSpacing.sm) {
            Button {
                Task { await viewModel.load() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .help("重新读取全部会话和分组。")

            Button {
                viewModel.isPresentingTrash = true
                Task { await viewModel.loadTrash() }
            } label: {
                Label("废纸篓", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .help("查看已移入废纸篓的会话并恢复。")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var groupRail: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("工作目录")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, AppSpacing.sm)

            ScrollView {
                VStack(spacing: AppSpacing.xs) {
                    ForEach(viewModel.groups, id: \.self) { group in
                        Button {
                            viewModel.selectedGroup = group
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group)
                                        .font(.system(size: 13, weight: .semibold))
                                        .lineLimit(1)
                                    Text("\(count(for: group)) 个会话")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, AppSpacing.sm)
                            .padding(.vertical, AppSpacing.sm)
                            .background(viewModel.selectedGroup == group ? Color.accentColor.opacity(0.12) : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(AppSpacing.md)
        .frame(maxHeight: .infinity, alignment: .top)
        .appPanelStyle()
    }

    private var sessionsPanel: some View {
        Group {
            if viewModel.filteredSessions.isEmpty {
                AppEmptyState(title: "没有会话", message: "启动 Codex 并产生对话后，会话会自动出现在这里。", symbol: "text.bubble")
            } else {
                List(selection: $viewModel.selectedSessionID) {
                    ForEach(viewModel.filteredSessions) { session in
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(session.title.isEmpty ? "未命名会话" : session.title)
                                        .font(.system(size: 14, weight: .semibold))
                                    Text(session.cwd)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(session.updatedAt?.formatted(date: .abbreviated, time: .shortened) ?? "未知")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.secondary)
                                    AppStatusBadge(text: "\(session.locations.count) 个实例", color: .secondary)
                                }
                            }

                            HStack {
                                if let stats = session.tokenStats {
                                    Label("\(stats.totalTokens.formatted()) tokens", systemImage: "waveform.path.ecg")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("tokens 暂无")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("移入废纸篓") {
                                    pendingTrashSession = session
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.red)
                            }
                        }
                        .padding(.vertical, AppSpacing.xs)
                        .contextMenu {
                            Button("移入废纸篓") {
                                pendingTrashSession = session
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appPanelStyle()
    }

    private func count(for group: String) -> Int {
        return viewModel.sessions.filter { $0.cwd == group }.count
    }
}

struct SessionsInspectorView: View {
    @ObservedObject var viewModel: SessionsViewModel

    var body: some View {
        Group {
            if let session = viewModel.selectedSession {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        Text(session.title.isEmpty ? "未命名会话" : session.title)
                            .font(.system(size: 22, weight: .semibold))
                        AppDetailRow(title: "会话 ID", value: session.id)
                        AppDetailRow(title: "工作目录", value: session.cwd)
                        AppDetailRow(title: "更新时间", value: session.updatedAt?.formatted(date: .abbreviated, time: .shortened) ?? "未知")

                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text("所在实例")
                                .font(.system(size: 15, weight: .semibold))
                            ForEach(session.locations, id: \.self) { location in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(location.instanceName)
                                        Text(location.instanceRoot)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    AppStatusBadge(text: location.running ? "运行中" : "静止", color: location.running ? AppSemanticColor.success : .secondary)
                                }
                                .padding(AppSpacing.md)
                                .background(AppSemanticColor.mutedFill)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }
                    .padding(AppSpacing.xl)
                }
            } else {
                AppEmptyState(title: "未选择会话", message: "从中间列表选择一个会话查看它所在的实例位置。", symbol: "info.bubble")
                    .padding(AppSpacing.lg)
            }
        }
    }
}

struct SessionTrashSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: SessionsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                Text("废纸篓")
                    .font(.system(size: 22, weight: .semibold))
                Spacer()
                Button("关闭") { dismiss() }
            }
            if viewModel.trash.isEmpty {
                AppEmptyState(title: "废纸篓为空", message: "删除的会话会临时保存在这里，可随时恢复。", symbol: "trash")
            } else {
                List(viewModel.trash) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.system(size: 13, weight: .semibold))
                            Text(item.cwd)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(item.deletedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("恢复") {
                            Task { await viewModel.restore(item) }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(AppSpacing.xl)
        .task {
            await viewModel.loadTrash()
        }
    }
}
