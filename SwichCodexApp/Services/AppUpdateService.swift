import AppKit
import Foundation

enum AppUpdateServiceError: LocalizedError {
    case invalidResponse
    case missingDMGAsset
    case mountFailed
    case missingAppBundle
    case installScriptFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "更新查询失败：GitHub Release 返回了无效响应。"
        case .missingDMGAsset:
            return "更新查询失败：未找到可下载的 DMG 安装包。"
        case .mountFailed:
            return "更新安装失败：无法挂载下载的 DMG。"
        case .missingAppBundle:
            return "更新安装失败：DMG 中没有找到 SwichCodex.app。"
        case .installScriptFailed:
            return "更新安装失败：无法启动自动更新脚本。"
        }
    }
}

struct AppUpdateService: AppUpdateServicing, @unchecked Sendable {
    private let session: URLSession
    private let owner = "xuqian-git"
    private let repo = "switchcodex"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func currentVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    func checkForUpdates() async throws -> AppUpdateCheckResult {
        let release = try await fetchLatestRelease()
        let current = currentVersion()
        if isVersion(release.version, newerThan: current) {
            return .updateAvailable(currentVersion: current, release: release)
        }
        return .upToDate(currentVersion: current)
    }

    func installUpdate(from release: AppReleaseInfo) async throws {
        guard let asset = release.primaryDMGAsset else {
            throw AppUpdateServiceError.missingDMGAsset
        }

        let downloadedDMG = try await downloadDMG(from: asset.downloadURL)
        let mountedVolume = try mountDMG(at: downloadedDMG)
        let sourceApp = try locateAppBundle(in: mountedVolume)
        let targetApp = installTargetURL()
        let scriptURL = try writeInstallerScript(
            sourceApp: sourceApp,
            targetApp: targetApp,
            mountPoint: mountedVolume,
            downloadedDMG: downloadedDMG
        )

        try launchInstallerScript(at: scriptURL, sourceApp: sourceApp, targetApp: targetApp, mountPoint: mountedVolume, downloadedDMG: downloadedDMG)

        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }

    private func fetchLatestRelease() async throws -> AppReleaseInfo {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SwichCodex/\(currentVersion())", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
            throw AppUpdateServiceError.invalidResponse
        }

        return try JSONDecoder().decode(AppReleaseInfo.self, from: data)
    }

    private func downloadDMG(from url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("SwichCodex/\(currentVersion())", forHTTPHeaderField: "User-Agent")

        let (temporaryURL, response) = try await session.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
            throw AppUpdateServiceError.invalidResponse
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwichCodex-\(UUID().uuidString).dmg")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private func mountDMG(at url: URL) throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["attach", url.path, "-nobrowse", "-readonly", "-plist"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw AppUpdateServiceError.mountFailed
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]] else {
            throw AppUpdateServiceError.mountFailed
        }

        for entity in entities {
            if let mountPoint = entity["mount-point"] as? String {
                return URL(fileURLWithPath: mountPoint, isDirectory: true)
            }
        }

        throw AppUpdateServiceError.mountFailed
    }

    private func locateAppBundle(in mountedVolume: URL) throws -> URL {
        let candidates = (try? FileManager.default.contentsOfDirectory(at: mountedVolume, includingPropertiesForKeys: nil)) ?? []
        if let appURL = candidates.first(where: { $0.pathExtension == "app" }) {
            return appURL
        }
        throw AppUpdateServiceError.missingAppBundle
    }

    private func installTargetURL() -> URL {
        let currentBundle = Bundle.main.bundleURL.standardizedFileURL
        let currentDirectory = currentBundle.deletingLastPathComponent()
        if FileManager.default.isWritableFile(atPath: currentDirectory.path) {
            return currentBundle
        }
        return URL(fileURLWithPath: "/Applications", isDirectory: true)
            .appendingPathComponent(currentBundle.lastPathComponent, isDirectory: true)
    }

    private func writeInstallerScript(sourceApp: URL, targetApp: URL, mountPoint: URL, downloadedDMG: URL) throws -> URL {
        let script = """
        #!/bin/bash
        set -euo pipefail
        PID="$1"
        SRC_APP="$2"
        TARGET_APP="$3"
        MOUNT_POINT="$4"
        DMG_PATH="$5"

        while kill -0 "$PID" 2>/dev/null; do
          sleep 1
        done

        TMP_APP="${TARGET_APP}.updating"
        rm -rf "$TMP_APP"
        /usr/bin/ditto "$SRC_APP" "$TMP_APP"
        rm -rf "$TARGET_APP"
        mv "$TMP_APP" "$TARGET_APP"
        /usr/bin/hdiutil detach "$MOUNT_POINT" -quiet || true
        rm -f "$DMG_PATH"
        open "$TARGET_APP"
        rm -f "$0"
        """

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("swichcodex-updater-\(UUID().uuidString).sh")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func launchInstallerScript(at scriptURL: URL, sourceApp: URL, targetApp: URL, mountPoint: URL, downloadedDMG: URL) throws {
        let command = """
        nohup '\(scriptURL.path)' '\(ProcessInfo.processInfo.processIdentifier)' '\(sourceApp.path)' '\(targetApp.path)' '\(mountPoint.path)' '\(downloadedDMG.path)' >/tmp/swichcodex-updater.log 2>&1 &
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", command]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw AppUpdateServiceError.installScriptFailed
        }
    }

    private func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let left = versionComponents(lhs)
        let right = versionComponents(rhs)
        let count = max(left.count, right.count)
        for index in 0 ..< count {
            let leftValue = index < left.count ? left[index] : 0
            let rightValue = index < right.count ? right[index] : 0
            if leftValue != rightValue {
                return leftValue > rightValue
            }
        }
        return false
    }

    private func versionComponents(_ value: String) -> [Int] {
        value
            .split(separator: ".")
            .map { component in
                Int(component.filter(\.isNumber)) ?? 0
            }
    }
}
