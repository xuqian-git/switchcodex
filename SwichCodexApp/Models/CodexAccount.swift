import Foundation

enum CodexAccountAuthMode: String, Codable, Hashable {
    case chatgpt
    case apikey
    case unknown
}

struct CodexAccountTokens: Codable, Hashable {
    var idToken: String?
    var accessToken: String?
    var refreshToken: String?
    var accountID: String?

    init(
        idToken: String? = nil,
        accessToken: String? = nil,
        refreshToken: String? = nil,
        accountID: String? = nil
    ) {
        self.idToken = idToken
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accountID = accountID
    }
}

struct CodexQuota: Codable, Hashable {
    var hourlyPercentage: Int
    var hourlyResetTime: TimeInterval?
    var hourlyWindowMinutes: Int?
    var hourlyWindowPresent: Bool?
    var weeklyPercentage: Int
    var weeklyResetTime: TimeInterval?
    var weeklyWindowMinutes: Int?
    var weeklyWindowPresent: Bool?
    var rawDataJSON: String?
}

struct CodexQuotaErrorInfo: Codable, Hashable {
    var code: String?
    var message: String
    var timestamp: Date
}

struct CodexAccount: Codable, Identifiable, Hashable {
    var id: String
    var email: String
    var displayName: String?
    var authMode: CodexAccountAuthMode
    var planType: String?
    var authFilePlanType: String?
    var userID: String?
    var accountID: String?
    var organizationID: String?
    var accountName: String?
    var accountStructure: String?
    var teamName: String?
    var tags: [String]
    var quota: CodexQuota?
    var quotaError: CodexQuotaErrorInfo?
    var createdAt: Date
    var lastUsedAt: Date
    var lastRefreshedAt: Date?
    var isCurrent: Bool
    var apiBaseURL: String?
    var apiProviderMode: String?
    var apiProviderID: String?
    var apiProviderName: String?
    var apiKeyPreview: String?
    var rawAuthJSON: String
    var tokens: CodexAccountTokens

    init(
        id: String,
        email: String,
        displayName: String?,
        authMode: CodexAccountAuthMode,
        planType: String?,
        authFilePlanType: String?,
        userID: String?,
        accountID: String?,
        organizationID: String?,
        accountName: String?,
        accountStructure: String?,
        teamName: String?,
        tags: [String],
        quota: CodexQuota?,
        quotaError: CodexQuotaErrorInfo?,
        createdAt: Date,
        lastUsedAt: Date,
        lastRefreshedAt: Date?,
        isCurrent: Bool,
        apiBaseURL: String?,
        apiProviderMode: String?,
        apiProviderID: String?,
        apiProviderName: String?,
        apiKeyPreview: String?,
        rawAuthJSON: String,
        tokens: CodexAccountTokens
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.authMode = authMode
        self.planType = planType
        self.authFilePlanType = authFilePlanType
        self.userID = userID
        self.accountID = accountID
        self.organizationID = organizationID
        self.accountName = accountName
        self.accountStructure = accountStructure
        self.teamName = teamName
        self.tags = tags
        self.quota = quota
        self.quotaError = quotaError
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.lastRefreshedAt = lastRefreshedAt
        self.isCurrent = isCurrent
        self.apiBaseURL = apiBaseURL
        self.apiProviderMode = apiProviderMode
        self.apiProviderID = apiProviderID
        self.apiProviderName = apiProviderName
        self.apiKeyPreview = apiKeyPreview
        self.rawAuthJSON = rawAuthJSON
        self.tokens = tokens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let now = Date()
        id = try container.decode(String.self, forKey: .id)
        email = try container.decode(String.self, forKey: .email)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        authMode = try container.decodeIfPresent(CodexAccountAuthMode.self, forKey: .authMode) ?? .unknown
        planType = try container.decodeIfPresent(String.self, forKey: .planType)
        authFilePlanType = try container.decodeIfPresent(String.self, forKey: .authFilePlanType)
        userID = try container.decodeIfPresent(String.self, forKey: .userID)
        accountID = try container.decodeIfPresent(String.self, forKey: .accountID)
        organizationID = try container.decodeIfPresent(String.self, forKey: .organizationID)
        accountName = try container.decodeIfPresent(String.self, forKey: .accountName)
        accountStructure = try container.decodeIfPresent(String.self, forKey: .accountStructure)
        teamName = try container.decodeIfPresent(String.self, forKey: .teamName)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        quota = try container.decodeIfPresent(CodexQuota.self, forKey: .quota)
        quotaError = try container.decodeIfPresent(CodexQuotaErrorInfo.self, forKey: .quotaError)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? now
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt) ?? createdAt
        lastRefreshedAt = try container.decodeIfPresent(Date.self, forKey: .lastRefreshedAt)
        isCurrent = try container.decodeIfPresent(Bool.self, forKey: .isCurrent) ?? false
        apiBaseURL = try container.decodeIfPresent(String.self, forKey: .apiBaseURL)
        apiProviderMode = try container.decodeIfPresent(String.self, forKey: .apiProviderMode)
        apiProviderID = try container.decodeIfPresent(String.self, forKey: .apiProviderID)
        apiProviderName = try container.decodeIfPresent(String.self, forKey: .apiProviderName)
        apiKeyPreview = try container.decodeIfPresent(String.self, forKey: .apiKeyPreview)
        rawAuthJSON = try container.decodeIfPresent(String.self, forKey: .rawAuthJSON) ?? ""
        tokens = try container.decodeIfPresent(CodexAccountTokens.self, forKey: .tokens) ?? CodexAccountTokens()
    }

    var resolvedDisplayName: String {
        if authMode == .apikey, let accountName, !accountName.isEmpty { return accountName }
        if let displayName, !displayName.isEmpty { return displayName }
        if !email.isEmpty { return email }
        return id
    }
}
