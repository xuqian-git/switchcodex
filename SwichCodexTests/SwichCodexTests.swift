import XCTest
@testable import SwichCodex
import SQLite3

final class SwichCodexTests: XCTestCase {
    func testMaskEmail() {
        XCTAssertEqual(Masking.maskEmail("hello@example.com"), "he***o@example.com")
    }

    func testAccountGroupCodable() throws {
        let group = AccountGroup(id: "1", name: "A", sortOrder: 1, accountIDs: ["x"], createdAt: Date(timeIntervalSince1970: 0))
        let data = try JSONEncoder.swichCodex.encode(group)
        let decoded = try JSONDecoder.swichCodex.decode(AccountGroup.self, from: data)
        XCTAssertEqual(group.id, decoded.id)
        XCTAssertEqual(group.name, decoded.name)
        XCTAssertEqual(group.accountIDs, decoded.accountIDs)
    }

    func testInstanceStoreCodable() throws {
        let store = InstanceStore.empty
        let data = try JSONEncoder.swichCodex.encode(store)
        let decoded = try JSONDecoder.swichCodex.decode(InstanceStore.self, from: data)
        XCTAssertEqual(decoded.defaultSettings.followCurrentAccount, true)
        XCTAssertTrue(decoded.managedInstances.isEmpty)
    }

    func testTrashManifestCodable() throws {
        let manifest = TrashedSessionManifest(
            instanceID: "default",
            instanceName: "默认实例",
            instanceRoot: "/tmp/.codex",
            rolloutOriginalPath: "/tmp/a.jsonl",
            rolloutTrashPath: "/tmp/trash/a.jsonl",
            sessionIndexEntry: #"{"id":"abc"}"#,
            threadRow: .init(
                id: "abc",
                rolloutPath: "/tmp/a.jsonl",
                createdAt: 1,
                updatedAt: 2,
                source: "codex",
                modelProvider: "openai",
                cwd: "/tmp",
                title: "Test",
                sandboxPolicy: "{}",
                approvalMode: "never",
                tokensUsed: 1,
                hasUserEvent: 0,
                archived: 0,
                archivedAt: nil,
                gitSHA: nil,
                gitBranch: nil,
                gitOriginURL: nil,
                cliVersion: nil,
                firstUserMessage: nil,
                agentNickname: nil,
                agentRole: nil,
                memoryMode: nil,
                model: nil,
                reasoningEffort: nil,
                agentPath: nil,
                createdAtMS: nil,
                updatedAtMS: nil
            )
        )
        let data = try JSONEncoder.swichCodex.encode(manifest)
        let decoded = try JSONDecoder.swichCodex.decode(TrashedSessionManifest.self, from: data)
        XCTAssertEqual(decoded.instanceID, "default")
        XCTAssertEqual(decoded.threadRow.id, "abc")
    }

    func testSQLiteStoreReadsThreadsWhenOptionalColumnsAreMissing() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let dbURL = directory.appendingPathComponent("state_5.sqlite")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }

        let createSQL = """
        CREATE TABLE threads (
            id TEXT PRIMARY KEY,
            rollout_path TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            source TEXT NOT NULL,
            model_provider TEXT NOT NULL,
            cwd TEXT NOT NULL,
            title TEXT NOT NULL,
            sandbox_policy TEXT NOT NULL,
            approval_mode TEXT NOT NULL,
            tokens_used INTEGER NOT NULL DEFAULT 0,
            has_user_event INTEGER NOT NULL DEFAULT 0,
            archived INTEGER NOT NULL DEFAULT 0
        );
        """
        XCTAssertEqual(sqlite3_exec(db, createSQL, nil, nil, nil), SQLITE_OK)
        let insertSQL = """
        INSERT INTO threads (
            id, rollout_path, created_at, updated_at, source, model_provider, cwd, title,
            sandbox_policy, approval_mode, tokens_used, has_user_event, archived
        ) VALUES (
            'session-1', '/tmp/rollout.jsonl', 1, 2, 'codex', 'openai', '/tmp',
            'Compat Test', '{}', 'never', 42, 1, 0
        );
        """
        XCTAssertEqual(sqlite3_exec(db, insertSQL, nil, nil, nil), SQLITE_OK)

        let rows = try SQLiteStore().readThreads(at: dbURL)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].id, "session-1")
        XCTAssertEqual(rows[0].title, "Compat Test")
        XCTAssertEqual(rows[0].cliVersion, "")
        XCTAssertEqual(rows[0].memoryMode, "enabled")
        XCTAssertNil(rows[0].agentPath)
    }
}
