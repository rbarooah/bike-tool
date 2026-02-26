import XCTest
@testable import bike_tool

final class BikeToolTests: XCTestCase {
    func testRoundTripPreservesRichMarkupAndUnknownAttributes() throws {
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

        let backupURL = URL(fileURLWithPath: tempURL.path + ".bak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path), "Should create a backup before writing.")
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
        let tempURL = try copyFixtureToTempFile()

        let bike = try BikeDocument(path: tempURL.path)
        let deleted = try bike.deleteRow(id: "re2")
        XCTAssertTrue(deleted, "Expected deleteRow to remove an existing row.")
        try bike.saveWithBackup()

        _ = try BikeDocument(path: tempURL.path)

        let content = try String(contentsOf: tempURL, encoding: .utf8)
        XCTAssertFalse(content.contains("id=\"re2\""), "Deleted row should not remain in output XML.")

        let backupURL = URL(fileURLWithPath: tempURL.path + ".bak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path), "Delete should create a backup before writing.")
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
}
