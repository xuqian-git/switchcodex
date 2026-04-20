import Foundation

@MainActor
final class RootViewModel: ObservableObject {
    @Published var selection: NavigationSection = .accounts

    let accountsViewModel: AccountsViewModel
    let instancesViewModel: InstancesViewModel
    let sessionsViewModel: SessionsViewModel

    init(
        accountsViewModel: AccountsViewModel,
        instancesViewModel: InstancesViewModel,
        sessionsViewModel: SessionsViewModel
    ) {
        self.accountsViewModel = accountsViewModel
        self.instancesViewModel = instancesViewModel
        self.sessionsViewModel = sessionsViewModel

        Task {
            await accountsViewModel.load()
        }
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
            )
        )
    }
}
