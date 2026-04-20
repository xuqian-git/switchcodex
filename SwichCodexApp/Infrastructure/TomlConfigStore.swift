import Foundation

struct CodexQuickConfig {
    var contextWindow1M: Bool
    var autoCompactTokenLimit: Int?
}

struct TomlConfigStore: Sendable {
    func readQuickConfig(from url: URL) -> CodexQuickConfig {
        guard let content = try? String(contentsOf: url) else {
            return CodexQuickConfig(contextWindow1M: false, autoCompactTokenLimit: nil)
        }
        let window = extractInteger(for: "model_context_window", content: content)
        let limit = extractInteger(for: "model_auto_compact_token_limit", content: content)
        return CodexQuickConfig(contextWindow1M: window == 1_000_000, autoCompactTokenLimit: limit)
    }

    private func extractInteger(for key: String, content: String) -> Int? {
        let pattern = #"(?m)^\#(key)\s*=\s*(\d+)\s*$"#
            .replacingOccurrences(of: "#(key)", with: NSRegularExpression.escapedPattern(for: key))
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        guard let match = regex.firstMatch(in: content, range: range),
              let valueRange = Range(match.range(at: 1), in: content) else { return nil }
        return Int(content[valueRange])
    }
}
