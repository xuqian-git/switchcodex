import Foundation

struct FileStore: @unchecked Sendable {
    private let fm = FileManager.default

    func ensureParentDirectory(for url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    func readData(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func writeData(_ data: Data, to url: URL) throws {
        try ensureParentDirectory(for: url)
        try AtomicWriter.write(data: data, to: url)
    }

    func readString(at url: URL) throws -> String {
        try String(decoding: readData(at: url), as: UTF8.self)
    }

    func writeString(_ value: String, to url: URL) throws {
        try writeData(Data(value.utf8), to: url)
    }

    func readJSON<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
        let data = try readData(at: url)
        return try JSONDecoder.swichCodex.decode(T.self, from: data)
    }

    func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try JSONEncoder.swichCodex.encode(value)
        try writeData(data, to: url)
    }

    func fileExists(_ url: URL) -> Bool {
        fm.fileExists(atPath: url.path)
    }

    func createDirectory(_ url: URL) throws {
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func removeItem(at url: URL) throws {
        try fm.removeItem(at: url)
    }

    func copyItem(at source: URL, to target: URL) throws {
        try ensureParentDirectory(for: target)
        if fileExists(target) {
            try removeItem(at: target)
        }
        try fm.copyItem(at: source, to: target)
    }

    func moveItem(at source: URL, to target: URL) throws {
        try ensureParentDirectory(for: target)
        if fileExists(target) {
            try removeItem(at: target)
        }
        try fm.moveItem(at: source, to: target)
    }
}

extension JSONDecoder {
    static let swichCodex: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension JSONEncoder {
    static let swichCodex: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
