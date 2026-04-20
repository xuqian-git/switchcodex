import Foundation

@MainActor
final class SessionsViewModel: ObservableObject {
    @Published var sessions: [CodexSession] = []
    @Published var trash: [TrashedSession] = []
    @Published var selectedSessionID: String?
    @Published var selectedGroup: String?
    @Published var feedback: OperationFeedback?
    @Published var isPresentingTrash = false

    private let sessionService: CodexSessionServicing
    private var feedbackDismissTask: Task<Void, Never>?

    init(sessionService: CodexSessionServicing, instanceService _: CodexInstanceServicing) {
        self.sessionService = sessionService
    }

    var groups: [String] {
        Array(Set(sessions.map(\.cwd))).sorted()
    }

    var filteredSessions: [CodexSession] {
        guard let selectedGroup, !selectedGroup.isEmpty else { return sessions }
        return sessions.filter { $0.cwd == selectedGroup }
    }

    func load() async {
        do {
            sessions = try await sessionService.listSessionsAcrossInstances()
            selectedSessionID = selectedSessionID ?? sessions.first?.id
            if let selectedGroup, groups.contains(selectedGroup) {
                self.selectedGroup = selectedGroup
            } else {
                self.selectedGroup = groups.first
            }
            if isPresentingTrash {
                trash = try await sessionService.listTrash()
            }
            await hydrateTokenStats()
        } catch {
            showFeedback(OperationFeedback(level: .error, message: error.localizedDescription))
        }
    }

    func loadTokenStats(for session: CodexSession) async {
        do {
            guard let value = try await sessionService.loadTokenStats(from: session.locations),
                  let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
            sessions[index].tokenStats = value
        } catch {
            showFeedback(OperationFeedback(level: .error, message: error.localizedDescription))
        }
    }

    func moveToTrash(_ session: CodexSession) async {
        do {
            showFeedback(try await sessionService.moveToTrash(sessionIDs: [session.id]))
            await load()
            trash = (try? await sessionService.listTrash()) ?? []
        } catch {
            showFeedback(OperationFeedback(level: .error, message: error.localizedDescription))
        }
    }

    func restore(_ item: TrashedSession) async {
        do {
            showFeedback(try await sessionService.restoreFromTrash(sessionIDs: [item.sessionID]))
            await load()
            trash = (try? await sessionService.listTrash()) ?? []
        } catch {
            showFeedback(OperationFeedback(level: .error, message: error.localizedDescription))
        }
    }

    var selectedSession: CodexSession? {
        sessions.first(where: { $0.id == selectedSessionID })
    }

    func loadTrash() async {
        trash = (try? await sessionService.listTrash()) ?? []
    }

    private func hydrateTokenStats() async {
        guard !sessions.isEmpty else { return }
        var hydrated = sessions
        for index in hydrated.indices {
            hydrated[index].tokenStats = try? await sessionService.loadTokenStats(from: hydrated[index].locations)
        }
        sessions = hydrated
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
