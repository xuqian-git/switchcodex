import Foundation
import CryptoKit

struct CodexAccountService: CodexAccountServicing, @unchecked Sendable {
    private static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    private let fileStore: FileStore
    private let backupService: BackupService
    private let mutationCoordinator: DirectoryMutationCoordinator

    init(fileStore: FileStore, backupService: BackupService, mutationCoordinator: DirectoryMutationCoordinator) {
        self.fileStore = fileStore
        self.backupService = backupService
        self.mutationCoordinator = mutationCoordinator
    }

    func listAccounts() async throws -> [CodexAccount] {
        try AppPaths.ensureBaseDirectories()
        var accounts = (try? fileStore.readJSON([CodexAccount].self, at: AppPaths.accountsURL)) ?? []
        if fileStore.fileExists(AppPaths.authURL) {
            let current = try parseAccount(from: AppPaths.authURL)
            accounts = merge(current, into: accounts)
            try fileStore.writeJSON(accounts, to: AppPaths.accountsURL)
        }
        return accounts.sorted { lhs, rhs in
            if lhs.isCurrent != rhs.isCurrent { return lhs.isCurrent && !rhs.isCurrent }
            return lhs.resolvedDisplayName.localizedStandardCompare(rhs.resolvedDisplayName) == .orderedAscending
        }
    }

    func account(for id: String) async throws -> CodexAccount? {
        try await listAccounts().first(where: { $0.id == id })
    }

    func importFromLocalAuth() async throws -> CodexAccount {
        let account = try parseAccount(from: AppPaths.authURL)
        let accounts = merge(account, into: (try? await listAccounts()) ?? [])
        try fileStore.writeJSON(accounts, to: AppPaths.accountsURL)
        return account
    }

    func importFromTokens(idToken: String, accessToken: String, refreshToken: String?) async throws -> CodexAccount {
        let payload: [String: Any?] = [
            "auth_mode": "chatgpt",
            "OPENAI_API_KEY": nil,
            "tokens": [
                "id_token": idToken,
                "access_token": accessToken,
                "refresh_token": refreshToken,
                "account_id": decodeJWT(idToken)?["https://api.openai.com/auth"].flatMap { $0 as? [String: Any] }?["chatgpt_account_id"] as? String
            ],
            "last_refresh": ISO8601DateFormatter().string(from: Date())
        ]
        let data = try JSONSerialization.data(withJSONObject: payload.compactMapValues { $0 }, options: [.prettyPrinted, .sortedKeys])
        let temp = AppPaths.applicationSupport.appendingPathComponent("token-import-\(UUID().uuidString).json")
        try fileStore.writeData(data, to: temp)
        defer { try? fileStore.removeItem(at: temp) }
        let account = try parseAccount(from: temp)
        let accounts = merge(account, into: (try? await listAccounts()) ?? [])
        try fileStore.writeJSON(accounts, to: AppPaths.accountsURL)
        return account
    }

    func importFromAPIKey(apiKey: String, baseURL: String?) async throws -> CodexAccount {
        let payload: [String: Any] = [
            "auth_mode": "apikey",
            "OPENAI_API_KEY": apiKey,
            "api_base_url": baseURL as Any
        ]
        let data = try JSONSerialization.data(withJSONObject: payload.compactMapValues { $0 }, options: [.prettyPrinted, .sortedKeys])
        let temp = AppPaths.applicationSupport.appendingPathComponent("apikey-import-\(UUID().uuidString).json")
        try fileStore.writeData(data, to: temp)
        defer { try? fileStore.removeItem(at: temp) }
        let account = try parseAccount(from: temp)
        let accounts = merge(account, into: (try? await listAccounts()) ?? [])
        try fileStore.writeJSON(accounts, to: AppPaths.accountsURL)
        return account
    }

    func importAccounts(from url: URL) async throws -> Int {
        try AppPaths.ensureBaseDirectories()
        let imported = try fileStore.readJSON([CodexAccount].self, at: url)
        guard !imported.isEmpty else { return 0 }

        let existing = try await listAccounts()
        let currentAccountID = existing.first(where: \.isCurrent)?.id
        var merged = existing

        for account in imported {
            var normalized = account
            normalized.isCurrent = currentAccountID == account.id
            merged = merge(normalized, into: merged)
        }

        try fileStore.writeJSON(merged, to: AppPaths.accountsURL)
        return imported.count
    }

    func exportAccounts(ids: [String], to url: URL) async throws {
        let idSet = Set(ids)
        let accounts = try await listAccounts().filter { idSet.contains($0.id) }
        try fileStore.writeJSON(accounts, to: url)
    }

