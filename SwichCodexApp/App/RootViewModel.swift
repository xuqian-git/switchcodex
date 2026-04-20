import Foundation

@MainActor
final class RootViewModel: ObservableObject {
    @Published var selection: NavigationSection = .accounts
    @Published var updateStatusMessage: String?
    @Published var isCheckingForUpdates = false
    @Published var isInstallingUpdate = false
    @Published var availableUpdate: AppReleaseInfo?
    @Published var updateErrorMessage: String?

    let accountsViewModel: AccountsViewModel
    let instancesViewModel: InstancesViewModel
    let sessionsViewModel: SessionsViewModel
    let currentVersion: String

    private let updateService: AppUpdateServicing
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
    }

    func checkForUpdates() async {
        guard !isCheckingForUpdates, !isInstallingUpdate else { return }
        isCheckingForUpdates = true
        updateErrorMessage = nil
        updateStatusMessage = nil
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
        guard let availableUpdate, !isInstallingUpdate else { return }
        isInstallingUpdate = true
        updateErrorMessage = nil
        updateStatusMessage = "正在下载并安装 \(availableUpdate.version)…"
        defer { isInstallingUpdate = false }

        do {
            try await updateService.installUpdate(from: availableUpdate)
        } catch {
            updateErrorMessage = error.localizedDescription
            updateStatusMessage = nil
        }
    }

    func dismissUpdatePrompt() {
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
