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

    private let path: String
    private let url: URL
    private let doc: XMLDocument

    /// Loads and validates a Bike XML document from disk.
    /// - Parameter path: Absolute or relative file path to a `.bike` document.
    /// - Throws: ``BikeToolCoreError`` when the file is missing, or XML parsing/validation errors.
    public init(path: String) throws {
        self.path = path
        self.url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            throw BikeToolCoreError(message: "File not found: \(path)")
        }
        self.doc = try XMLDocument(contentsOf: url, options: [.nodePreserveAll, .documentValidate])
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
        let p = XMLElement(name: "p")
        p.stringValue = text
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
        let p = XMLElement(name: "p")
        let a = XMLElement(name: "a")
        a.addAttribute(XMLNode.attribute(withName: "href", stringValue: normalizedHref) as! XMLNode)
        a.stringValue = normalizedText.isEmpty ? normalizedHref : normalizedText
        p.addChild(a)
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

    private func addRow(type: String, paragraph: XMLElement, parentID: String?, placement: AddPlacement) throws -> String {
        let normalizedType = Self.normalizeStoredType(type)
        guard !normalizedType.isEmpty else {
            throw BikeToolCoreError(message: "Row type must not be empty.")
        }

        let li = XMLElement(name: "li")
        let id = try generateUniqueID()
        li.addAttribute(XMLNode.attribute(withName: "id", stringValue: id) as! XMLNode)
        if normalizedType != "item" {
            li.addAttribute(XMLNode.attribute(withName: "data-type", stringValue: normalizedType) as! XMLNode)
        }
        li.addChild(paragraph)

        switch placement {
        case .atEnd:
            if let parentID {
                guard let parent = findLI(id: parentID) else {
                    throw BikeToolCoreError(message: "Parent id not found: \(parentID)")
                }
                if let childUL = firstChildElement(named: "ul", in: parent) {
                    childUL.addChild(li)
                } else {
                    let newUL = XMLElement(name: "ul")
                    newUL.addChild(li)
                    parent.addChild(newUL)
                }
            } else {
                let rootUL = try topUL()
                rootUL.addChild(li)
            }
        case .atStart:
            if let parentID {
                guard let parent = findLI(id: parentID) else {
                    throw BikeToolCoreError(message: "Parent id not found: \(parentID)")
                }
                if let childUL = firstChildElement(named: "ul", in: parent) {
                    let startIndex = firstListItemIndex(in: childUL)
                    childUL.insertChild(li, at: startIndex)
                } else {
                    let newUL = XMLElement(name: "ul")
                    newUL.addChild(li)
                    parent.addChild(newUL)
                }
            } else {
                let rootUL = try topUL()
                let startIndex = firstListItemIndex(in: rootUL)
                rootUL.insertChild(li, at: startIndex)
            }
        case .before(let targetID), .after(let targetID):
            guard let target = findLI(id: targetID) else {
                throw BikeToolCoreError(message: "Target id not found: \(targetID)")
            }
            guard let siblingsUL = target.parent as? XMLElement, siblingsUL.name == "ul" else {
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
            siblingsUL.insertChild(li, at: insertionIndex)
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
            li.addAttribute(XMLNode.attribute(withName: "data-done", stringValue: doneValue) as! XMLNode)
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

        let existingChildren = p.children ?? []
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
        let outData = try serializedXML()
        switch writeMode {
        case .coordinated:
            try writeCoordinated(outData, backupMode: backupMode)
        case .atomic:
            try writeNonCoordinated(outData, atomic: true, backupMode: backupMode)
        case .inplace:
            try writeNonCoordinated(outData, atomic: false, backupMode: backupMode)
        }
    }

    private func serializedXML() throws -> Data {
        doc.characterEncoding = "UTF-8"
        doc.version = "1.0"
        // Avoid pretty-print rewriting inside inline-rich <p> content. Pretty print introduces
        // indentation/newline text nodes around mixed inline elements (for example <strong> + text).
        let xmlData = doc.xmlData(options: [.nodeCompactEmptyElement])
        guard var xml = String(data: xmlData, encoding: .utf8) else {
            throw BikeToolCoreError(message: "Unable to serialize XML as UTF-8.")
        }

        if !xml.hasPrefix("<?xml") {
            xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" + xml
        }
        // XMLDocument may emit <meta ...> in HTML style; normalize for strict XML parsing.
        xml = xml.replacingOccurrences(of: "<meta charset=\"utf-8\">", with: "<meta charset=\"utf-8\"/>")

        guard let outData = xml.data(using: .utf8) else {
            throw BikeToolCoreError(message: "Unable to encode XML output as UTF-8.")
        }
        return outData
    }

    private func writeNonCoordinated(_ data: Data, atomic: Bool, backupMode: BackupMode) throws {
        try writeBackup(for: url, mode: backupMode)
        if atomic {
            try data.write(to: url, options: .atomic)
        } else {
            try data.write(to: url)
        }
    }

    private func writeCoordinated(_ data: Data, backupMode: BackupMode) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinatorError: NSError?
        var writeError: Error?

        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { coordinatedURL in
            do {
                try writeBackup(for: coordinatedURL, mode: backupMode)
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

    private func topUL() throws -> XMLElement {
        guard
            let body = try doc.nodes(forXPath: "/html/body").first as? XMLElement,
            let rootUL = firstChildElement(named: "ul", in: body)
        else {
            throw BikeToolCoreError(message: "Invalid Bike structure. Expected /html/body/ul.")
        }
        return rootUL
    }

    private func parseRows(in ul: XMLElement) -> [Row] {
        let lis = ul.children?.compactMap { $0 as? XMLElement }.filter { $0.name == "li" } ?? []
        return lis.map { parseRow(from: $0) }
    }

    private func parseRow(from li: XMLElement) -> Row {
        let attrs = allAttributes(from: li)
        let id = attrs["id"] ?? ""
        let type = attrs["data-type"]
        let done = attrs["data-done"]
        let p = firstChildElement(named: "p", in: li)
        let text = p?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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

    private func findLI(id: String) -> XMLElement? {
        let escaped = id.replacingOccurrences(of: "'", with: "&apos;")
        let xpath = "//li[@id='\(escaped)']"
        return try? doc.nodes(forXPath: xpath).first as? XMLElement
    }

    private func firstChildElement(named: String, in element: XMLElement) -> XMLElement? {
        element.children?.first { node in
            guard let el = node as? XMLElement else { return false }
            return el.name == named
        } as? XMLElement
    }

    private func generateID() -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        return String((0..<6).map { _ in chars.randomElement()! })
    }

    private func firstListItemIndex(in ul: XMLElement) -> Int {
        guard let children = ul.children else { return 0 }
        for (index, child) in children.enumerated() {
            guard let childElement = child as? XMLElement else { continue }
            if childElement.name == "li" {
                return index
            }
        }
        return children.count
    }

    private func listItemIndex(of target: XMLElement, in ul: XMLElement) -> Int? {
        guard let children = ul.children else { return nil }
        for (index, child) in children.enumerated() {
            guard let childElement = child as? XMLElement else { continue }
            if childElement === target {
                return index
            }
        }
        return nil
    }

    private func inferredParentRowID(forSiblingsUL ul: XMLElement) throws -> String? {
        let rootUL = try topUL()
        if ul === rootUL {
            return nil
        }
        guard let parentLI = ul.parent as? XMLElement, parentLI.name == "li" else {
            throw BikeToolCoreError(message: "Invalid Bike structure. Expected nested rows under li/ul.")
        }
        guard let parentID = parentLI.attribute(forName: "id")?.stringValue, !parentID.isEmpty else {
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

    private func allAttributes(from element: XMLElement) -> [String: String] {
        let attrs = element.attributes ?? []
        var out: [String: String] = [:]
        for attr in attrs {
            guard let name = attr.name else { continue }
            out[name] = attr.stringValue ?? ""
        }
        return out
    }

    private func innerXML(of element: XMLElement) -> String {
        let children = element.children ?? []
        return children.map { $0.xmlString(options: []) }.joined()
    }

    private func paragraphFromRichText(_ richText: String) throws -> XMLElement {
        let p = XMLElement(name: "p")
        let richChildren = try parseRichTextFragment(richText)
        for child in richChildren {
            p.addChild(child)
        }
        return p
    }

    private func parseRichTextFragment(_ fragment: String) throws -> [XMLNode] {
        if fragment.isEmpty {
            return []
        }

        // Plain text input with no tag delimiters should be accepted directly.
        if !fragment.contains("<"), !fragment.contains(">") {
            return [XMLNode.text(withStringValue: fragment) as! XMLNode]
        }

        let wrapped = "<root>\(fragment)</root>"
        let parsedDoc: XMLDocument
        do {
            parsedDoc = try XMLDocument(xmlString: wrapped, options: [.nodePreserveAll])
        } catch {
            throw BikeToolCoreError(message: "Invalid --rich-text fragment: not well-formed XML.")
        }

        guard let root = parsedDoc.rootElement() else {
            throw BikeToolCoreError(message: "Invalid --rich-text fragment: unable to parse root container.")
        }

        let children = root.children ?? []
        return try children.map { try sanitizeInlineNode($0) }
    }

    private func sanitizeInlineNode(_ node: XMLNode) throws -> XMLNode {
        switch node.kind {
        case .text:
            return XMLNode.text(withStringValue: node.stringValue ?? "") as! XMLNode
        case .element:
            guard let element = node as? XMLElement else {
                throw BikeToolCoreError(message: "Invalid --rich-text fragment: malformed element node.")
            }
            return try sanitizeInlineElement(element)
        default:
            throw BikeToolCoreError(message: "Invalid --rich-text fragment: unsupported node kind in paragraph content.")
        }
    }

    private func sanitizeInlineElement(_ element: XMLElement) throws -> XMLElement {
        guard let rawName = element.name, !rawName.isEmpty else {
            throw BikeToolCoreError(message: "Invalid --rich-text fragment: encountered unnamed element.")
        }

        let canonicalName = canonicalInlineName(from: rawName)
        guard Self.allowedInlineTagNames.contains(canonicalName) else {
            throw BikeToolCoreError(message: "Invalid --rich-text fragment: unsupported tag '\(rawName)'.")
        }

        let allowedAttributes = Self.allowedInlineAttributesByTag[canonicalName] ?? []
        let copied = XMLElement(name: rawName)
        for attribute in element.attributes ?? [] {
            guard let attributeName = attribute.name, !attributeName.isEmpty else { continue }
            let canonicalAttributeName = canonicalInlineName(from: attributeName)
            guard allowedAttributes.contains(canonicalAttributeName) else {
                throw BikeToolCoreError(message: "Invalid --rich-text fragment: attribute '\(attributeName)' is not allowed on <\(rawName)>.")
            }
            let attributeValue = attribute.stringValue ?? ""
            if canonicalName == "a", canonicalAttributeName == "href",
               attributeValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                throw BikeToolCoreError(message: "Invalid --rich-text fragment: <a> requires non-empty href.")
            }
            copied.addAttribute(XMLNode.attribute(withName: attributeName, stringValue: attributeValue) as! XMLNode)
        }

        if canonicalName == "a", copied.attribute(forName: "href") == nil {
            throw BikeToolCoreError(message: "Invalid --rich-text fragment: <a> requires href attribute.")
        }

        for child in element.children ?? [] {
            copied.addChild(try sanitizeInlineNode(child))
        }
        return copied
    }

    private func canonicalInlineName(from rawName: String) -> String {
        rawName.split(separator: ":").last.map(String.init) ?? rawName
    }

    private func extractLinks(from paragraph: XMLElement) -> [RowLink] {
        collectAnchorElements(in: paragraph).compactMap { anchor in
            guard let href = anchor.attribute(forName: "href")?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !href.isEmpty
            else {
                return nil
            }
            let text = anchor.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? href
            let title = anchor.attribute(forName: "title")?.stringValue
            let rel = anchor.attribute(forName: "rel")?.stringValue
            return RowLink(href: href, text: text, title: title, rel: rel)
        }
    }

    private func collectAnchorElements(in element: XMLElement) -> [XMLElement] {
        var anchors: [XMLElement] = []
        for child in element.children ?? [] {
            guard let childElement = child as? XMLElement else { continue }
            if isElement(childElement, named: "a") {
                anchors.append(childElement)
            }
            anchors.append(contentsOf: collectAnchorElements(in: childElement))
        }
        return anchors
    }

    private func isElement(_ element: XMLElement, named expectedName: String) -> Bool {
        if let localName = element.localName {
            return localName == expectedName
        }
        guard let name = element.name else { return false }
        return name == expectedName || name.split(separator: ":").last == Substring(expectedName)
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

    private func upsertParagraph(in li: XMLElement) -> XMLElement {
        if let existing = firstChildElement(named: "p", in: li) {
            return existing
        }

        let paragraph = XMLElement(name: "p")
        let children = li.children ?? []
        if children.isEmpty {
            li.addChild(paragraph)
        } else {
            li.insertChild(paragraph, at: 0)
        }
        return paragraph
    }
}
