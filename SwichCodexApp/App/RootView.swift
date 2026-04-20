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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial)
        .navigationSplitViewColumnWidth(min: 240, ideal: 252, max: 280)
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
