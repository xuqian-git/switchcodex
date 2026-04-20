import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AccountsView: View {
    @ObservedObject var viewModel: AccountsViewModel
    @State private var pendingDeleteAccount: CodexAccount?
    @State private var isShowingBatchDeleteAlert = false

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            header

            if let feedback = viewModel.feedback {
                FeedbackBanner(feedback: feedback)
            }

            actionPanel
            cardsPanel
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.lg)
        .navigationTitle("账号")
        .sheet(isPresented: $viewModel.isPresentingAddSheet) {
            AddAccountSheet(viewModel: viewModel)
                .frame(width: 560, height: 480)
        }
        .alert("删除账号", isPresented: Binding(
            get: { pendingDeleteAccount != nil },
            set: { if !$0 { pendingDeleteAccount = nil } }
        )) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let account = pendingDeleteAccount {
                    Task { await viewModel.deleteAccount(account) }
                }
                pendingDeleteAccount = nil
            }
        } message: {
            if let account = pendingDeleteAccount {
                Text("确认删除账号「\(account.resolvedDisplayName)」？此操作会移除本地保存的账号记录。")
            }
        }
        .alert("批量删除账号", isPresented: $isShowingBatchDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                Task { await viewModel.deleteSelectedAccounts() }
            }
        } message: {
            Text("确认删除当前选中的 \(viewModel.selectedAccountsCount) 个账号？此操作不可撤销。")
        }
        .task { await viewModel.load() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ACCOUNTS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Codex 账号总览")
                    .font(.system(size: 24, weight: .semibold))
            }

            Spacer(minLength: AppSpacing.md)

            HStack(spacing: AppSpacing.sm) {
                headerMetric("账号", "\(viewModel.accounts.count)")
                headerMetric("当前", "\(viewModel.accounts.filter { $0.isCurrent }.count)")
                headerMetric("API Key", "\(viewModel.accounts.filter { $0.authMode == .apikey }.count)")
            }

            if let current = viewModel.accounts.first(where: { $0.isCurrent }) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(current.resolvedDisplayName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(viewModel.hideEmail ? Masking.maskEmail(current.email) : current.email)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
                .padding(.leading, AppSpacing.sm)
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
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索邮箱、账号名、团队、标签", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(AppSemanticColor.mutedFill)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {
                viewModel.isPresentingAddSheet = true
            } label: {
                Label("添加", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .help("导入本地 auth.json、Token 或 API Key 账号。")

            Button {
                importAccounts()
            } label: {
                Label("批量导入", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)

            Button {
                viewModel.toggleBatchMode()
            } label: {
                Label(viewModel.isBatchMode ? "退出批量" : "批量操作", systemImage: viewModel.isBatchMode ? "checkmark.circle" : "checklist")
            }
            .buttonStyle(.bordered)

            if viewModel.isBatchMode {
                Text("已选 \(viewModel.selectedAccountsCount)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Button("全选") {
                    viewModel.selectAllFilteredAccounts()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.filteredAccounts.isEmpty)

                Button("清空") {
                    viewModel.clearSelection()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.selectedAccountsCount == 0)

                Button {
                    exportSelectedAccounts()
                } label: {
                    Label("批量导出", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.selectedAccountsCount == 0)

                Button(role: .destructive) {
                    isShowingBatchDeleteAlert = true
                } label: {
                    Label("批量删除", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.selectedAccountsCount == 0)
            }

            Button {
                Task { await viewModel.refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .help("重新读取当前账号状态和本地缓存数据。")

            Toggle(isOn: $viewModel.hideEmail) {
                EmptyView()
            }
            .labelsHidden()
            .toggleStyle(.switch)
            .help("切换邮箱的脱敏显示。")

            Button {
                withAnimation(.snappy) { viewModel.isGrid.toggle() }
            } label: {
                Image(systemName: viewModel.isGrid ? "rectangle.grid.1x2" : "square.grid.2x2")
            }
            .buttonStyle(.bordered)
            .help("切换账号卡片和紧凑列表视图。")
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .appPanelStyle()
    }

    private var cardsPanel: some View {
        Group {
            if viewModel.filteredAccounts.isEmpty {
                AppEmptyState(title: "没有账号", message: "从本地 auth.json、Token 或 API Key 导入后会显示在这里。", symbol: "person.crop.circle.badge.plus")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    if viewModel.isGrid, viewModel.filteredAccounts.count > 1 {
                        VStack(alignment: .leading, spacing: AppSpacing.md) {
                            ForEach(gridRows, id: \.self) { row in
                                HStack(alignment: .top, spacing: AppSpacing.md) {
                                    ForEach(row) { account in
                                        accountCard(account)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    if row.count == 1 {
                                        Spacer()
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            ForEach(viewModel.filteredAccounts) { account in
                                Group {
                                    if viewModel.isGrid {
                                        accountCard(account)
                                    } else {
                                        accountCompactRow(account)
                                    }
                                }
                                .frame(maxWidth: viewModel.isGrid ? 420 : .infinity, alignment: .leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .appPanelStyle()
    }

    private var gridRows: [[CodexAccount]] {
        let accounts = viewModel.filteredAccounts
        return stride(from: 0, to: accounts.count, by: 2).map { index in
            Array(accounts[index ..< min(index + 2, accounts.count)])
        }
    }

    private func accountCard(_ account: CodexAccount) -> some View {
        let presentation = CodexAccountPresentation.make(for: account, hideEmail: viewModel.hideEmail)

        return VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(presentation.title)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    Text(presentation.subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
                Spacer()
                if viewModel.isBatchMode {
                    selectionButton(for: account)
                }
                if account.isCurrent {
                    AppStatusBadge(text: "当前", color: .accentColor)
                }
                AccountPlanBadge(label: presentation.planLabel, tone: presentation.planTone)
            }

            if let contextLine = presentation.contextLine {
                Text(contextLine)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 6) {
                if let identityLine = presentation.identityLine {
                    accountInfoLine(identityLine)
                }
                if let apiKeyLine = presentation.apiKeyLine {
                    accountInfoLine(apiKeyLine)
                }
                if let providerLine = presentation.providerLine {
                    accountInfoLine(providerLine)
                }
                if let baseURLLine = presentation.baseURLLine {
                    accountInfoLine(baseURLLine)
                }
            }

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                if let quotaErrorLine = presentation.quotaErrorLine {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(quotaErrorLine)
                            .lineLimit(2)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppSemanticColor.warning)
                }

                if account.authMode == .apikey {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "arrow.up.forward.square")
                        Text("API Key 账号不展示 ChatGPT 配额，可直接使用供应商与 Base URL。")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppSpacing.md)
                    .background(AppSemanticColor.mutedFill)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else if presentation.quotaItems.isEmpty {
                    Text("暂无配额数据")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppSpacing.md)
                        .background(AppSemanticColor.mutedFill)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    ForEach(presentation.quotaItems) { item in
                        quotaRow(item)
                    }
                }
            }

            if !presentation.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.xs) {
                        ForEach(Array(presentation.tags.prefix(3)), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(AppSemanticColor.mutedFill)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            HStack {
                Text(presentation.footerLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("切换") {
                    Task { await viewModel.switchAccount(account) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(account.isCurrent)
                Button(role: .destructive) {
                    pendingDeleteAccount = account
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                Button {
                    Task { await viewModel.refreshAccount(account) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground(account))
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous)
                .stroke(account.isCurrent ? Color.accentColor.opacity(0.22) : AppSemanticColor.subtleBorder)
        )
        .onTapGesture {
            handleAccountTap(account)
        }
    }

    private func accountCompactRow(_ account: CodexAccount) -> some View {
        let presentation = CodexAccountPresentation.make(for: account, hideEmail: viewModel.hideEmail)

        return HStack(spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: AppSpacing.xs) {
                    Text(presentation.title)
                        .font(.system(size: 13, weight: .semibold))
                    if viewModel.isBatchMode {
                        selectionButton(for: account)
                    }
                    if account.isCurrent {
                        AppStatusBadge(text: "当前", color: .accentColor)
                    }
                }
                Text(presentation.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: AppSpacing.md) {
                ForEach(Array(presentation.quotaItems.prefix(2))) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(item.valueText)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(quotaColor(item.tone))
                    }
                }
            }
            .frame(width: 120, alignment: .leading)

            Button {
                Task { await viewModel.switchAccount(account) }
            } label: {
                Image(systemName: account.isCurrent ? "checkmark" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(account.isCurrent)

            Button(role: .destructive) {
                pendingDeleteAccount = account
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(cardBackground(account))
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.compactCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.compactCard, style: .continuous)
                .stroke(account.isCurrent ? Color.accentColor.opacity(0.22) : AppSemanticColor.subtleBorder)
        )
        .onTapGesture {
            handleAccountTap(account)
        }
    }

    private func quotaRow(_ item: CodexAccountQuotaPresentation) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Text(item.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(item.valueText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(quotaColor(item.tone))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(quotaColor(item.tone).gradient)
                        .frame(width: max(12, proxy.size.width * CGFloat(item.percentage) / 100.0))
                }
            }
            .frame(height: 8)

            if let resetText = item.resetText {
                Text(resetText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AppSpacing.sm)
        .background(AppSemanticColor.mutedFill)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func accountInfoLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .textSelection(.enabled)
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

    private func cardBackground(_ account: CodexAccount) -> some ShapeStyle {
        if account.isCurrent {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.16), Color.accentColor.opacity(0.07)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(.thinMaterial)
    }

    private func handleAccountTap(_ account: CodexAccount) {
        if viewModel.isBatchMode {
            viewModel.toggleAccountSelection(account.id)
        } else {
            viewModel.selectedAccountID = account.id
        }
    }

    private func selectionButton(for account: CodexAccount) -> some View {
        let isSelected = viewModel.selectedAccountIDs.contains(account.id)

        return Button {
            viewModel.toggleAccountSelection(account.id)
        } label: {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func importAccounts() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await viewModel.importAccounts(from: url) }
    }

    private func exportSelectedAccounts() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "codex-accounts-export.json"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await viewModel.exportSelectedAccounts(to: url) }
    }
}

struct AccountsInspectorView: View {
    @ObservedObject var viewModel: AccountsViewModel

    var body: some View {
        Group {
            if let account = viewModel.selectedAccount {
                let presentation = CodexAccountPresentation.make(for: account, hideEmail: false)

                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        HStack {
                            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                Text(account.resolvedDisplayName)
                                    .font(.system(size: 24, weight: .semibold))
                                Text(account.email)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Spacer()
                            AccountPlanBadge(label: presentation.planLabel, tone: presentation.planTone)
                        }

                        VStack(alignment: .leading, spacing: AppSpacing.md) {
                            AppDetailRow(title: "账号 ID", value: account.accountID ?? "暂无")
                            AppDetailRow(title: "用户 ID", value: account.userID ?? "暂无")
                            AppDetailRow(title: "组织 ID", value: account.organizationID ?? "暂无")
                            AppDetailRow(title: "账号结构", value: account.accountStructure ?? "暂无")
                            AppDetailRow(title: "团队", value: account.teamName ?? "暂无")
                            AppDetailRow(title: "API Base URL", value: account.apiBaseURL ?? "默认")
                        }

                        if !presentation.quotaItems.isEmpty {
                            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                                Text("配额")
                                    .font(.system(size: 15, weight: .semibold))
                                ForEach(presentation.quotaItems) { item in
                                    quotaInspectorRow(item)
                                }
                            }
                        }
                    }
                    .padding(AppSpacing.xl)
                }
            } else {
                AppEmptyState(title: "未选择账号", message: "从中间卡片区选择账号查看详细信息。", symbol: "person.crop.square")
                    .padding(AppSpacing.lg)
            }
        }
    }

    private func quotaInspectorRow(_ item: CodexAccountQuotaPresentation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.label)
                Spacer()
                Text(item.valueText)
                    .foregroundStyle(quotaColor(item.tone))
            }
            .font(.system(size: 13, weight: .semibold))

            ProgressView(value: Double(item.percentage), total: 100)
                .tint(quotaColor(item.tone))

            if let resetText = item.resetText {
                Text(resetText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AppSpacing.md)
        .background(AppSemanticColor.mutedFill)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

private struct AccountPlanBadge: View {
    let label: String
    let tone: CodexPlanTone

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch tone {
        case .free:
            return Color.secondary.opacity(0.14)
        case .plus:
            return Color.blue.opacity(0.14)
        case .pro:
            return Color.orange.opacity(0.16)
        case .team:
            return Color.teal.opacity(0.16)
        case .enterprise:
            return Color.indigo.opacity(0.16)
        case .neutral:
            return Color.secondary.opacity(0.14)
        }
    }

    private var foregroundColor: Color {
        switch tone {
        case .free, .neutral:
            return .secondary
        case .plus:
            return .blue
        case .pro:
            return .orange
        case .team:
            return .teal
        case .enterprise:
            return .indigo
        }
    }
}

struct AddAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: AccountsViewModel

    enum Mode: String, CaseIterable, Identifiable {
        case local
        case token
        case apikey

        var id: String { rawValue }
        var title: String {
            switch self {
            case .local: return "本地导入"
            case .token: return "Token"
            case .apikey: return "API Key"
            }
        }
    }

    @State private var mode: Mode = .local
    @State private var idToken = ""
    @State private var accessToken = ""
    @State private var refreshToken = ""
    @State private var apiKey = ""
    @State private var baseURL = ""

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            Text("添加账号")
                .font(.system(size: 22, weight: .semibold))

            Picker("方式", selection: $mode) {
                ForEach(Mode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            Group {
                switch mode {
                case .local:
                    Text("从当前 `~/.codex/auth.json` 导入默认账号。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                case .token:
                    Form {
                        TextField("ID Token", text: $idToken, axis: .vertical)
                        TextField("Access Token", text: $accessToken, axis: .vertical)
                        TextField("Refresh Token（可选）", text: $refreshToken, axis: .vertical)
                    }
                case .apikey:
                    Form {
                        SecureField("API Key", text: $apiKey)
                        TextField("Base URL（可选）", text: $baseURL)
                    }
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("导入") {
                    Task {
                        switch mode {
                        case .local:
                            await viewModel.addLocalAccount()
                        case .token:
                            await viewModel.addTokens(
                                idToken: idToken,
                                accessToken: accessToken,
                                refreshToken: refreshToken.isEmpty ? nil : refreshToken
                            )
                        case .apikey:
                            await viewModel.addAPIKey(apiKey, baseURL: baseURL.isEmpty ? nil : baseURL)
                        }
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isImportDisabled)
            }
        }
        .padding(AppSpacing.xl)
    }

    private var isImportDisabled: Bool {
        switch mode {
        case .local:
            return false
        case .token:
            return idToken.isEmpty || accessToken.isEmpty
        case .apikey:
            return apiKey.isEmpty
        }
    }
}