    func switchAccount(id: String) async throws -> OperationFeedback {
        guard let account = try await account(for: id) else {
            return OperationFeedback(level: .error, message: "未找到要切换的账号。")
        }
        _ = try backupService.backup(urls: [AppPaths.authURL], operation: "switch-account")
        try mutationCoordinator.perform(directory: AppPaths.codexHome) {
            try fileStore.writeString(account.rawAuthJSON, to: AppPaths.authURL)
            var accounts = (try? fileStore.readJSON([CodexAccount].self, at: AppPaths.accountsURL)) ?? []
            accounts = accounts.map {
                var value = $0
                value.isCurrent = value.id == id
                return value
            }
            try fileStore.writeJSON(accounts, to: AppPaths.accountsURL)
        }
        return OperationFeedback(level: .success, message: "已切换到 \(account.resolvedDisplayName)。")
    }

    func refreshAccount(id: String) async throws -> CodexAccount {
        var accounts = try await listAccounts()
        guard let index = accounts.firstIndex(where: { $0.id == id }) else {
            throw NSError(domain: "SwichCodex", code: 404, userInfo: [NSLocalizedDescriptionKey: "账号不存在"])
        }
        if accounts[index].isCurrent, fileStore.fileExists(AppPaths.authURL) {
            accounts[index] = preserveMetadata(from: accounts[index], overridingWith: try parseAccount(from: AppPaths.authURL))
        }
        accounts[index] = try await refreshQuotaIfPossible(for: accounts[index])
        try fileStore.writeJSON(accounts, to: AppPaths.accountsURL)
        return accounts[index]
    }

    func refreshAllAccounts() async throws -> [CodexAccount] {
        let accounts = try await listAccounts()
        for account in accounts {
            _ = try await refreshAccount(id: account.id)
        }
        return try await listAccounts()
    }

    func deleteAccounts(ids: [String]) async throws -> Int {
        let idSet = Set(ids)
        guard !idSet.isEmpty else { return 0 }

        let accounts = try await listAccounts()
        let deletedAccounts = accounts.filter { idSet.contains($0.id) }
        guard !deletedAccounts.isEmpty else { return 0 }

        let deletingCurrent = deletedAccounts.contains(where: \.isCurrent)
        var remainingAccounts = accounts.filter { !idSet.contains($0.id) }

        try mutationCoordinator.perform(directory: AppPaths.codexHome) {
            if deletingCurrent {
                _ = try backupService.backup(urls: [AppPaths.authURL], operation: "delete-account")

                if !remainingAccounts.isEmpty {
                    for index in remainingAccounts.indices {
                        remainingAccounts[index].isCurrent = false
                    }
                    remainingAccounts[0].isCurrent = true
                    try fileStore.writeString(remainingAccounts[0].rawAuthJSON, to: AppPaths.authURL)
                } else if fileStore.fileExists(AppPaths.authURL) {
                    try fileStore.removeItem(at: AppPaths.authURL)
                }
            }

            try fileStore.writeJSON(remainingAccounts, to: AppPaths.accountsURL)
        }

        return deletedAccounts.count
    }

    private func merge(_ current: CodexAccount, into accounts: [CodexAccount]) -> [CodexAccount] {
        let existing = accounts.first(where: { $0.id == current.id })
        let hydratedCurrent = preserveMetadata(from: existing, overridingWith: current)
        var values = accounts.filter { $0.id != current.id }.map {
            var value = $0
            value.isCurrent = false
            return value
        }
        values.append(hydratedCurrent)
        return values
    }

    private func parseAccount(from url: URL) throws -> CodexAccount {
        let raw = try fileStore.readString(at: url)
        guard let json = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] else {
            throw NSError(domain: "SwichCodex", code: 1, userInfo: [NSLocalizedDescriptionKey: "auth.json 解析失败"])
        }
        let authMode = CodexAccountAuthMode(rawValue: (json["auth_mode"] as? String ?? "").lowercased()) ?? .unknown
        let apiKey = json["OPENAI_API_KEY"] as? String
        let tokensObject = json["tokens"] as? [String: Any]
        let idToken = tokensObject?["id_token"] as? String
        let accessToken = tokensObject?["access_token"] as? String
        let refreshToken = tokensObject?["refresh_token"] as? String
        let accountID = tokensObject?["account_id"] as? String

