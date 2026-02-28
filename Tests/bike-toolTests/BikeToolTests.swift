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

    func testParseAddTypeDefaultsToItemAndSupportsBodyAlias() throws {
        XCTAssertEqual(try BikeTool.parseAddType(rawValue: nil, defaultType: "item"), "item")
        XCTAssertEqual(try BikeTool.parseAddType(rawValue: "body", defaultType: "item"), "item")
        XCTAssertEqual(try BikeTool.parseAddType(rawValue: "quote", defaultType: "item"), "quote")

        XCTAssertThrowsError(try BikeTool.parseAddType(rawValue: "unknown", defaultType: "item")) { error in
            XCTAssertTrue("\(error)".contains("Invalid --type"))
        }
    }

    func testAddItemAndBodyRowsWriteWithoutDataTypeAttribute() throws {
        try withIsolatedBackupDirectory { _ in
            let tempURL = try writePlacementFixture()
            let bike = try BikeDocument(path: tempURL.path)

            let itemID = try bike.addRow(text: "Plain body row", type: "item", parentID: nil)
            let bodyID = try bike.addRow(text: "Body alias row", type: "body", parentID: nil)
            try bike.saveWithBackup(backupMode: .none)

            let rows = try BikeDocument(path: tempURL.path).readRows()
            let itemRow = try XCTUnwrap(rows.first(where: { $0.id == itemID }))
            let bodyRow = try XCTUnwrap(rows.first(where: { $0.id == bodyID }))
            XCTAssertNil(itemRow.type, "Untyped item rows should not set data-type.")
            XCTAssertNil(bodyRow.type, "Body alias should map to untyped item rows.")

            let content = try String(contentsOf: tempURL, encoding: .utf8)
            XCTAssertTrue(content.contains("<li id=\"\(itemID)\">"))
            XCTAssertTrue(content.contains("<li id=\"\(bodyID)\">"))
            XCTAssertFalse(content.contains("<li id=\"\(itemID)\" data-type="))
            XCTAssertFalse(content.contains("<li id=\"\(bodyID)\" data-type="))
        }
    }

    func testHandleAddDefaultsToItemType() throws {
        let tempURL = try writePlacementFixture()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try BikeTool.handleAdd(args: [
            tempURL.path,
            "--text", "Default add body row",
            "--backup-mode", "none",
        ])

        let rows = try BikeDocument(path: tempURL.path).readRows()
        let inserted = try XCTUnwrap(rows.first(where: { $0.text == "Default add body row" }))
        XCTAssertNil(inserted.type, "add should default to untyped item rows.")
    }

    func testHandleAddLinkDefaultsToItemType() throws {
        let tempURL = try writePlacementFixture()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try BikeTool.handleAddLink(args: [
            tempURL.path,
            "--href", "file:///tmp/default-item-link.bike",
            "--text", "Default item link",
            "--parent-id", "rootB",
            "--backup-mode", "none",
        ])

        let rows = try BikeDocument(path: tempURL.path).readRows()
        let rootB = try XCTUnwrap(rows.first(where: { $0.id == "rootB" }))
        let inserted = try XCTUnwrap(rootB.children.first(where: { $0.text == "Default item link" }))
        XCTAssertNil(inserted.type, "add-link should default to untyped item rows.")
        XCTAssertEqual(inserted.links.first?.href, "file:///tmp/default-item-link.bike")
    }

    func testHandleAddAcceptsExtendedBikeTypes() throws {
        let tempURL = try writePlacementFixture()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let types = ["quote", "code", "ordered", "unordered"]
        for type in types {
            try BikeTool.handleAdd(args: [
                tempURL.path,
                "--text", "Type row \(type)",
                "--type", type,
                "--parent-id", "rootB",
                "--backup-mode", "none",
            ])
        }

        let rows = try BikeDocument(path: tempURL.path).readRows()
        let rootB = try XCTUnwrap(rows.first(where: { $0.id == "rootB" }))
        for type in types {
            let row = try XCTUnwrap(rootB.children.first(where: { $0.text == "Type row \(type)" }))
            XCTAssertEqual(row.type, type)
        }
    }

    func testAddAtStartInsertsRootRowAtTop() throws {
        let tempURL = try writePlacementFixture()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try BikeTool.handleAdd(args: [
            tempURL.path,
            "--text", "Transcript: newest entry",
            "--type", "heading",
            "--at-start",
            "--backup-mode", "none",
        ])

        let rows = try BikeDocument(path: tempURL.path).readRows()
        XCTAssertEqual(rows.first?.text, "Transcript: newest entry")
        XCTAssertEqual(rows.dropFirst().first?.id, "rootA")
    }

    func testAddBeforeIDInsertsBeforeRootTarget() throws {
        let tempURL = try writePlacementFixture()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try BikeTool.handleAdd(args: [
            tempURL.path,
            "--text", "Inserted before first root row",
            "--type", "note",
            "--before-id", "rootA",
            "--backup-mode", "none",
        ])

        let rows = try BikeDocument(path: tempURL.path).readRows()
        XCTAssertEqual(rows.first?.text, "Inserted before first root row")
        XCTAssertEqual(rows.dropFirst().first?.id, "rootA")
    }

    func testAddAfterIDInsertsAfterKnownRow() throws {
        let tempURL = try writePlacementFixture()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try BikeTool.handleAdd(args: [
            tempURL.path,
            "--text", "Inserted after childA",
            "--type", "note",
            "--after-id", "childA",
            "--parent-id", "rootB",
            "--backup-mode", "none",
        ])

        let rows = try BikeDocument(path: tempURL.path).readRows()
        let rootB = try XCTUnwrap(rows.first(where: { $0.id == "rootB" }))
        XCTAssertEqual(rootB.children.map(\.text), ["Child A", "Inserted after childA", "Child B"])
    }

    func testAddAtStartWithParentInsertsAsFirstChild() throws {
        let tempURL = try writePlacementFixture()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try BikeTool.handleAdd(args: [
            tempURL.path,
            "--text", "First child now",
            "--type", "task",
            "--parent-id", "rootB",
            "--at-start",
            "--backup-mode", "none",
        ])

        let rows = try BikeDocument(path: tempURL.path).readRows()
        let rootB = try XCTUnwrap(rows.first(where: { $0.id == "rootB" }))
        XCTAssertEqual(rootB.children.first?.text, "First child now")
    }

    func testPositionedInsertPreservesUntouchedRowsAndMetadata() throws {
        let tempURL = try writePlacementFixture()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let beforeRows = try BikeDocument(path: tempURL.path).readRows()
        let beforeRootA = try XCTUnwrap(beforeRows.first(where: { $0.id == "rootA" }))
        let beforeChildA = try XCTUnwrap(beforeRows.first(where: { $0.id == "rootB" })?.children.first(where: { $0.id == "childA" }))

        try BikeTool.handleAdd(args: [
            tempURL.path,
            "--text", "Inserted after childA",
            "--type", "note",
            "--after-id", "childA",
            "--backup-mode", "none",
        ])

        let afterRows = try BikeDocument(path: tempURL.path).readRows()
        XCTAssertEqual(afterRows.map(\.id), ["rootA", "rootB", "rootC"])

        let afterRootA = try XCTUnwrap(afterRows.first(where: { $0.id == "rootA" }))
        XCTAssertEqual(afterRootA.attributes["indent"], beforeRootA.attributes["indent"])
        XCTAssertTrue(afterRootA.richText.contains("<strong>Root A</strong>"))
        XCTAssertTrue(beforeRootA.richText.contains("<strong>Root A</strong>"))

        let afterRootB = try XCTUnwrap(afterRows.first(where: { $0.id == "rootB" }))
        XCTAssertEqual(afterRootB.children.count, 3)
        XCTAssertEqual(afterRootB.children.first?.id, "childA")
        XCTAssertEqual(afterRootB.children.last?.id, "childB")

        let afterChildA = try XCTUnwrap(afterRootB.children.first(where: { $0.id == "childA" }))
        XCTAssertEqual(afterChildA.attributes["data-extra"], beforeChildA.attributes["data-extra"])
        XCTAssertTrue(afterChildA.richText.contains("<em>Child A</em>"))
        XCTAssertTrue(beforeChildA.richText.contains("<em>Child A</em>"))
    }

    func testAddPlacementErrorsAreClear() throws {
        let tempURL = try writePlacementFixture()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        XCTAssertThrowsError(try BikeTool.handleAdd(args: [
            tempURL.path,
            "--text", "bad flags",
            "--before-id", "rootA",
            "--at-start",
            "--backup-mode", "none",
        ])) { error in
            XCTAssertTrue("\(error)".contains("Conflicting placement flags"))
        }

        XCTAssertThrowsError(try BikeTool.handleAdd(args: [
            tempURL.path,
            "--text", "missing target",
            "--before-id", "does-not-exist",
            "--backup-mode", "none",
        ])) { error in
            XCTAssertTrue("\(error)".contains("Target id not found"))
        }

        XCTAssertThrowsError(try BikeTool.handleAdd(args: [
            tempURL.path,
            "--text", "parent mismatch",
            "--after-id", "childA",
            "--parent-id", "rootC",
            "--backup-mode", "none",
        ])) { error in
            XCTAssertTrue("\(error)".contains("Parent mismatch"))
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

    private func writePlacementFixture() throws -> URL {
        try writeTempBike(contents: """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
          <head>
            <meta charset="utf-8"/>
          </head>
          <body>
            <ul>
              <li id="rootA" data-type="heading" indent="1">
                <p><strong>Root A</strong></p>
              </li>
              <li id="rootB" data-type="task">
                <p>Root B</p>
                <ul>
                  <li id="childA" data-type="note" data-extra="keep-me">
                    <p><em>Child A</em></p>
                  </li>
                  <li id="childB" data-type="note">
                    <p>Child B</p>
                  </li>
                </ul>
              </li>
              <li id="rootC" data-type="note">
                <p>Root C</p>
              </li>
            </ul>
          </body>
        </html>
        """)
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
