import XCTest
@testable import bike_tool

final class BikeToolTests: XCTestCase {
    func testRoundTripPreservesRichMarkupAndUnknownAttributes() throws {
        try withIsolatedBackupDirectory { _ in
            let tempURL = try copyFixtureToTempFile()

            let bike = try BikeDocument(path: tempURL.path)
            _ = try bike.addRow(text: "Regression add", type: "note", parentID: "cOV")
            _ = try bike.setDone(id: "8r", markDone: true)
            try bike.saveWithBackup()

            _ = try BikeDocument(path: tempURL.path)

            let content = try String(contentsOf: tempURL, encoding: .utf8)
            XCTAssertTrue(content.contains("indent=\"2\""), "Should preserve unknown row attributes like indent.")
            XCTAssertTrue(content.contains("<strong>Ordered Events with no start or end time:"), "Should preserve inline rich text markup inside row paragraphs.")
            XCTAssertTrue(content.contains("Regression add"), "Should include newly inserted row text.")
            XCTAssertTrue(content.contains("xmlns=\"http://www.w3.org/1999/xhtml\""), "Should preserve XHTML namespace declaration.")

            let inlineBackupURL = URL(fileURLWithPath: tempURL.path + ".bak")
            XCTAssertFalse(FileManager.default.fileExists(atPath: inlineBackupURL.path), "Managed backups should avoid littering sidecar .bak files by default.")

            let backups = try BackupManager.listBackups(for: tempURL)
            XCTAssertEqual(backups.count, 1, "Should create one managed backup before the first write.")
        }
    }

    func testJSONRowsIncludeAttributesAndRichTextWhenRequested() throws {
        let bike = try BikeDocument(path: fixtureURL().path)
        let rows = try bike.readRows()

        let encoded = try JSONEncoder().encode(rows.map { EncodableRow(from: $0, includeRichText: true) })
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertTrue(json.contains("\"attributes\""), "JSON should include full row attributes.")
        XCTAssertTrue(json.contains("\"indent\":\"2\""), "JSON should surface custom attributes such as indent.")
        XCTAssertTrue(json.contains("\"richText\""), "JSON should include richText when requested.")
    }

    func testDeleteRowRemovesNodeAndKeepsDocumentValid() throws {
        try withIsolatedBackupDirectory { _ in
            let tempURL = try copyFixtureToTempFile()

            let bike = try BikeDocument(path: tempURL.path)
            let deleted = try bike.deleteRow(id: "re2")
            XCTAssertTrue(deleted, "Expected deleteRow to remove an existing row.")
            try bike.saveWithBackup()

            _ = try BikeDocument(path: tempURL.path)

            let content = try String(contentsOf: tempURL, encoding: .utf8)
            XCTAssertFalse(content.contains("id=\"re2\""), "Deleted row should not remain in output XML.")

            let backups = try BackupManager.listBackups(for: tempURL)
            XCTAssertEqual(backups.count, 1, "Delete should create a managed backup before writing.")
        }
    }

    func testManagedBackupRestoreAndPrune() throws {
        try withIsolatedBackupDirectory { _ in
            let tempURL = try copyFixtureToTempFile()

            let bikeFirst = try BikeDocument(path: tempURL.path)
            _ = try bikeFirst.addRow(text: "First snapshot row", type: "note", parentID: nil)
            try bikeFirst.saveWithBackup()
            let firstSnapshot = try String(contentsOf: tempURL, encoding: .utf8)

            let bikeSecond = try BikeDocument(path: tempURL.path)
            _ = try bikeSecond.addRow(text: "Second snapshot row", type: "note", parentID: nil)
            try bikeSecond.saveWithBackup()
            let secondSnapshot = try String(contentsOf: tempURL, encoding: .utf8)

            XCTAssertNotEqual(firstSnapshot, secondSnapshot, "Expected second write to change document content.")

            let backupsBeforeRestore = try BackupManager.listBackups(for: tempURL)
            XCTAssertGreaterThanOrEqual(backupsBeforeRestore.count, 2, "Expected one backup per write.")

            let restoreID = try XCTUnwrap(backupsBeforeRestore.first?.id)
            try BackupManager.restoreBackup(for: tempURL, backupID: restoreID, writeMode: .atomic)

            let restored = try String(contentsOf: tempURL, encoding: .utf8)
            XCTAssertEqual(restored, firstSnapshot, "Restore should recover the selected backup state.")

            let removed = try BackupManager.pruneBackups(for: tempURL, keep: 1, maxAgeDays: 3650)
            XCTAssertGreaterThanOrEqual(removed, 1, "Prune should remove older backups beyond keep policy.")

            let backupsAfterPrune = try BackupManager.listBackups(for: tempURL)
            XCTAssertEqual(backupsAfterPrune.count, 1, "Prune should leave the requested number of backups.")
        }
    }

    private func copyFixtureToTempFile() throws -> URL {
        let fixture = fixtureURL()
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let target = tempDir.appendingPathComponent("bike-tool-regression-\(UUID().uuidString).bike")
        try FileManager.default.copyItem(at: fixture, to: target)
        return target
    }

    private func fixtureURL() -> URL {
        guard let url = Bundle.module.url(forResource: "Chronogram Master Outline copy", withExtension: "bike") else {
            fatalError("Fixture not found in test bundle.")
        }
        return url
    }

    private func withIsolatedBackupDirectory(_ body: (URL) throws -> Void) throws {
        let previous = ProcessInfo.processInfo.environment["BIKETOOL_BACKUP_DIR"]
        let backupRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("bike-tool-backups-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        setenv("BIKETOOL_BACKUP_DIR", backupRoot.path, 1)

        defer {
            if let previous {
                setenv("BIKETOOL_BACKUP_DIR", previous, 1)
            } else {
                unsetenv("BIKETOOL_BACKUP_DIR")
            }
            try? FileManager.default.removeItem(at: backupRoot)
        }

        try body(backupRoot)
    }
}