        let payload = decodeJWT(idToken) ?? decodeJWT(accessToken)
        let authPayload = payload?["https://api.openai.com/auth"] as? [String: Any]
        let profilePayload = payload?["https://api.openai.com/profile"] as? [String: Any]
        let createdAt = Date()
        let email = (payload?["email"] as? String)
            ?? (profilePayload?["email"] as? String)
            ?? buildFallbackEmail(apiKey: apiKey)
        let displayName = payload?["name"] as? String
        let planType = authPayload?["chatgpt_plan_type"] as? String
        let authFilePlanType = (json["auth_file_plan_type"] as? String) ?? (json["plan_type"] as? String)
        let orgs = authPayload?["organizations"] as? [[String: Any]]
        let defaultOrg = orgs?.first(where: { ($0["is_default"] as? Bool) == true }) ?? orgs?.first
        let teamName = defaultOrg?["title"] as? String
        let organizationID = (defaultOrg?["id"] as? String) ?? (defaultOrg?["organization_id"] as? String)
        let accountStructure = buildAccountStructure(orgs: orgs)
        let userID = (authPayload?["chatgpt_user_id"] as? String)
            ?? (authPayload?["user_id"] as? String)
            ?? (payload?["sub"] as? String)
        let id = accountID
            ?? authPayload?["chatgpt_account_id"] as? String
            ?? stableAccountID(for: raw, email: email)
        let refreshDate = (json["last_refresh"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()

        return CodexAccount(
            id: id,
            email: email,
            displayName: displayName,
            authMode: authMode,
            planType: planType,
            authFilePlanType: authFilePlanType,
            userID: userID,
            accountID: accountID ?? (authPayload?["chatgpt_account_id"] as? String),
            organizationID: organizationID,
            accountName: json["account_name"] as? String,
            accountStructure: accountStructure,
            teamName: teamName,
            tags: [],
            quota: nil,
            quotaError: nil,
            createdAt: createdAt,
            lastUsedAt: createdAt,
            lastRefreshedAt: refreshDate,
            isCurrent: url.standardizedFileURL == AppPaths.authURL.standardizedFileURL,
            apiBaseURL: json["api_base_url"] as? String,
            apiProviderMode: json["api_provider_mode"] as? String,
            apiProviderID: json["api_provider_id"] as? String,
            apiProviderName: json["api_provider_name"] as? String,
            apiKeyPreview: maskAPIKey(apiKey),
            rawAuthJSON: raw,
            tokens: CodexAccountTokens(idToken: idToken, accessToken: accessToken, refreshToken: refreshToken, accountID: accountID)
        )
    }

    private func preserveMetadata(from existing: CodexAccount?, overridingWith current: CodexAccount) -> CodexAccount {
        guard let existing else { return current }
        return CodexAccount(
            id: current.id,
            email: current.email,
            displayName: current.displayName ?? existing.displayName,
            authMode: current.authMode,
            planType: current.planType ?? existing.planType,
            authFilePlanType: current.authFilePlanType ?? existing.authFilePlanType,
            userID: current.userID ?? existing.userID,
            accountID: current.accountID ?? existing.accountID,
            organizationID: current.organizationID ?? existing.organizationID,
            accountName: current.accountName ?? existing.accountName,
            accountStructure: current.accountStructure ?? existing.accountStructure,
            teamName: current.teamName ?? existing.teamName,
            tags: existing.tags,
            quota: existing.quota,
            quotaError: existing.quotaError,
            createdAt: existing.createdAt,
            lastUsedAt: current.isCurrent ? Date() : existing.lastUsedAt,
            lastRefreshedAt: current.lastRefreshedAt ?? existing.lastRefreshedAt,
            isCurrent: current.isCurrent,
            apiBaseURL: current.apiBaseURL ?? existing.apiBaseURL,
            apiProviderMode: current.apiProviderMode ?? existing.apiProviderMode,
            apiProviderID: current.apiProviderID ?? existing.apiProviderID,
            apiProviderName: current.apiProviderName ?? existing.apiProviderName,
            apiKeyPreview: current.apiKeyPreview ?? existing.apiKeyPreview,
            rawAuthJSON: current.rawAuthJSON,
            tokens: current.tokens
        )
    }

    private func refreshQuotaIfPossible(for account: CodexAccount) async throws -> CodexAccount {
        var updated = account
        updated.lastRefreshedAt = Date()

        guard account.authMode != .apikey else {
            updated.quotaError = nil
            return updated
        }

        guard let accessToken = account.tokens.accessToken, !accessToken.isEmpty else {
            updated.quotaError = CodexQuotaErrorInfo(
                code: "missing_access_token",
                message: "缺少 access token，无法读取配额。",
                timestamp: Date()
            )
            return updated
        }

        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        if let accountID = account.accountID ?? account.tokens.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "SwichCodex", code: 1, userInfo: [NSLocalizedDescriptionKey: "配额接口响应异常"])
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                let body = String(decoding: data, as: UTF8.self)
                let errorCode = extractQuotaErrorCode(from: body)
                let message = if let errorCode {
                    "配额接口返回 \(httpResponse.statusCode) [\(errorCode)]"
                } else {
                    "配额接口返回 \(httpResponse.statusCode)"
                }
                updated.quotaError = CodexQuotaErrorInfo(code: errorCode, message: message, timestamp: Date())
                return updated
            }

