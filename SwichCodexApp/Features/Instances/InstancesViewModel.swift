import Foundation

@MainActor
final class InstancesViewModel: ObservableObject {
    @Published var instances: [CodexInstance] = []
    @Published var accounts: [CodexAccount] = []
    @Published var selectedInstanceID: String?
    @Published var feedback: OperationFeedback?
    @Published var isPresentingCreateSheet = false

    private let instanceService: CodexInstanceServicing
    private let accountService: CodexAccountServicing
    private var feedbackDismissTask: Task<Void, Never>?

    init(instanceService: CodexInstanceServicing, accountService: CodexAccountServicing) {
        self.instanceService = instanceService
        self.accountService = accountService
    }

    func load() async {
        do {
            instances = try await instanceService.listInstances()
            accounts = try await accountService.listAccounts()
            selectedInstanceID = selectedInstanceID ?? instances.first?.id
        } catch {
            showFeedback(OperationFeedback(level: .error, message: error.localizedDescription))
        }
    }

    func createInstance(name: String, directory: String, bindAccountID: String?) async {
        do {
            try await instanceService.createInstance(name: name, directory: directory, bindAccountID: bindAccountID)
            showFeedback(OperationFeedback(level: .success, message: "实例已创建。"))
            await load()
        } catch {
            showFeedback(OperationFeedback(level: .error, message: error.localizedDescription))
        }
    }

    func start(_ instance: CodexInstance) async {
        do {
            showFeedback(try await instanceService.startInstance(id: instance.id))
            await load()
        } catch {
            showFeedback(OperationFeedback(level: .error, message: error.localizedDescription))
        }
    }

    func stop(_ instance: CodexInstance) async {
        do {
            showFeedback(try await instanceService.stopInstance(id: instance.id))
            await load()
        } catch {
            showFeedback(OperationFeedback(level: .error, message: error.localizedDescription))
        }
    }

    func delete(_ instance: CodexInstance) async {
        do {
            showFeedback(try await instanceService.deleteInstance(id: instance.id))
            if selectedInstanceID == instance.id {
                selectedInstanceID = nil
            }
            await load()
        } catch {
            showFeedback(OperationFeedback(level: .error, message: error.localizedDescription))
        }
    }

    var selectedInstance: CodexInstance? {
        instances.first(where: { $0.id == selectedInstanceID })
    }

    func accountName(for id: String?) -> String {
        guard let id else { return "未绑定" }
        return accounts.first(where: { $0.id == id })?.resolvedDisplayName ?? id
    }

    private func showFeedback(_ value: OperationFeedback) {
        feedbackDismissTask?.cancel()
        feedback = value
        feedbackDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, feedback?.id == value.id else { return }
            feedback = nil
        }
    }
}
