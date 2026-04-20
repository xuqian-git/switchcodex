import AppKit
import SwiftUI

struct InstancesView: View {
    @ObservedObject var viewModel: InstancesViewModel
    @State private var pendingDeleteInstance: CodexInstance?

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            header

            if let feedback = viewModel.feedback {
                FeedbackBanner(feedback: feedback)
            }

            HStack(alignment: .top, spacing: AppSpacing.lg) {
                instancesTable
                selectedSummary
                    .frame(width: 320)
            }
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.lg)
        .navigationTitle("实例")
        .sheet(isPresented: $viewModel.isPresentingCreateSheet) {
            CreateInstanceSheet(viewModel: viewModel)
                .frame(width: 560, height: 360)
        }
        .confirmationDialog(
            "删除实例",
            isPresented: Binding(
                get: { pendingDeleteInstance != nil },
                set: { if !$0 { pendingDeleteInstance = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let instance = pendingDeleteInstance {
                Button("删除 \(instance.name)", role: .destructive) {
                    Task { await viewModel.delete(instance) }
                    pendingDeleteInstance = nil
                }
            }
            Button("取消", role: .cancel) {
                pendingDeleteInstance = nil
            }
        } message: {
            if let instance = pendingDeleteInstance {
                Text("只会把“\(instance.name)”从管理列表中移除，不会删除磁盘上的实例目录。")
            }
        }
        .task { await viewModel.load() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("INSTANCES")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Codex 多开实例")
                    .font(.system(size: 24, weight: .semibold))
            }

            Spacer(minLength: AppSpacing.md)
            
            HStack(spacing: AppSpacing.sm) {
                Button {
                    Task { await viewModel.load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help("重新读取实例状态和运行状态。")

                Button {
                    viewModel.isPresentingCreateSheet = true
                } label: {
                    Label("新建实例", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .help("创建新的 Codex 实例目录并绑定账号。")
            }
        }
    }

    private var instancesTable: some View {
        Group {
            if viewModel.instances.isEmpty {
                AppEmptyState(title: "没有实例", message: "新建实例后可以绑定账号并独立启动。", symbol: "square.grid.3x3")
            } else {
                Table(viewModel.instances, selection: $viewModel.selectedInstanceID) {
                    TableColumn("名称") { instance in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(instance.name)
                                    .font(.system(size: 13, weight: .semibold))
                                if instance.isDefault {
                                    AppStatusBadge(text: "默认", color: .accentColor)
                                }
                            }
                            Text(instance.userDataDir)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    TableColumn("绑定账号") { instance in
                        Text(viewModel.accountName(for: instance.bindAccountID))
                            .font(.system(size: 12))
                    }
                    TableColumn("状态") { instance in
                        AppStatusBadge(
                            text: instance.isRunning ? "运行中" : "已停止",
                            color: instance.isRunning ? AppSemanticColor.success : .secondary
                        )
                    }
                    TableColumn("最后启动") { instance in
                        Text(instance.lastLaunchedAt.map(AppDateFormatting.display) ?? "未启动")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    TableColumn("操作") { instance in
                        HStack(spacing: AppSpacing.xs) {
                            Button(instance.isRunning ? "停止" : "启动") {
                                Task {
                                    if instance.isRunning {
                                        await viewModel.stop(instance)
                                    } else {
                                        await viewModel.start(instance)
                                    }
                                }
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(instance.isRunning ? AppSemanticColor.warning : AppSemanticColor.success)

                            if !instance.isDefault {
                                Button("删除") {
                                    pendingDeleteInstance = instance
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.red)
                            }
                        }
                        .font(.system(size: 12, weight: .medium))
                    }
                }
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appPanelStyle()
    }

    private var selectedSummary: some View {
        Group {
            if let instance = viewModel.selectedInstance {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    HStack {
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text(instance.name)
                                .font(.system(size: 22, weight: .semibold))
                            Text(instance.isDefault ? "默认实例" : "受管实例")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        AppStatusBadge(
                            text: instance.isRunning ? "运行中" : "静止",
                            color: instance.isRunning ? AppSemanticColor.success : .secondary
                        )
                    }

                    AppDetailRow(title: "目录", value: instance.userDataDir)
                    AppDetailRow(title: "绑定账号", value: viewModel.accountName(for: instance.bindAccountID))
                    AppDetailRow(title: "初始化状态", value: instance.isInitialized ? "已初始化" : "未初始化")
                    AppDetailRow(title: "附加参数", value: instance.extraArgs.isEmpty ? "暂无" : instance.extraArgs)

                    Spacer()
                }
                .padding(AppSpacing.lg)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .appPanelStyle()
            } else {
                AppEmptyState(title: "未选择实例", message: "从左侧实例列表中选择一项查看状态。", symbol: "macwindow")
                    .padding(AppSpacing.md)
                    .frame(maxHeight: .infinity)
                    .appPanelStyle()
            }
        }
    }
}

struct InstancesInspectorView: View {
    @ObservedObject var viewModel: InstancesViewModel

    var body: some View {
        Group {
            if let instance = viewModel.selectedInstance {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    Text("运行信息")
                        .font(.system(size: 20, weight: .semibold))
                    AppDetailRow(title: "实例 ID", value: instance.id)
                    AppDetailRow(title: "最后启动", value: instance.lastLaunchedAt.map(AppDateFormatting.display) ?? "未知")
                    AppDetailRow(title: "绑定账号 ID", value: instance.bindAccountID ?? "未绑定")
                    Spacer()
                }
                .padding(AppSpacing.xl)
            } else {
                AppEmptyState(title: "无额外信息", message: "选择实例后会在这里显示补充信息。", symbol: "info.square")
                    .padding(AppSpacing.lg)
            }
        }
    }
}

struct CreateInstanceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: InstancesViewModel
    @State private var name = ""
    @State private var directory = ""
    @State private var bindAccountID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            Text("新建实例")
                .font(.system(size: 22, weight: .semibold))
            Form {
                TextField("实例名称", text: $name)
                HStack {
                    TextField("实例目录", text: $directory)
                    Button("选择…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.canCreateDirectories = true
                        if panel.runModal() == .OK {
                            directory = panel.url?.path ?? ""
                        }
                    }
                }
                Picker("绑定账号", selection: $bindAccountID) {
                    Text("不绑定").tag("")
                    ForEach(viewModel.accounts) { account in
                        Text(account.resolvedDisplayName).tag(account.id)
                    }
                }
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("创建") {
                    Task {
                        await viewModel.createInstance(
                            name: name,
                            directory: directory,
                            bindAccountID: bindAccountID.isEmpty ? nil : bindAccountID
                        )
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(directory.isEmpty)
            }
        }
        .padding(AppSpacing.xl)
    }
}
