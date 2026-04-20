import Foundation

struct BackupSnapshot {
    let directory: URL
    let files: [URL]
}

struct BackupService: @unchecked Sendable {
    let fileStore: FileStore

    func backup(urls: [URL], operation: String) throws -> BackupSnapshot {
        try AppPaths.ensureBaseDirectories()
        let directory = AppPaths.backupsDirectory
            .appendingPathComponent("\(timestamp())-\(operation)", isDirectory: true)
        try fileStore.createDirectory(directory)
        var copied: [URL] = []
        for url in urls where fileStore.fileExists(url) {
            let target = directory.appendingPathComponent(url.lastPathComponent)
            try fileStore.copyItem(at: url, to: target)
            copied.append(target)
        }
        return BackupSnapshot(directory: directory, files: copied)
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
