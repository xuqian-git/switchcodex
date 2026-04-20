import Foundation

enum Masking {
    static func maskEmail(_ email: String) -> String {
        let parts = email.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return email }
        let name = parts[0]
        let domain = parts[1]
        if name.count <= 2 {
            return "\(name.prefix(1))***@\(domain)"
        }
        return "\(name.prefix(2))***\(name.suffix(1))@\(domain)"
    }
}

