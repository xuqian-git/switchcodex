import Foundation
import SQLite3

struct ThreadRow: Hashable {
    var id: String
    var rolloutPath: String
    var createdAt: Int64
    var updatedAt: Int64
    var source: String
    var modelProvider: String
    var cwd: String
    var title: String
    var sandboxPolicy: String
    var approvalMode: String
    var tokensUsed: Int64
    var hasUserEvent: Int64
    var archived: Int64
    var archivedAt: Int64?
    var gitSHA: String?
    var gitBranch: String?
    var gitOriginURL: String?
    var cliVersion: String?
    var firstUserMessage: String?
    var agentNickname: String?
    var agentRole: String?
    var memoryMode: String?
    var model: String?
    var reasoningEffort: String?
    var agentPath: String?
    var createdAtMS: Int64?
    var updatedAtMS: Int64?
}

enum SQLiteStoreError: Error {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
}

struct SQLiteStore: Sendable {
    func readThreads(at url: URL) throws -> [ThreadRow] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw SQLiteStoreError.openFailed(message(for: db))
        }
        defer { sqlite3_close(db) }
        let sql = try makeReadThreadsSQL(db: db)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteStoreError.prepareFailed(message(for: db))
        }
        defer { sqlite3_finalize(statement) }
        var rows: [ThreadRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(ThreadRow(
                id: string(statement, 0),
                rolloutPath: string(statement, 1),
                createdAt: sqlite3_column_int64(statement, 2),
                updatedAt: sqlite3_column_int64(statement, 3),
                source: string(statement, 4),
                modelProvider: string(statement, 5),
                cwd: string(statement, 6),
                title: string(statement, 7),
                sandboxPolicy: string(statement, 8),
                approvalMode: string(statement, 9),
                tokensUsed: sqlite3_column_int64(statement, 10),
                hasUserEvent: sqlite3_column_int64(statement, 11),
                archived: sqlite3_column_int64(statement, 12),
                archivedAt: nullableInt64(statement, 13),
                gitSHA: nullableString(statement, 14),
                gitBranch: nullableString(statement, 15),
                gitOriginURL: nullableString(statement, 16),
                cliVersion: nullableString(statement, 17),
                firstUserMessage: nullableString(statement, 18),
                agentNickname: nullableString(statement, 19),
                agentRole: nullableString(statement, 20),
                memoryMode: nullableString(statement, 21),
                model: nullableString(statement, 22),
                reasoningEffort: nullableString(statement, 23),
                agentPath: nullableString(statement, 24),
                createdAtMS: nullableInt64(statement, 25),
                updatedAtMS: nullableInt64(statement, 26)
            ))
        }
        return rows
    }

    func deleteThread(id: String, at url: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            throw SQLiteStoreError.openFailed(message(for: db))
        }
        defer { sqlite3_close(db) }
        try execute(db: db, sql: "DELETE FROM threads WHERE id = ?", bind: { stmt in
            sqlite3_bind_text(stmt, 1, id, -1, nil)
        })
    }

    func insertThread(_ row: TrashedSessionManifest.ThreadRowBackup, at url: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            throw SQLiteStoreError.openFailed(message(for: db))
        }
        defer { sqlite3_close(db) }
        let sql = """
        INSERT INTO threads (
            id, rollout_path, created_at, updated_at, source, model_provider, cwd, title,
            sandbox_policy, approval_mode, tokens_used, has_user_event, archived, archived_at,
            git_sha, git_branch, git_origin_url, cli_version, first_user_message, agent_nickname,
            agent_role, memory_mode, model, reasoning_effort, agent_path, created_at_ms, updated_at_ms
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        try execute(db: db, sql: sql) { stmt in
            bindText(row.id, stmt, 1)
            bindText(row.rolloutPath, stmt, 2)
            sqlite3_bind_int64(stmt, 3, row.createdAt)
            sqlite3_bind_int64(stmt, 4, row.updatedAt)
            bindText(row.source, stmt, 5)
            bindText(row.modelProvider, stmt, 6)
            bindText(row.cwd, stmt, 7)
            bindText(row.title, stmt, 8)
            bindText(row.sandboxPolicy, stmt, 9)
            bindText(row.approvalMode, stmt, 10)
            sqlite3_bind_int64(stmt, 11, row.tokensUsed)
            sqlite3_bind_int64(stmt, 12, row.hasUserEvent)
            sqlite3_bind_int64(stmt, 13, row.archived)
            bindInt64(row.archivedAt, stmt, 14)
            bindText(row.gitSHA, stmt, 15)
            bindText(row.gitBranch, stmt, 16)
            bindText(row.gitOriginURL, stmt, 17)
            bindText(row.cliVersion, stmt, 18)
            bindText(row.firstUserMessage, stmt, 19)
            bindText(row.agentNickname, stmt, 20)
            bindText(row.agentRole, stmt, 21)
            bindText(row.memoryMode, stmt, 22)
            bindText(row.model, stmt, 23)
            bindText(row.reasoningEffort, stmt, 24)
            bindText(row.agentPath, stmt, 25)
            bindInt64(row.createdAtMS, stmt, 26)
            bindInt64(row.updatedAtMS, stmt, 27)
        }
    }

    func threadExists(id: String, at url: URL) throws -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw SQLiteStoreError.openFailed(message(for: db))
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT 1 FROM threads WHERE id = ? LIMIT 1", -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteStoreError.prepareFailed(message(for: db))
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, id, -1, nil)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func execute(db: OpaquePointer?, sql: String, bind: (OpaquePointer?) -> Void = { _ in }) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteStoreError.prepareFailed(message(for: db))
        }
        defer { sqlite3_finalize(statement) }
        bind(statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteStoreError.stepFailed(message(for: db))
        }
    }

    private func string(_ statement: OpaquePointer?, _ index: Int32) -> String {
        String(cString: sqlite3_column_text(statement, index))
    }

    private func nullableString(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    private func nullableInt64(_ statement: OpaquePointer?, _ index: Int32) -> Int64? {
        if sqlite3_column_type(statement, index) == SQLITE_NULL { return nil }
        return sqlite3_column_int64(statement, index)
    }

    private func bindText(_ value: String?, _ statement: OpaquePointer?, _ index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, value, -1, nil)
    }

    private func bindInt64(_ value: Int64?, _ statement: OpaquePointer?, _ index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_int64(statement, index, value)
    }

    private func message(for db: OpaquePointer?) -> String {
        if let db, let cString = sqlite3_errmsg(db) {
            return String(cString: cString)
        }
        return "unknown sqlite error"
    }

    private func makeReadThreadsSQL(db: OpaquePointer?) throws -> String {
        let availableColumns = try threadColumns(in: db)
        let projections = threadColumnDefinitions.map { definition in
            availableColumns.contains(definition.name)
                ? definition.name
                : "\(definition.defaultSQL) AS \(definition.name)"
        }
        return """
        SELECT \(projections.joined(separator: ", "))
        FROM threads
        ORDER BY updated_at DESC
        """
    }

    private func threadColumns(in db: OpaquePointer?) throws -> Set<String> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(threads)", -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteStoreError.prepareFailed(message(for: db))
        }
        defer { sqlite3_finalize(statement) }

        var columns: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 1) {
                columns.insert(String(cString: name))
            }
        }
        return columns
    }
}

private struct ThreadColumnDefinition {
    let name: String
    let defaultSQL: String
}

private let threadColumnDefinitions: [ThreadColumnDefinition] = [
    .init(name: "id", defaultSQL: "''"),
    .init(name: "rollout_path", defaultSQL: "''"),
    .init(name: "created_at", defaultSQL: "0"),
    .init(name: "updated_at", defaultSQL: "0"),
    .init(name: "source", defaultSQL: "''"),
    .init(name: "model_provider", defaultSQL: "''"),
    .init(name: "cwd", defaultSQL: "''"),
    .init(name: "title", defaultSQL: "''"),
    .init(name: "sandbox_policy", defaultSQL: "''"),
    .init(name: "approval_mode", defaultSQL: "''"),
    .init(name: "tokens_used", defaultSQL: "0"),
    .init(name: "has_user_event", defaultSQL: "0"),
    .init(name: "archived", defaultSQL: "0"),
    .init(name: "archived_at", defaultSQL: "NULL"),
    .init(name: "git_sha", defaultSQL: "NULL"),
    .init(name: "git_branch", defaultSQL: "NULL"),
    .init(name: "git_origin_url", defaultSQL: "NULL"),
    .init(name: "cli_version", defaultSQL: "''"),
    .init(name: "first_user_message", defaultSQL: "''"),
    .init(name: "agent_nickname", defaultSQL: "NULL"),
    .init(name: "agent_role", defaultSQL: "NULL"),
    .init(name: "memory_mode", defaultSQL: "'enabled'"),
    .init(name: "model", defaultSQL: "NULL"),
    .init(name: "reasoning_effort", defaultSQL: "NULL"),
    .init(name: "agent_path", defaultSQL: "NULL"),
    .init(name: "created_at_ms", defaultSQL: "NULL"),
    .init(name: "updated_at_ms", defaultSQL: "NULL")
]

extension SQLiteStoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .openFailed(message):
            return "SQLite 打开失败：\(message)"
        case let .prepareFailed(message):
            return "SQLite 查询准备失败：\(message)"
        case let .stepFailed(message):
            return "SQLite 执行失败：\(message)"
        }
    }
}
