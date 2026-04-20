import Foundation

struct AccountGroup: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var sortOrder: Int
    var accountIDs: [String]
    var createdAt: Date
}

