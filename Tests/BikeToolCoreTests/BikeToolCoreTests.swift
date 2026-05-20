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

    func testDataInitializerAndSerializationRoundTripPreservesBikeMarkup() throws {
        let source = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
          <head>
            <meta charset="utf-8"/>
          </head>
          <body>
            <ul>
              <li id="root" data-type="task" indent="2" data-extra="keep">
                <p><strong>Root</strong> &amp; <em>child</em></p>
                <ul>
                  <li id="child" data-type="note" data-done="2026-01-01T00:00:00Z">
                    <p/>
                  </li>
                </ul>
              </li>
            </ul>
          </body>
        </html>
        """
        let bike = try BikeDocument(data: Data(source.utf8))
        let rows = try bike.readRows()
        let root = try XCTUnwrap(rows.first)

        XCTAssertEqual(root.id, "root")
        XCTAssertEqual(root.attributes["indent"], "2")
        XCTAssertEqual(root.attributes["data-extra"], "keep")
        XCTAssertEqual(root.children.first?.done, "2026-01-01T00:00:00Z")
        XCTAssertEqual(root.children.first?.richText, "")

        let output = try XCTUnwrap(String(data: bike.serializedData(), encoding: .utf8))
        XCTAssertTrue(output.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        XCTAssertTrue(output.contains("xmlns=\"http://www.w3.org/1999/xhtml\""))
        XCTAssertTrue(output.contains("<meta charset=\"utf-8\"/>"))
        XCTAssertTrue(output.contains("<p/>"))
        XCTAssertTrue(output.contains("<strong>Root</strong> &amp; <em>child</em>"))
    }

    func testSetRichTextInsertsParagraphWhenMissing() throws {
        let source = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
          <head><meta charset="utf-8"/></head>
          <body>
            <ul>
              <li id="root" data-type="note">
                <ul>
                  <li id="child"><p>Child</p></li>
                </ul>
              </li>
            </ul>
          </body>
        </html>
        """
        let bike = try BikeDocument(data: Data(source.utf8))
        XCTAssertTrue(try bike.setRichText(id: "root", richText: "Inserted <mark>paragraph</mark>"))

        let rows = try bike.readRows()
        let root = try XCTUnwrap(rows.first)
        XCTAssertEqual(root.text, "Inserted paragraph")
        XCTAssertTrue(root.richText.contains("<mark>paragraph</mark>"))
        XCTAssertEqual(root.children.map(\.id), ["child"])
    }

    func testReorderRootRowsPreservesSubtreesAndMetadata() throws {
        let tempURL = try writeReorderBike()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let bike = try BikeDocument(path: tempURL.path)
        try bike.reorderChildren(parentID: nil, orderedChildIDs: ["third", "first", "second"])
        try bike.saveWithBackup(backupMode: .none)

        let rows = try BikeDocument(path: tempURL.path).readRows()
        XCTAssertEqual(rows.map(\.id), ["third", "first", "second"])

        let first = try XCTUnwrap(rows.first(where: { $0.id == "first" }))
        XCTAssertEqual(first.attributes["indent"], "1")
        XCTAssertTrue(first.richText.contains("<strong>First</strong>"))
        XCTAssertEqual(first.children.map(\.id), ["first-child"])
        XCTAssertEqual(first.children.first?.done, "2026-01-01T00:00:00Z")
    }

    func testReorderNestedChildrenKeepsParentAndSiblingOrder() throws {
        let tempURL = try writeReorderBike()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let bike = try BikeDocument(path: tempURL.path)
        try bike.reorderChildren(parentID: "second", orderedChildIDs: ["second-child-b", "second-child-a"])
        try bike.saveWithBackup(backupMode: .none)

        let rows = try BikeDocument(path: tempURL.path).readRows()
        XCTAssertEqual(rows.map(\.id), ["first", "second", "third"])

        let second = try XCTUnwrap(rows.first(where: { $0.id == "second" }))
        XCTAssertEqual(second.children.map(\.id), ["second-child-b", "second-child-a"])
        XCTAssertEqual(second.children.first?.children.map(\.id), ["second-grandchild"])
    }

    func testReorderChildrenRejectsInvalidChildSets() throws {
        let tempURL = try writeReorderBike()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let duplicateDocument = try BikeDocument(path: tempURL.path)
        XCTAssertThrowsError(
            try duplicateDocument.reorderChildren(parentID: nil, orderedChildIDs: ["first", "first", "third"])
        )

        let incompleteDocument = try BikeDocument(path: tempURL.path)
        XCTAssertThrowsError(
            try incompleteDocument.reorderChildren(parentID: nil, orderedChildIDs: ["first", "third"])
        )

        let nonDirectDocument = try BikeDocument(path: tempURL.path)
        XCTAssertThrowsError(
            try nonDirectDocument.reorderChildren(parentID: nil, orderedChildIDs: ["first", "second", "first-child"])
        )

        let unknownDocument = try BikeDocument(path: tempURL.path)
        XCTAssertThrowsError(
            try unknownDocument.reorderChildren(parentID: "second", orderedChildIDs: ["second-child-a", "missing"])
        )
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

    private func writeReorderBike() throws -> URL {
        try writeTempBike(contents: """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
          <head>
            <meta charset="utf-8"/>
          </head>
          <body>
            <ul>
              <li id="first" data-type="task" indent="1">
                <p><strong>First</strong></p>
                <ul>
                  <li id="first-child" data-type="note" data-done="2026-01-01T00:00:00Z">
                    <p>First child</p>
                  </li>
                </ul>
              </li>
              <li id="second">
                <p>Second</p>
                <ul>
                  <li id="second-child-a">
                    <p>Second child A</p>
                  </li>
                  <li id="second-child-b">
                    <p>Second child B</p>
                    <ul>
                      <li id="second-grandchild">
                        <p>Second grandchild</p>
                      </li>
                    </ul>
                  </li>
                </ul>
              </li>
              <li id="third" data-extra="keep">
                <p><em>Third</em></p>
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
