import Foundation

struct CodexAccountQuotaPresentation: Identifiable, Hashable {
    let id: String
    let label: String
    let percentage: Int
    let valueText: String
    let resetText: String?
    let tone: CodexQuotaTone
}

enum CodexQuotaTone: Hashable {
    case high
    case medium
    case low
    case critical
}

struct CodexAccountCardPresentation: Hashable {
    let title: String
    let subtitle: String
    let planLabel: String
    let planTone: CodexPlanTone
    let contextLine: String?
    let identityLine: String?
    let apiKeyLine: String?
    let providerLine: String?
    let baseURLLine: String?
    let quotaErrorLine: String?
    let quotaItems: [CodexAccountQuotaPresentation]
    let footerLine: String
    let tags: [String]
}

enum CodexPlanTone: Hashable {
    case free
    case plus
    case pro
    case team
    case enterprise
    case neutral
}

enum CodexAccountPresentation {
    static func make(for account: CodexAccount, hideEmail: Bool) -> CodexAccountCardPresentation {
        let title = account.resolvedDisplayName
        let subtitle = hideEmail ? Masking.maskEmail(account.email) : account.email
        let planLabel = planBadgeLabel(for: account)
        let footerLine = "最近刷新：\(formatDate(account.lastRefreshedAt ?? account.createdAt))"

        if account.authMode == .apikey {
            return CodexAccountCardPresentation(
                title: title,
                subtitle: subtitle,
                planLabel: planLabel,
                planTone: planTone(for: account),
                contextLine: account.accountName ?? account.accountStructure,
                identityLine: nil,
                apiKeyLine: "API Key：\(account.apiKeyPreview ?? "未记录")",
                providerLine: "供应商：\(account.apiProviderName ?? "OpenAI")",
                baseURLLine: "Base URL：\((account.apiBaseURL?.isEmpty == false ? account.apiBaseURL! : "默认"))",
                quotaErrorLine: account.quotaError?.message,
                quotaItems: [],
                footerLine: footerLine,
                tags: account.tags
            )
        }

        let provider = loginProviderText(from: account)
        let accountIDLabel = account.accountID?.isEmpty == false ? "Account ID" : "User ID"
        let accountIDValue = account.accountID ?? account.userID ?? "暂无"
        let contextLine = account.teamName ?? account.accountStructure ?? account.accountName

        return CodexAccountCardPresentation(
            title: title,
            subtitle: subtitle,
            planLabel: planLabel,
            planTone: planTone(for: account),
            contextLine: contextLine.map { "Team Name：\($0)" },
            identityLine: "登录方式：\(provider) | \(accountIDLabel)：\(accountIDValue)",
            apiKeyLine: nil,
            providerLine: nil,
            baseURLLine: nil,
            quotaErrorLine: account.quotaError?.message,
            quotaItems: quotaItems(from: account.quota),
            footerLine: footerLine,
            tags: account.tags
        )
    }

    static func planBadgeLabel(for account: CodexAccount) -> String {
        let base = planLabel(planType: account.planType, authMode: account.authMode)
        guard normalizePlan(account.planType) == "pro" else { return base }
        let normalizedAuthFile = (account.authFilePlanType ?? account.planType ?? "")
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        if normalizedAuthFile == "prolite" { return "\(base) 5x" }
        if normalizedAuthFile == "promax" { return "\(base) 20x" }
        return base
    }

    static func planTone(for account: CodexAccount) -> CodexPlanTone {
        let normalized = normalizePlan(account.planType)
        switch normalized {
        case "free":
            return .free
        case "plus":
            return .plus
        case "pro":
            return .pro
        case "team", "business", "edu":
            return .team
        case "enterprise":
            return .enterprise
        default:
            return account.authMode == .apikey ? .neutral : .free
        }
    }