            let usage = try JSONDecoder().decode(UsageResponse.self, from: data)
            updated.quota = buildQuota(from: usage, rawData: data)
            updated.quotaError = nil
            updated.planType = usage.planType ?? updated.planType
            return updated
        } catch {
            updated.quotaError = CodexQuotaErrorInfo(code: nil, message: error.localizedDescription, timestamp: Date())
            return updated
        }
    }

    private func buildQuota(from usage: UsageResponse, rawData: Data) -> CodexQuota {
        let primaryWindow = usage.rateLimit?.primaryWindow
        let secondaryWindow = usage.rateLimit?.secondaryWindow

        return CodexQuota(
            hourlyPercentage: primaryWindow.map(remainingPercentage(from:)) ?? 100,
            hourlyResetTime: primaryWindow.flatMap(resetTime(from:)),
            hourlyWindowMinutes: primaryWindow.flatMap(windowMinutes(from:)),
            hourlyWindowPresent: primaryWindow != nil,
            weeklyPercentage: secondaryWindow.map(remainingPercentage(from:)) ?? 100,
            weeklyResetTime: secondaryWindow.flatMap(resetTime(from:)),
            weeklyWindowMinutes: secondaryWindow.flatMap(windowMinutes(from:)),
            weeklyWindowPresent: secondaryWindow != nil,
            rawDataJSON: String(data: rawData, encoding: .utf8)
        )
    }

    private func remainingPercentage(from window: UsageWindow) -> Int {
        let used = min(max(window.usedPercent ?? 0, 0), 100)
        return 100 - used
    }

    private func windowMinutes(from window: UsageWindow) -> Int? {
        guard let seconds = window.limitWindowSeconds, seconds > 0 else { return nil }
        return Int((seconds + 59) / 60)
    }

    private func resetTime(from window: UsageWindow) -> TimeInterval? {
        if let resetAt = window.resetAt {
            return TimeInterval(resetAt)
        }

        guard let resetAfterSeconds = window.resetAfterSeconds, resetAfterSeconds >= 0 else {
            return nil
        }

        return Date().timeIntervalSince1970 + TimeInterval(resetAfterSeconds)
    }

    private func extractQuotaErrorCode(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let detail = object["detail"] as? [String: Any], let code = detail["code"] as? String {
            return code
        }

        if let error = object["error"] as? [String: Any], let code = error["code"] as? String {
            return code
        }

        return object["code"] as? String
    }

    private func buildAccountStructure(orgs: [[String: Any]]?) -> String? {
        guard let orgs, !orgs.isEmpty else { return nil }
        let titles = orgs.compactMap { $0["title"] as? String }.filter { !$0.isEmpty }
        guard !titles.isEmpty else { return nil }
        return Array(titles.prefix(2)).joined(separator: " · ")
    }

    private func buildFallbackEmail(apiKey: String?) -> String {
        guard let apiKey, !apiKey.isEmpty else { return "unknown@local" }
        let digest = Insecure.MD5.hash(data: Data(apiKey.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return "api-key-\(hash.prefix(8))@local"
    }

    private func maskAPIKey(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        if value.count <= 10 { return value }
        return "\(value.prefix(6))••••\(value.suffix(4))"
    }

    private func stableAccountID(for raw: String, email: String) -> String {
        let digest = Insecure.MD5.hash(data: Data("\(email)|\(raw)".utf8))
        return "codex-\(digest.map { String(format: "%02x", $0) }.joined())"
    }

    private func decodeJWT(_ value: String?) -> [String: Any]? {
        guard let value else { return nil }
        let parts = value.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
        let remainder = payload.count % 4
        if remainder != 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }
        payload = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }
}

private struct UsageResponse: Decodable {
    let planType: String?
    let rateLimit: UsageRateLimit?
    let codeReviewRateLimit: UsageRateLimit?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case codeReviewRateLimit = "code_review_rate_limit"
    }
}

private struct UsageRateLimit: Decodable {
    let primaryWindow: UsageWindow?
    let secondaryWindow: UsageWindow?

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

private struct UsageWindow: Decodable {
    let usedPercent: Int?
    let limitWindowSeconds: Int?
    let resetAfterSeconds: Int?
    let resetAt: Int?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAfterSeconds = "reset_after_seconds"
        case resetAt = "reset_at"
    }
}
