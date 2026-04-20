import Foundation

enum AppPaths {
    static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    static var codexHome: URL {
        if let env = ProcessInfo.processInfo.environment["CODEX_HOME"], !env.isEmpty {
            return URL(fileURLWithPath: env)
        }
        return home.appendingPathComponent(".codex", isDirectory: true)
    }

    static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("swichcodex", isDirectory: true)
    }

    static var accountsURL: URL { applicationSupport.appendingPathComponent("accounts.json") }
    static var groupsURL: URL { applicationSupport.appendingPathComponent("account-groups.json") }
    static var instancesURL: URL { applicationSupport.appendingPathComponent("instances.json") }
    static var backupsDirectory: URL { applicationSupport.appendingPathComponent("backups", isDirectory: true) }
    static var sessionTrashDirectory: URL { applicationSupport.appendingPathComponent("session-trash", isDirectory: true) }
    static var logsDirectory: URL { applicationSupport.appendingPathComponent("logs", isDirectory: true) }
    static var authURL: URL { codexHome.appendingPathComponent("auth.json") }
    static var configURL: URL { codexHome.appendingPathComponent("config.toml") }

    static func ensureBaseDirectories() throws {
        let fm = FileManager.default
        for directory in [applicationSupport, backupsDirectory, sessionTrashDirectory, logsDirectory] {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}