    static func quotaItems(from quota: CodexQuota?) -> [CodexAccountQuotaPresentation] {
        guard let quota else { return [] }
        var items = [CodexAccountQuotaPresentation(
            id: "primary",
            label: quotaWindowLabel(minutes: quota.hourlyWindowMinutes, fallback: "5h"),
            percentage: quota.hourlyPercentage,
            valueText: "\(quota.hourlyPercentage)%",
            resetText: formatResetTime(quota.hourlyResetTime),
            tone: quotaTone(quota.hourlyPercentage)
        )]

        if quota.weeklyWindowPresent != false {
            items.append(
                CodexAccountQuotaPresentation(
                    id: "secondary",
                    label: quotaWindowLabel(minutes: quota.weeklyWindowMinutes, fallback: "Weekly"),
                    percentage: quota.weeklyPercentage,
                    valueText: "\(quota.weeklyPercentage)%",
                    resetText: formatResetTime(quota.weeklyResetTime),
                    tone: quotaTone(quota.weeklyPercentage)
                )
            )
        }

        if let codeReviewItem = codeReviewQuotaItem(from: quota.rawDataJSON) {
            items.append(codeReviewItem)
        }

        return items
    }

    private static func planLabel(planType: String?, authMode: CodexAccountAuthMode) -> String {
        if authMode == .apikey { return "API KEY" }
        let normalized = normalizePlan(planType)
        switch normalized {
        case "team":
            return "TEAM"
        case "enterprise":
            return "ENTERPRISE"
        case "plus":
            return "PLUS"
        case "pro":
            return "PRO"
        case "business":
            return "BUSINESS"
        case "edu":
            return "EDU"
        default:
            return "FREE"
        }
    }

    private static func normalizePlan(_ value: String?) -> String {
        let normalized = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("enterprise") { return "enterprise" }
        if normalized.contains("business") { return "business" }
        if normalized.contains("team") { return "team" }
        if normalized.contains("edu") { return "edu" }
        if normalized.contains("plus") { return "plus" }
        if normalized.contains("pro") { return "pro" }
        if normalized.contains("free") { return "free" }
        return normalized
    }

    private static func loginProviderText(from account: CodexAccount) -> String {
        switch account.authMode {
        case .apikey:
            return "API Key"
        case .chatgpt:
            let idTokenPayload = decodeJWT(account.tokens.idToken)
            let provider = (idTokenPayload?["auth_provider"] as? String)?.lowercased()
            switch provider {
            case "google": return "Google"
            case "github": return "GitHub"
            case "microsoft": return "Microsoft"
            case "apple": return "Apple"
            case "password": return "Password"
            default: return "ChatGPT"
            }
        case .unknown:
            return "未知"
        }
    }

    private static func quotaWindowLabel(minutes: Int?, fallback: String) -> String {
        guard let minutes, minutes > 0 else { return fallback }
        if minutes >= 7 * 24 * 60 { return "Weekly" }
        if minutes >= 24 * 60 { return "\(Int(ceil(Double(minutes) / 1440.0)))d" }
        if minutes >= 60 { return "\(Int(ceil(Double(minutes) / 60.0)))h" }
        return "\(minutes)m"
    }

    private static func quotaTone(_ percentage: Int) -> CodexQuotaTone {
        switch percentage {
        case 80...100: return .high
        case 40..<80: return .medium
        case 10..<40: return .low
        default: return .critical
        }
    }

    private static func formatResetTime(_ unixSeconds: TimeInterval?) -> String? {
        guard let unixSeconds, unixSeconds > 0 else { return nil }
        let date = Date(timeIntervalSince1970: unixSeconds)
        return "重置：\(formatDate(date))"
    }

    private static func formatDate(_ value: Date) -> String {
        value.formatted(date: .abbreviated, time: .shortened)
    }

    private static func codeReviewQuotaItem(from rawDataJSON: String?) -> CodexAccountQuotaPresentation? {
        guard let rawDataJSON,
              let data = rawDataJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rateLimit = object["code_review_rate_limit"] as? [String: Any] else {
            return nil
        }

        let window = (rateLimit["primary_window"] as? [String: Any]) ?? (rateLimit["secondary_window"] as? [String: Any])
        guard let window else { return nil }

        let usedPercent = parseNumber(window["used_percent"]) ?? 0
        let percentage = max(0, min(100, 100 - Int(usedPercent.rounded())))
        let windowMinutes = parseNumber(window["limit_window_seconds"]).flatMap { value -> Int? in
            guard value > 0 else { return nil }
            return Int(ceil(value / 60))
        }

        return CodexAccountQuotaPresentation(
            id: "code-review",
            label: quotaWindowLabel(minutes: windowMinutes, fallback: "Code Review"),
            percentage: percentage,
            valueText: "\(percentage)%",
            resetText: nil,
            tone: quotaTone(percentage)
        )
    }

    private static func parseNumber(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func decodeJWT(_ value: String?) -> [String: Any]? {
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
