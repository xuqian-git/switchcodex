import Foundation

final class DirectoryMutationCoordinator: @unchecked Sendable {
    private let lock = NSLock()

    func perform<T>(directory _: URL, operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}
