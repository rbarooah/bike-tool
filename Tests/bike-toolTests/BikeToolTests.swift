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

    func testJSONRowsIncludeStructuredLinks() throws {
        let tempURL = try writeTempBike(contents: """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
          <head>
            <meta charset="utf-8"/>
          </head>
          <body>
            <ul>
              <li id="root" data-type="note">
                <p><a href="file:///Users/robin/Desktop/example.bike">Example Bike File</a></p>
              </li>
            </ul>
          </body>
        </html>
        """)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let bike = try BikeDocument(path: tempURL.path)
        let rows = try bike.readRows()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].links.count, 1)
        XCTAssertEqual(rows[0].links[0].href, "file:///Users/robin/Desktop/example.bike")
        XCTAssertEqual(rows[0].links[0].text, "Example Bike File")

        let encoded = try JSONEncoder().encode(rows.map { EncodableRow(from: $0, includeRichText: false) })
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertTrue(json.contains("\"links\""), "JSON should include links when anchor tags exist in row content.")
        XCTAssertTrue(json.contains("file:\\/\\/\\/Users\\/robin\\/Desktop\\/example.bike"), "JSON should include parsed href values.")
    }

    func testAddLinkRowCreatesAnchorMarkup() throws {
        try withIsolatedBackupDirectory { _ in
            let tempURL = try copyFixtureToTempFile()

            let bike = try BikeDocument(path: tempURL.path)
            _ = try bike.addLinkRow(
                href: "file:///Users/robin/Desktop/another-file.bike",
                text: "another-file.bike",
                type: "note",
                parentID: "cOV"
            )
            try bike.saveWithBackup()

            let updated = try String(contentsOf: tempURL, encoding: .utf8)
            XCTAssertTrue(
                updated.contains("<a href=\"file:///Users/robin/Desktop/another-file.bike\">another-file.bike</a>"),
                "addLinkRow should create explicit anchor markup in paragraph content."
            )
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

    private func writeTempBike(contents: String) throws -> URL {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let target = tempDir.appendingPathComponent("bike-tool-link-fixture-\(UUID().uuidString).bike")
        try contents.write(to: target, atomically: true, encoding: .utf8)
        return target
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
