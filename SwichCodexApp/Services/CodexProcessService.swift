import AppKit
import Foundation

struct CodexProcessService: CodexProcessServicing, @unchecked Sendable {
    func resolveCodexApplicationURL() async throws -> URL {
        let fm = FileManager.default
        let directCandidates = [
            URL(fileURLWithPath: "/Applications/Codex.app"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Codex.app")
        ]
        if let candidate = directCandidates.first(where: { fm.fileExists(atPath: $0.path) }) {
            return candidate
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") {
            return url
        }
        let output = try runProcess("/usr/bin/mdfind", arguments: ["kMDItemFSName == 'Codex.app'"])
        if let first = output
            .split(separator: "\n")
            .map(String.init)
            .map({ URL(fileURLWithPath: $0) })
            .first(where: { fm.fileExists(atPath: $0.path) }) {
            return first
        }
        throw NSError(domain: "SwichCodex", code: 404, userInfo: [NSLocalizedDescriptionKey: "未找到 Codex.app，请先安装桌面客户端。"])
    }

    func startInstance(at root: URL, isDefault: Bool, extraArgs: String) async throws -> Int32 {
        let appURL = try await resolveCodexApplicationURL()
        if isDefault {
            var args = ["-n", "-a", appURL.path]
            args.append(contentsOf: parseArgs(extraArgs))
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = args
            try process.run()
            return Int32(process.processIdentifier)
        }

        let executable = try executableURL(for: appURL)
        let process = Process()
        process.executableURL = executable
        process.environment = ProcessInfo.processInfo.environment.merging(["CODEX_HOME": root.path]) { _, new in new }
        process.arguments = parseArgs(extraArgs)
        try process.run()
        return Int32(process.processIdentifier)
    }

    func stopInstance(pid: Int32?, root: URL, isDefault: Bool) async throws {
        if let pid, pid > 0 {
            kill(pid, SIGTERM)
            return
        }
        let pattern = isDefault ? "Codex.app" : "CODEX_HOME=\(root.path)"
        let output = try runProcess("/usr/bin/pgrep", arguments: ["-f", pattern])
        for line in output.split(separator: "\n") {
            if let pid = Int32(line.trimmingCharacters(in: .whitespacesAndNewlines)) {
                kill(pid, SIGTERM)
            }
        }
    }

    func focusInstance(pid: Int32?) async throws {
        if let pid, let app = NSRunningApplication(processIdentifier: pid_t(pid)) {
            _ = app.activate()
            return
        }
        let script = #"tell application "Codex" to activate"#
        _ = try runProcess("/usr/bin/osascript", arguments: ["-e", script])
    }

    func isRunning(pid: Int32?, root: URL, isDefault: Bool) async -> Bool {
        if let pid, pid > 0 {
            return kill(pid, 0) == 0
        }
        let pattern = isDefault ? "Codex.app" : "CODEX_HOME=\(root.path)"
        do {
            let output = try runProcess("/usr/bin/pgrep", arguments: ["-f", pattern])
            return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } catch {
            return false
        }
    }

    private func executableURL(for appURL: URL) throws -> URL {
        let info = appURL.appendingPathComponent("Contents/Info.plist")
        if let dict = NSDictionary(contentsOf: info),
           let executable = dict["CFBundleExecutable"] as? String {
            return appURL.appendingPathComponent("Contents/MacOS/\(executable)")
        }
        let fallback = appURL.appendingPathComponent("Contents/MacOS/Codex")
        if FileManager.default.fileExists(atPath: fallback.path) { return fallback }
        throw NSError(domain: "SwichCodex", code: 500, userInfo: [NSLocalizedDescriptionKey: "无法定位 Codex 可执行文件。"])
    }

    private func parseArgs(_ raw: String) -> [String] {
        raw.split(separator: " ").map(String.init).filter { !$0.isEmpty }
    }

    @discardableResult
    private func runProcess(_ executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        if process.terminationStatus != 0 {
            let error = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw NSError(domain: "SwichCodex", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: error.isEmpty ? output : error])
        }
        return output
    }
}
