import Foundation

@MainActor
final class RootViewModel: ObservableObject {
    @Published var selection: NavigationSection = .accounts
    @Published var updateStatusMessage: String?
    @Published var isCheckingForUpdates = false
    @Published var isInstallingUpdate = false
    @Published var updateProgress: Double = 0
    @Published var availableUpdate: AppReleaseInfo?
    @Published var updateErrorMessage: String?

    let accountsViewModel: AccountsViewModel
    let instancesViewModel: InstancesViewModel
    let sessionsViewModel: SessionsViewModel
    let currentVersion: String

    private let updateService: AppUpdateServicing
    private var pendingInstallRelease: AppReleaseInfo?
    init(
        accountsViewModel: AccountsViewModel,
        instancesViewModel: InstancesViewModel,
        sessionsViewModel: SessionsViewModel,
        updateService: AppUpdateServicing
    ) {
        self.accountsViewModel = accountsViewModel
        self.instancesViewModel = instancesViewModel
        self.sessionsViewModel = sessionsViewModel
        self.updateService = updateService
        currentVersion = updateService.currentVersion()

        Task {
            await accountsViewModel.load()
        }
        accountsViewModel.startAutoRefresh()
    }

    func checkForUpdates() async {
        guard !isCheckingForUpdates, !isInstallingUpdate else { return }
        isCheckingForUpdates = true
        updateErrorMessage = nil
        updateStatusMessage = nil
        updateProgress = 0
        defer { isCheckingForUpdates = false }

        do {
            switch try await updateService.checkForUpdates() {
            case let .upToDate(currentVersion):
                updateStatusMessage = "当前已是最新版 \(currentVersion)"
                availableUpdate = nil
            case let .updateAvailable(_, release):
                availableUpdate = release
                updateStatusMessage = "发现新版本 \(release.version)"
            }
        } catch {
            updateErrorMessage = error.localizedDescription
        }
    }

    func installAvailableUpdate() async {
        guard let release = pendingInstallRelease, isInstallingUpdate else { return }

        do {
            try await updateService.installUpdate(from: release) { [weak self] fractionCompleted, status in
                Task { @MainActor in
                    self?.updateProgress = min(max(fractionCompleted, 0), 1)
                    self?.updateStatusMessage = status
                }
            }
        } catch {
            isInstallingUpdate = false
            updateProgress = 0
            self.pendingInstallRelease = nil
            updateErrorMessage = error.localizedDescription
            updateStatusMessage = nil
        }
    }

    func beginInstallAvailableUpdate() {
        guard let availableUpdate, !isInstallingUpdate else { return }
        isInstallingUpdate = true
        pendingInstallRelease = availableUpdate
        updateErrorMessage = nil
        updateStatusMessage = "正在准备安装 \(availableUpdate.version)…"
        updateProgress = 0.02
        self.availableUpdate = nil
        Task { await installAvailableUpdate() }
    }

    func dismissUpdatePrompt() {
        guard !isInstallingUpdate else { return }
        availableUpdate = nil
    }

    static func live() -> RootViewModel {
        let fileStore = FileStore()
        let backupService = BackupService(fileStore: fileStore)
        let mutationCoordinator = DirectoryMutationCoordinator()
        let accountService = CodexAccountService(
            fileStore: fileStore,
            backupService: backupService,
            mutationCoordinator: mutationCoordinator
        )
        let groupService = CodexGroupService(fileStore: fileStore)
        let processService = CodexProcessService()
        let instanceService = CodexInstanceService(
            fileStore: fileStore,
            backupService: backupService,
            mutationCoordinator: mutationCoordinator,
            accountService: accountService,
            processService: processService
        )
        let sessionService = CodexSessionService(
            fileStore: fileStore,
            backupService: backupService,
            mutationCoordinator: mutationCoordinator,
            instanceService: instanceService,
            processService: processService
        )
        let updateService = AppUpdateService()

        return RootViewModel(
            accountsViewModel: AccountsViewModel(
                accountService: accountService,
                groupService: groupService
            ),
            instancesViewModel: InstancesViewModel(
                instanceService: instanceService,
                accountService: accountService
            ),
            sessionsViewModel: SessionsViewModel(
                sessionService: sessionService,
                instanceService: instanceService
            ),
            updateService: updateService
        )
    }
}
