import Foundation

enum AppBinaryArchitecture: String, Hashable {
    case arm64
    case x86_64

    var assetName: String {
        "swichcodex-macos-\(rawValue).dmg"
    }

    static var current: AppBinaryArchitecture {
        #if arch(arm64)
            .arm64
        #else
            .x86_64
        #endif
    }
}

struct AppReleaseAsset: Decodable, Hashable {
    let name: String
    let downloadURL: URL
    let contentType: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case downloadURL = "browser_download_url"
        case contentType = "content_type"
    }
}

struct AppReleaseInfo: Decodable, Hashable, Identifiable {
    let tagName: String
    let name: String
    let htmlURL: URL
    let body: String?
    let assets: [AppReleaseAsset]

    var id: String { tagName }

    var version: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }

    func primaryDMGAsset(for architecture: AppBinaryArchitecture) -> AppReleaseAsset? {
        assets.first { $0.name.lowercased() == architecture.assetName }
            ?? assets.first { $0.name.lowercased().hasSuffix(".dmg") && $0.name.localizedCaseInsensitiveContains(architecture.rawValue) }
    }

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case body
        case assets
    }
}

enum AppUpdateCheckResult: Hashable {
    case upToDate(currentVersion: String)
    case updateAvailable(currentVersion: String, release: AppReleaseInfo)
}
