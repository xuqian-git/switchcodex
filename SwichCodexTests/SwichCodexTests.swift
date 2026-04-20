import XCTest
@testable import SwichCodex

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
}
