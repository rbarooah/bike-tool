import Foundation

/// In-memory `.bike` document model with safe, structured mutation APIs.
public final class BikeDocument {
    private static let allowedInlineTagNames: Set<String> = ["a", "strong", "em", "s", "code", "mark", "span"]
    private static let allowedInlineAttributesByTag: [String: Set<String>] = [
        "a": ["href", "title", "rel"],
        "span": ["style"],
        "strong": [],
        "em": [],
        "s": [],
        "code": [],
        "mark": [],
    ]

    private let url: URL?
    private let document: BikeXMLDocument

    /// Loads and validates a Bike XML document from disk.
    /// - Parameter path: Absolute or relative file path to a `.bike` document.
    /// - Throws: ``BikeToolCoreError`` when the file is missing, or XML parsing/validation errors.
    public convenience init(path: String) throws {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            throw BikeToolCoreError(message: "File not found: \(path)")
        }
        let data = try Data(contentsOf: url)
        try self.init(data: data, sourceURL: url)
    }

    /// Loads and validates a Bike XML document from in-memory data.
    /// - Parameter data: UTF-8 XML data for a `.bike` document.
    /// - Throws: ``BikeToolCoreError`` when parsing or validation fails.
    public convenience init(data: Data) throws {
        try self.init(data: data, sourceURL: nil)
    }

    private init(data: Data, sourceURL: URL?) throws {
        self.url = sourceURL
        self.document = try BikeXMLDocument(data: data)
        _ = try topUL()
    }

    /// Reads top-level outline rows from the document.
    /// - Returns: Parsed rows preserving attributes, rich text, and hierarchy.
    /// - Throws: ``BikeToolCoreError`` when expected Bike structure is missing.
    public func readRows() throws -> [Row] {
        let rootUL = try topUL()
        return parseRows(in: rootUL)
    }

    /// Adds a plain-text row.
    /// - Parameters:
    ///   - text: Plain text for the row paragraph.
    ///   - type: Bike row type (for example `item`, `task`, `note`).
    ///   - parentID: Optional parent row id for nested insertion.
    ///   - placement: Insertion placement among siblings.
    /// - Returns: The generated row id.
    /// - Throws: ``BikeToolCoreError`` for invalid placement or missing parent/target rows.
    public func addRow(text: String, type: String, parentID: String?, placement: AddPlacement = .atEnd) throws -> String {
        let p = BikeXMLElement(name: "p")
        p.addChild(BikeXMLNode(text: text))
        return try addRow(type: type, paragraph: p, parentID: parentID, placement: placement)
    }

    /// Adds a row containing an anchor (`<a href="...">`).
    /// - Parameters:
    ///   - href: Link destination URI. Must be non-empty after trimming.
    ///   - text: Link label text. Falls back to `href` when empty after trimming.
    ///   - type: Bike row type.
    ///   - parentID: Optional parent row id for nested insertion.
    ///   - placement: Insertion placement among siblings.
    /// - Returns: The generated row id.
    /// - Throws: ``BikeToolCoreError`` for invalid `href` or placement/parent errors.
    public func addLinkRow(href: String, text: String, type: String, parentID: String?, placement: AddPlacement = .atEnd) throws -> String {
        let normalizedHref = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHref.isEmpty else {
            throw BikeToolCoreError(message: "--href must not be empty.")
        }

        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = BikeXMLElement(name: "p")
        let a = BikeXMLElement(name: "a")
        a.setAttribute(name: "href", value: normalizedHref)
        a.addChild(BikeXMLNode(text: normalizedText.isEmpty ? normalizedHref : normalizedText))
        p.addChild(BikeXMLNode(element: a))
        return try addRow(type: type, paragraph: p, parentID: parentID, placement: placement)
    }

    /// Adds a row whose paragraph content is provided as inline rich-text XML fragment.
    /// - Parameters:
    ///   - richText: Inline XML fragment allowed by the sanitizer (`a`, `strong`, `em`, `s`, `code`, `mark`, `span`).
    ///   - type: Bike row type.
    ///   - parentID: Optional parent row id for nested insertion.
    ///   - placement: Insertion placement among siblings.
    /// - Returns: The generated row id.
    /// - Throws: ``BikeToolCoreError`` for malformed/unsupported rich text or invalid placement.
    public func addRichRow(richText: String, type: String, parentID: String?, placement: AddPlacement = .atEnd) throws -> String {
        let p = try paragraphFromRichText(richText)
        return try addRow(type: type, paragraph: p, parentID: parentID, placement: placement)
    }

    private func addRow(type: String, paragraph: BikeXMLElement, parentID: String?, placement: AddPlacement) throws -> String {
        let normalizedType = Self.normalizeStoredType(type)
        guard !normalizedType.isEmpty else {
            throw BikeToolCoreError(message: "Row type must not be empty.")
        }

        let li = BikeXMLElement(name: "li")
        let id = try generateUniqueID()
        li.setAttribute(name: "id", value: id)
        if normalizedType != "item" {
            li.setAttribute(name: "data-type", value: normalizedType)
        }
        li.addChild(BikeXMLNode(element: paragraph))

        switch placement {
        case .atEnd:
            if let parentID {
                guard let parent = findLI(id: parentID) else {
                    throw BikeToolCoreError(message: "Parent id not found: \(parentID)")
                }
                if let childUL = firstChildElement(named: "ul", in: parent) {
                    childUL.addChild(BikeXMLNode(element: li))
                } else {
                    let newUL = BikeXMLElement(name: "ul")
                    newUL.addChild(BikeXMLNode(element: li))
                    parent.addChild(BikeXMLNode(element: newUL))
                }
            } else {
                let rootUL = try topUL()
                rootUL.addChild(BikeXMLNode(element: li))
            }
        case .atStart:
            if let parentID {
                guard let parent = findLI(id: parentID) else {
                    throw BikeToolCoreError(message: "Parent id not found: \(parentID)")
                }
                if let childUL = firstChildElement(named: "ul", in: parent) {
                    let startIndex = firstListItemIndex(in: childUL)
                    childUL.insertChild(BikeXMLNode(element: li), at: startIndex)
                } else {
                    let newUL = BikeXMLElement(name: "ul")
                    newUL.addChild(BikeXMLNode(element: li))
                    parent.addChild(BikeXMLNode(element: newUL))
                }
            } else {
                let rootUL = try topUL()
                let startIndex = firstListItemIndex(in: rootUL)
                rootUL.insertChild(BikeXMLNode(element: li), at: startIndex)
            }
        case .before(let targetID), .after(let targetID):
            guard let target = findLI(id: targetID) else {
                throw BikeToolCoreError(message: "Target id not found: \(targetID)")
            }
            guard let siblingsUL = target.parent, siblingsUL.isNamed("ul") else {
                throw BikeToolCoreError(message: "Invalid Bike structure near target id=\(targetID).")
            }

            let inferredParentID = try inferredParentRowID(forSiblingsUL: siblingsUL)
            if let parentID {
                if let inferredParentID {
                    guard parentID == inferredParentID else {
                        throw BikeToolCoreError(message: "Parent mismatch for target id=\(targetID): --parent-id \(parentID) does not match inferred parent \(inferredParentID).")
                    }
                } else {
                    throw BikeToolCoreError(message: "Parent mismatch for target id=\(targetID): target row is at root, so omit --parent-id.")
                }
            }

            guard let targetIndex = listItemIndex(of: target, in: siblingsUL) else {
                throw BikeToolCoreError(message: "Invalid Bike structure near target id=\(targetID).")
            }
            let insertionIndex: Int
            switch placement {
            case .before:
                insertionIndex = targetIndex
            case .after:
                insertionIndex = targetIndex + 1
            default:
                insertionIndex = targetIndex
            }
            siblingsUL.insertChild(BikeXMLNode(element: li), at: insertionIndex)
        }
        return id
    }

    /// Marks or unmarks an existing row as done.
    /// - Parameters:
    ///   - id: Target row id.
    ///   - markDone: `true` to set `data-done`, `false` to remove it.
    /// - Returns: `true` when the row exists and was updated; otherwise `false`.
    /// - Throws: XML traversal errors when internal document state is invalid.
    public func setDone(id: String, markDone: Bool) throws -> Bool {
        guard let li = findLI(id: id) else { return false }
        if markDone {
            li.removeAttribute(forName: "data-done")
            let doneValue = Self.iso8601Now()
            li.setAttribute(name: "data-done", value: doneValue)
        } else {
            li.removeAttribute(forName: "data-done")
        }
        return true
    }

    /// Deletes a row by id.
    /// - Parameter id: Target row id.
    /// - Returns: `true` when the row exists and was removed; otherwise `false`.
    /// - Throws: XML traversal errors when internal document state is invalid.
    public func deleteRow(id: String) throws -> Bool {
        guard let li = findLI(id: id) else { return false }
        li.detach()
        return true
    }

    /// Replaces paragraph content for an existing row with sanitized rich text.
    /// - Parameters:
    ///   - id: Target row id.
    ///   - richText: Inline XML fragment for the paragraph body.
    /// - Returns: `true` when the row exists and was updated; otherwise `false`.
    /// - Throws: ``BikeToolCoreError`` for malformed/unsupported rich text.
    public func setRichText(id: String, richText: String) throws -> Bool {
        guard let li = findLI(id: id) else { return false }
        let p = upsertParagraph(in: li)
        let newChildren = try parseRichTextFragment(richText)

        let existingChildren = p.children
        for child in existingChildren {
            child.detach()
        }
        for child in newChildren {
            p.addChild(child)
        }
        return true
    }

    /// Serializes and writes the current in-memory document to disk.
    ///
    /// Backup handling runs first according to `backupMode`.
    /// - Parameters:
    ///   - writeMode: File write strategy.
    ///   - backupMode: Backup strategy applied before write.
    /// - Throws: ``BikeToolCoreError`` or Foundation file coordination/write errors.
    public func saveWithBackup(writeMode: WriteMode = .coordinated, backupMode: BackupMode = .managed) throws {
        guard url != nil else {
            throw BikeToolCoreError(message: "Cannot save document loaded from data without a source URL.")
        }
        let outData = try serializedData()
        switch writeMode {
        case .coordinated:
            try writeCoordinated(outData, backupMode: backupMode)
        case .atomic:
            try writeNonCoordinated(outData, atomic: true, backupMode: backupMode)
        case .inplace:
            try writeNonCoordinated(outData, atomic: false, backupMode: backupMode)
        }
    }

    /// Serializes the current in-memory document as UTF-8 XML data.
    /// - Returns: XML data suitable for writing as a `.bike` document.
    /// - Throws: ``BikeToolCoreError`` when serialization fails.
    public func serializedData() throws -> Data {
        try document.serializedData()
    }

    private func writeNonCoordinated(_ data: Data, atomic: Bool, backupMode: BackupMode) throws {
        guard let url else {
            throw BikeToolCoreError(message: "Cannot save document loaded from data without a source URL.")
        }
        try writeBackup(for: url, mode: backupMode)
        if atomic {
            try data.write(to: url, options: .atomic)
        } else {
            try data.write(to: url)
        }
    }

    private func writeCoordinated(_ data: Data, backupMode: BackupMode) throws {
        guard let url else {
            throw BikeToolCoreError(message: "Cannot save document loaded from data without a source URL.")
        }
        try writeBackup(for: url, mode: backupMode)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinatorError: NSError?
        var writeError: Error?

        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { coordinatedURL in
            do {
                try data.write(to: coordinatedURL, options: .atomic)
            } catch {
                writeError = error
            }
        }

        if let coordinatorError {
            throw coordinatorError
        }
        if let writeError {
            throw writeError
        }
    }

    private func writeBackup(for sourceURL: URL, mode: BackupMode) throws {
        switch mode {
        case .managed:
            _ = try BackupManager.createManagedBackup(for: sourceURL)
        case .inline:
            let backupURL = URL(fileURLWithPath: sourceURL.path + ".bak")
            if FileManager.default.fileExists(atPath: backupURL.path) {
                try FileManager.default.removeItem(at: backupURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: backupURL)
        case .none:
            return
        }
    }

    private func topUL() throws -> BikeXMLElement {
        guard let html = document.root.isNamed("html") ? document.root : nil,
              let body = firstChildElement(named: "body", in: html),
              let rootUL = firstChildElement(named: "ul", in: body)
        else {
            throw BikeToolCoreError(message: "Invalid Bike structure. Expected /html/body/ul.")
        }
        return rootUL
    }

    private func parseRows(in ul: BikeXMLElement) -> [Row] {
        let lis = ul.children.compactMap(\.element).filter { $0.isNamed("li") }
        return lis.map { parseRow(from: $0) }
    }

    private func parseRow(from li: BikeXMLElement) -> Row {
        let attrs = allAttributes(from: li)
        let id = attrs["id"] ?? ""
        let type = attrs["data-type"]
        let done = attrs["data-done"]
        let p = firstChildElement(named: "p", in: li)
        let text = p?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let richText = p.map(innerXML(of:)) ?? ""
        let links = p.map(extractLinks(from:)) ?? []

        var children: [Row] = []
        if let childUL = firstChildElement(named: "ul", in: li) {
            children = parseRows(in: childUL)
        }
        return Row(
            id: id,
            type: type,
            text: text,
            richText: richText,
            links: links,
            done: done,
            attributes: attrs,
            children: children
        )
    }

    private func findLI(id: String) -> BikeXMLElement? {
        document.elements(named: "li").first { $0.attribute(forName: "id") == id }
    }

    private func firstChildElement(named: String, in element: BikeXMLElement) -> BikeXMLElement? {
        element.firstChildElement(named: named)
    }

    private func generateID() -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        return String((0..<6).map { _ in chars.randomElement()! })
    }

    private func firstListItemIndex(in ul: BikeXMLElement) -> Int {
        for (index, child) in ul.children.enumerated() {
            guard let childElement = child.element else { continue }
            if childElement.isNamed("li") {
                return index
            }
        }
        return ul.children.count
    }

    private func listItemIndex(of target: BikeXMLElement, in ul: BikeXMLElement) -> Int? {
        for (index, child) in ul.children.enumerated() {
            guard let childElement = child.element else { continue }
            if childElement === target {
                return index
            }
        }
        return nil
    }

    private func inferredParentRowID(forSiblingsUL ul: BikeXMLElement) throws -> String? {
        let rootUL = try topUL()
        if ul === rootUL {
            return nil
        }
        guard let parentLI = ul.parent, parentLI.isNamed("li") else {
            throw BikeToolCoreError(message: "Invalid Bike structure. Expected nested rows under li/ul.")
        }
        guard let parentID = parentLI.attribute(forName: "id"), !parentID.isEmpty else {
            throw BikeToolCoreError(message: "Invalid Bike structure. Parent row is missing id.")
        }
        return parentID
    }

    private func generateUniqueID(maxAttempts: Int = 100) throws -> String {
        for _ in 0..<maxAttempts {
            let candidate = generateID()
            if findLI(id: candidate) == nil {
                return candidate
            }
        }
        throw BikeToolCoreError(message: "Unable to generate unique id after \(maxAttempts) attempts.")
    }

    private func allAttributes(from element: BikeXMLElement) -> [String: String] {
        element.attributes
    }

    private func innerXML(of element: BikeXMLElement) -> String {
        element.children.map { $0.xmlString() }.joined()
    }

    private func paragraphFromRichText(_ richText: String) throws -> BikeXMLElement {
        let p = BikeXMLElement(name: "p")
        let richChildren = try parseRichTextFragment(richText)
        for child in richChildren {
            p.addChild(child)
        }
        return p
    }

    private func parseRichTextFragment(_ fragment: String) throws -> [BikeXMLNode] {
        if fragment.isEmpty {
            return []
        }

        // Plain text input with no tag delimiters should be accepted directly.
        if !fragment.contains("<"), !fragment.contains(">") {
            return [BikeXMLNode(text: fragment)]
        }

        let wrapped = "<root>\(fragment)</root>"
        let parsedDocument: BikeXMLDocument
        do {
            guard let data = wrapped.data(using: .utf8) else {
                throw BikeToolCoreError(message: "Invalid --rich-text fragment: unable to encode XML.")
            }
            parsedDocument = try BikeXMLDocument(data: data)
        } catch {
            throw BikeToolCoreError(message: "Invalid --rich-text fragment: not well-formed XML.")
        }

        return try parsedDocument.root.children.map { try sanitizeInlineNode($0) }
    }

    private func sanitizeInlineNode(_ node: BikeXMLNode) throws -> BikeXMLNode {
        switch node.storage {
        case .text(let text):
            return BikeXMLNode(text: text)
        case .element(let element):
            return BikeXMLNode(element: try sanitizeInlineElement(element))
        }
    }

    private func sanitizeInlineElement(_ element: BikeXMLElement) throws -> BikeXMLElement {
        let rawName = element.name
        guard !rawName.isEmpty else {
            throw BikeToolCoreError(message: "Invalid --rich-text fragment: encountered unnamed element.")
        }

        let canonicalName = canonicalInlineName(from: rawName)
        guard Self.allowedInlineTagNames.contains(canonicalName) else {
            throw BikeToolCoreError(message: "Invalid --rich-text fragment: unsupported tag '\(rawName)'.")
        }

        let allowedAttributes = Self.allowedInlineAttributesByTag[canonicalName] ?? []
        let copied = BikeXMLElement(name: rawName)
        for attributeName in element.attributeNames {
            guard let attributeValue = element.attribute(forName: attributeName), !attributeName.isEmpty else { continue }
            let canonicalAttributeName = canonicalInlineName(from: attributeName)
            guard allowedAttributes.contains(canonicalAttributeName) else {
                throw BikeToolCoreError(message: "Invalid --rich-text fragment: attribute '\(attributeName)' is not allowed on <\(rawName)>.")
            }
            if canonicalName == "a", canonicalAttributeName == "href",
               attributeValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                throw BikeToolCoreError(message: "Invalid --rich-text fragment: <a> requires non-empty href.")
            }
            copied.setAttribute(name: attributeName, value: attributeValue)
        }

        if canonicalName == "a", copied.attribute(forName: "href") == nil {
            throw BikeToolCoreError(message: "Invalid --rich-text fragment: <a> requires href attribute.")
        }

        for child in element.children {
            copied.addChild(try sanitizeInlineNode(child))
        }
        return copied
    }

    private func canonicalInlineName(from rawName: String) -> String {
        rawName.split(separator: ":").last.map(String.init) ?? rawName
    }

    private func extractLinks(from paragraph: BikeXMLElement) -> [RowLink] {
        collectAnchorElements(in: paragraph).compactMap { anchor in
            guard let href = anchor.attribute(forName: "href")?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !href.isEmpty
            else {
                return nil
            }
            let text = anchor.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = anchor.attribute(forName: "title")
            let rel = anchor.attribute(forName: "rel")
            return RowLink(href: href, text: text, title: title, rel: rel)
        }
    }

    private func collectAnchorElements(in element: BikeXMLElement) -> [BikeXMLElement] {
        var anchors: [BikeXMLElement] = []
        for child in element.children {
            guard let childElement = child.element else { continue }
            if isElement(childElement, named: "a") {
                anchors.append(childElement)
            }
            anchors.append(contentsOf: collectAnchorElements(in: childElement))
        }
        return anchors
    }

    private func isElement(_ element: BikeXMLElement, named expectedName: String) -> Bool {
        element.isNamed(expectedName)
    }

    private static func iso8601Now() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter.string(from: Date())
    }

    private static func normalizeStoredType(_ rawType: String) -> String {
        let trimmed = rawType.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare("body") == .orderedSame {
            return "item"
        }
        if trimmed.caseInsensitiveCompare("item") == .orderedSame {
            return "item"
        }
        return trimmed
    }

    private func upsertParagraph(in li: BikeXMLElement) -> BikeXMLElement {
        if let existing = firstChildElement(named: "p", in: li) {
            return existing
        }

        let paragraph = BikeXMLElement(name: "p")
        if li.children.isEmpty {
            li.addChild(BikeXMLNode(element: paragraph))
        } else {
            li.insertChild(BikeXMLNode(element: paragraph), at: 0)
        }
        return paragraph
    }
}
