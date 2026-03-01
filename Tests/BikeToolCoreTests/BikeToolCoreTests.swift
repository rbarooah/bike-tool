import XCTest
import BikeToolCore

final class BikeToolCoreTests: XCTestCase {
    func testRoundTripPreservesUnknownAttributesAndRichMarkup() throws {
        try withIsolatedBackupDirectory { _ in
            let tempURL = try writeBaseBike()
            defer { try? FileManager.default.removeItem(at: tempURL) }

            let bike = try BikeDocument(path: tempURL.path)
            _ = try bike.addRow(text: "Regression add", type: "note", parentID: "root")
            _ = try bike.setDone(id: "child", markDone: true)
            try bike.saveWithBackup()

            _ = try BikeDocument(path: tempURL.path)

            let content = try String(contentsOf: tempURL, encoding: .utf8)
            XCTAssertTrue(content.contains("indent=\"2\""))
            XCTAssertTrue(content.contains("<strong>Root</strong>"))
            XCTAssertTrue(content.contains("Regression add"))

            let inlineBackupURL = URL(fileURLWithPath: tempURL.path + ".bak")
            XCTAssertFalse(FileManager.default.fileExists(atPath: inlineBackupURL.path))

            let backups = try BackupManager.listBackups(for: tempURL)
            XCTAssertEqual(backups.count, 1)
        }
    }

    func testManagedBackupRestoreAndPrune() throws {
        try withIsolatedBackupDirectory { _ in
            let tempURL = try writeBaseBike()
            defer { try? FileManager.default.removeItem(at: tempURL) }

            let bikeFirst = try BikeDocument(path: tempURL.path)
            _ = try bikeFirst.addRow(text: "First snapshot row", type: "note", parentID: nil)
            try bikeFirst.saveWithBackup()
            let firstSnapshot = try String(contentsOf: tempURL, encoding: .utf8)

            let bikeSecond = try BikeDocument(path: tempURL.path)
            _ = try bikeSecond.addRow(text: "Second snapshot row", type: "note", parentID: nil)
            try bikeSecond.saveWithBackup()
            let secondSnapshot = try String(contentsOf: tempURL, encoding: .utf8)

            XCTAssertNotEqual(firstSnapshot, secondSnapshot)

            let backupsBeforeRestore = try BackupManager.listBackups(for: tempURL)
            XCTAssertGreaterThanOrEqual(backupsBeforeRestore.count, 2)

            let restoreID = try XCTUnwrap(backupsBeforeRestore.first?.id)
            try BackupManager.restoreBackup(for: tempURL, backupID: restoreID, writeMode: .atomic)

            let restored = try String(contentsOf: tempURL, encoding: .utf8)
            XCTAssertEqual(restored, firstSnapshot)

            let removed = try BackupManager.pruneBackups(for: tempURL, keep: 1, maxAgeDays: 3650)
            XCTAssertGreaterThanOrEqual(removed, 1)

            let backupsAfterPrune = try BackupManager.listBackups(for: tempURL)
            XCTAssertEqual(backupsAfterPrune.count, 1)
        }
    }

    func testAddLinkRowCreatesAnchorAndParsedLinks() throws {
        let tempURL = try writeBaseBike()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let bike = try BikeDocument(path: tempURL.path)
        _ = try bike.addLinkRow(
            href: "file:///Users/robin/Desktop/another-file.bike",
            text: "another-file.bike",
            type: "note",
            parentID: "root"
        )
        try bike.saveWithBackup(backupMode: .none)

        let rows = try BikeDocument(path: tempURL.path).readRows()
        let root = try XCTUnwrap(rows.first(where: { $0.id == "root" }))
        let inserted = try XCTUnwrap(root.children.first(where: { $0.text == "another-file.bike" }))
        XCTAssertEqual(inserted.links.first?.href, "file:///Users/robin/Desktop/another-file.bike")

        let updated = try String(contentsOf: tempURL, encoding: .utf8)
        XCTAssertTrue(updated.contains("<a href=\"file:///Users/robin/Desktop/another-file.bike\">another-file.bike</a>"))
    }

    func testSetRichTextPreservesChildren() throws {
        let tempURL = try writeBaseBike()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let bike = try BikeDocument(path: tempURL.path)
        _ = try bike.setRichText(id: "root", richText: "Updated <mark>rich</mark> text")
        try bike.saveWithBackup(backupMode: .none)

        let rows = try BikeDocument(path: tempURL.path).readRows()
        let root = try XCTUnwrap(rows.first(where: { $0.id == "root" }))
        XCTAssertEqual(root.children.map(\.id), ["child"])
        XCTAssertTrue(root.richText.contains("<mark>rich</mark>"))
    }

    func testAddRichRejectsUnsupportedTag() throws {
        let tempURL = try writeBaseBike()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let bike = try BikeDocument(path: tempURL.path)
        XCTAssertThrowsError(
            try bike.addRichRow(richText: "<div>Not allowed</div>", type: "note", parentID: nil)
        ) { error in
            XCTAssertTrue("\(error)".contains("unsupported tag"))
        }
    }

    private func writeBaseBike() throws -> URL {
        try writeTempBike(contents: """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
          <head>
            <meta charset="utf-8"/>
          </head>
          <body>
            <ul>
              <li id="root" data-type="task" indent="2">
                <p><strong>Root</strong></p>
                <ul>
                  <li id="child" data-type="note">
                    <p>Child</p>
                  </li>
                </ul>
              </li>
            </ul>
          </body>
        </html>
        """)
    }

    private func writeTempBike(contents: String) throws -> URL {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let target = tempDir.appendingPathComponent("bike-tool-core-test-\(UUID().uuidString).bike")
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
