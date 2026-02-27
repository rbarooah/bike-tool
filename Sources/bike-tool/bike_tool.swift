import Foundation

struct CLIError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

enum WriteMode: String {
    case coordinated
    case atomic
    case inplace
}

enum BackupMode: String {
    case managed
    case inline
    case none
}

struct Row {
    let id: String
    let type: String?
    let text: String
    let richText: String
    let links: [RowLink]
    let done: String?
    let attributes: [String: String]
    let children: [Row]
}

struct RowLink: Encodable {
    let href: String
    let text: String
    let title: String?
    let rel: String?
}

@main
struct BikeTool {
    static func main() {
        do {
            try run()
        } catch {
            fputs("Error: \(error)\n", stderr)
            exit(1)
        }
    }

    static func run() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            printHelp()
            return
        }

        switch command {
        case "help", "--help", "-h":
            printHelp()
        case "validate":
            try handleValidate(args: Array(args.dropFirst()))
        case "list":
            try handleList(args: Array(args.dropFirst()))
        case "to-json":
            try handleToJSON(args: Array(args.dropFirst()))
        case "add":
            try handleAdd(args: Array(args.dropFirst()))
        case "add-link":
            try handleAddLink(args: Array(args.dropFirst()))
        case "done":
            try handleDone(args: Array(args.dropFirst()), markDone: true)
        case "undone":
            try handleDone(args: Array(args.dropFirst()), markDone: false)
        case "delete":
            try handleDelete(args: Array(args.dropFirst()))
        case "backup":
            try handleBackup(args: Array(args.dropFirst()))
        default:
            throw CLIError(message: "Unknown command '\(command)'. Run 'bike-tool help'.")
        }
    }

    static func printHelp() {
        print("""
        bike-tool - CLI for .bike outline files

        Usage:
          bike-tool help
          bike-tool validate <file.bike>
          bike-tool list <file.bike>
          bike-tool to-json <file.bike> [--rich-text]
          bike-tool add <file.bike> --text "<text>" [--parent-id <id>] [--type task|note|heading] [--write-mode coordinated|atomic|inplace] [--backup-mode managed|inline|none]
          bike-tool add-link <file.bike> --href "<uri>" [--text "<label>"] [--parent-id <id>] [--type task|note|heading] [--write-mode coordinated|atomic|inplace] [--backup-mode managed|inline|none]
          bike-tool done <file.bike> --id <id> [--write-mode coordinated|atomic|inplace] [--backup-mode managed|inline|none]
          bike-tool undone <file.bike> --id <id> [--write-mode coordinated|atomic|inplace] [--backup-mode managed|inline|none]
          bike-tool delete <file.bike> --id <id> [--write-mode coordinated|atomic|inplace] [--backup-mode managed|inline|none]
          bike-tool backup list <file.bike>
          bike-tool backup prune [<file.bike>] [--keep <count>] [--days <count>]
          bike-tool backup restore <file.bike> --id <backup-id> [--write-mode coordinated|atomic|inplace]
        """)
    }

    static func handleValidate(args: [String]) throws {
        guard args.count == 1 else {
            throw CLIError(message: "Usage: bike-tool validate <file.bike>")
        }
        _ = try BikeDocument(path: args[0])
        print("OK: \(args[0]) is valid Bike XML.")
    }

    static func handleList(args: [String]) throws {
        guard args.count == 1 else {
            throw CLIError(message: "Usage: bike-tool list <file.bike>")
        }
        let bike = try BikeDocument(path: args[0])
        let rows = try bike.readRows()
        printRows(rows, indent: 0)
    }

    static func handleToJSON(args: [String]) throws {
        guard let file = args.first else {
            throw CLIError(message: "Usage: bike-tool to-json <file.bike> [--rich-text]")
        }
        let flags = try parseFlags(Array(args.dropFirst()))
        let includeRichText = flags["rich-text"] == "true"

        let bike = try BikeDocument(path: file)
        let rows = try bike.readRows()
        let encodableRows = rows.map { EncodableRow(from: $0, includeRichText: includeRichText) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(encodableRows)
        guard let json = String(data: data, encoding: .utf8) else {
            throw CLIError(message: "Unable to encode JSON as UTF-8.")
        }
        print(json)
    }

    static func handleAdd(args: [String]) throws {
        guard let file = args.first else {
            throw CLIError(message: "Usage: bike-tool add <file.bike> --text \"<text>\" [--parent-id <id>] [--type task|note|heading] [--write-mode coordinated|atomic|inplace] [--backup-mode managed|inline|none]")
        }
        let flags = try parseFlags(Array(args.dropFirst()))
        guard let text = flags["text"] else {
            throw CLIError(message: "Missing required flag: --text")
        }
        let writeMode = try parseWriteMode(flags: flags)
        let backupMode = try parseBackupMode(flags: flags)
        let parentID = flags["parent-id"]
        let type = flags["type"] ?? "task"
        guard ["task", "note", "heading"].contains(type) else {
            throw CLIError(message: "Invalid --type '\(type)'. Use task|note|heading.")
        }

        let bike = try BikeDocument(path: file)
        let newID = try bike.addRow(text: text, type: type, parentID: parentID)
        try bike.saveWithBackup(writeMode: writeMode, backupMode: backupMode)
        print("Added row id=\(newID)")
    }

    static func handleAddLink(args: [String]) throws {
        guard let file = args.first else {
            throw CLIError(message: "Usage: bike-tool add-link <file.bike> --href \"<uri>\" [--text \"<label>\"] [--parent-id <id>] [--type task|note|heading] [--write-mode coordinated|atomic|inplace] [--backup-mode managed|inline|none]")
        }
        let flags = try parseFlags(Array(args.dropFirst()))
        guard let href = flags["href"] else {
            throw CLIError(message: "Missing required flag: --href")
        }
        let writeMode = try parseWriteMode(flags: flags)
        let backupMode = try parseBackupMode(flags: flags)
        let parentID = flags["parent-id"]
        let type = flags["type"] ?? "note"
        guard ["task", "note", "heading"].contains(type) else {
            throw CLIError(message: "Invalid --type '\(type)'. Use task|note|heading.")
        }

        let label = flags["text"] ?? href
        let bike = try BikeDocument(path: file)
        let newID = try bike.addLinkRow(href: href, text: label, type: type, parentID: parentID)
        try bike.saveWithBackup(writeMode: writeMode, backupMode: backupMode)
        print("Added link row id=\(newID)")
    }

    static func handleDone(args: [String], markDone: Bool) throws {
        guard let file = args.first else {
            let cmd = markDone ? "done" : "undone"
            throw CLIError(message: "Usage: bike-tool \(cmd) <file.bike> --id <id> [--write-mode coordinated|atomic|inplace] [--backup-mode managed|inline|none]")
        }
        let flags = try parseFlags(Array(args.dropFirst()))
        guard let id = flags["id"] else {
            throw CLIError(message: "Missing required flag: --id")
        }
        let writeMode = try parseWriteMode(flags: flags)
        let backupMode = try parseBackupMode(flags: flags)

        let bike = try BikeDocument(path: file)
        let changed = try bike.setDone(id: id, markDone: markDone)
        guard changed else {
            throw CLIError(message: "No row found with id=\(id)")
        }
        try bike.saveWithBackup(writeMode: writeMode, backupMode: backupMode)
        if markDone {
            print("Marked done id=\(id)")
        } else {
            print("Marked undone id=\(id)")
        }
    }

    static func handleDelete(args: [String]) throws {
        guard let file = args.first else {
            throw CLIError(message: "Usage: bike-tool delete <file.bike> --id <id> [--write-mode coordinated|atomic|inplace] [--backup-mode managed|inline|none]")
        }
        let flags = try parseFlags(Array(args.dropFirst()))
        guard let id = flags["id"] else {
            throw CLIError(message: "Missing required flag: --id")
        }
        let writeMode = try parseWriteMode(flags: flags)
        let backupMode = try parseBackupMode(flags: flags)

        let bike = try BikeDocument(path: file)
        let changed = try bike.deleteRow(id: id)
        guard changed else {
            throw CLIError(message: "No row found with id=\(id)")
        }
        try bike.saveWithBackup(writeMode: writeMode, backupMode: backupMode)
        print("Deleted id=\(id)")
    }

    static func handleBackup(args: [String]) throws {
        guard let subcommand = args.first else {
            throw CLIError(message: "Usage: bike-tool backup list <file.bike> | bike-tool backup prune [<file.bike>] [--keep <count>] [--days <count>] | bike-tool backup restore <file.bike> --id <backup-id> [--write-mode coordinated|atomic|inplace]")
        }

        switch subcommand {
        case "list":
            guard args.count == 2 else {
                throw CLIError(message: "Usage: bike-tool backup list <file.bike>")
            }
            let fileURL = URL(fileURLWithPath: args[1]).standardizedFileURL
            let backups = try BackupManager.listBackups(for: fileURL)
            if backups.isEmpty {
                print("No backups found for \(fileURL.path)")
                return
            }
            for backup in backups {
                print("\(backup.id)\t\(backup.createdAt)\t\(backup.sizeBytes) bytes")
            }
        case "prune":
            var tail = Array(args.dropFirst())
            var fileURL: URL?
            if let first = tail.first, !first.hasPrefix("--") {
                fileURL = URL(fileURLWithPath: first).standardizedFileURL
                tail.removeFirst()
            }
            let flags = try parseFlags(tail)
            let keep = try parsePositiveIntFlag(flags["keep"], name: "keep", defaultValue: BackupManager.defaultKeepCount)
            let days = try parsePositiveIntFlag(flags["days"], name: "days", defaultValue: BackupManager.defaultMaxAgeDays)
            let removedCount: Int
            if let fileURL {
                removedCount = try BackupManager.pruneBackups(for: fileURL, keep: keep, maxAgeDays: days)
            } else {
                removedCount = try BackupManager.pruneAllBackups(keep: keep, maxAgeDays: days)
            }
            print("Pruned \(removedCount) backups.")
        case "restore":
            guard args.count >= 3 else {
                throw CLIError(message: "Usage: bike-tool backup restore <file.bike> --id <backup-id> [--write-mode coordinated|atomic|inplace]")
            }
            let fileURL = URL(fileURLWithPath: args[1]).standardizedFileURL
            let flags = try parseFlags(Array(args.dropFirst(2)))
            guard let backupID = flags["id"] else {
                throw CLIError(message: "Missing required flag: --id")
            }
            let writeMode = try parseWriteMode(flags: flags)
            try BackupManager.restoreBackup(for: fileURL, backupID: backupID, writeMode: writeMode)
            print("Restored \(fileURL.path) from backup id=\(backupID)")
        default:
            throw CLIError(message: "Unknown backup subcommand '\(subcommand)'. Use list|prune|restore.")
        }
    }

    static func parseWriteMode(flags: [String: String]) throws -> WriteMode {
        let raw = flags["write-mode"] ?? WriteMode.coordinated.rawValue
        guard let mode = WriteMode(rawValue: raw) else {
            throw CLIError(message: "Invalid --write-mode '\(raw)'. Use coordinated|atomic|inplace.")
        }
        return mode
    }

    static func parseBackupMode(flags: [String: String]) throws -> BackupMode {
        let raw = flags["backup-mode"] ?? BackupMode.managed.rawValue
        guard let mode = BackupMode(rawValue: raw) else {
            throw CLIError(message: "Invalid --backup-mode '\(raw)'. Use managed|inline|none.")
        }
        return mode
    }

    static func parsePositiveIntFlag(_ rawValue: String?, name: String, defaultValue: Int) throws -> Int {
        guard let rawValue else { return defaultValue }
        guard let parsed = Int(rawValue), parsed > 0 else {
            throw CLIError(message: "Invalid --\(name) '\(rawValue)'. Use a positive integer.")
        }
        return parsed
    }

    static func parseFlags(_ args: [String]) throws -> [String: String] {
        var out: [String: String] = [:]
        var i = 0
        while i < args.count {
            let token = args[i]
            guard token.hasPrefix("--") else {
                throw CLIError(message: "Unexpected argument '\(token)'. Flags must use --name value.")
            }
            let key = String(token.dropFirst(2))
            if i + 1 < args.count, !args[i + 1].hasPrefix("--") {
                out[key] = args[i + 1]
                i += 2
            } else {
                out[key] = "true"
                i += 1
            }
        }
        return out
    }

    static func printRows(_ rows: [Row], indent: Int) {
        for row in rows {
            let pad = String(repeating: "  ", count: indent)
            let doneMark = row.done == nil ? "[ ]" : "[x]"
            let type = row.type ?? "item"
            print("\(pad)\(doneMark) \(type) \(row.id): \(row.text)")
            if !row.children.isEmpty {
                printRows(row.children, indent: indent + 1)
            }
        }
    }
}

final class BikeDocument {
    private let path: String
    private let url: URL
    private let doc: XMLDocument

    init(path: String) throws {
        self.path = path
        self.url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            throw CLIError(message: "File not found: \(path)")
        }
        self.doc = try XMLDocument(contentsOf: url, options: [.nodePreserveAll, .documentValidate])
    }

    func readRows() throws -> [Row] {
        let rootUL = try topUL()
        return parseRows(in: rootUL)
    }

    func addRow(text: String, type: String, parentID: String?) throws -> String {
        let p = XMLElement(name: "p")
        p.stringValue = text
        return try addRow(type: type, paragraph: p, parentID: parentID)
    }

    func addLinkRow(href: String, text: String, type: String, parentID: String?) throws -> String {
        let normalizedHref = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHref.isEmpty else {
            throw CLIError(message: "--href must not be empty.")
        }

        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = XMLElement(name: "p")
        let a = XMLElement(name: "a")
        a.addAttribute(XMLNode.attribute(withName: "href", stringValue: normalizedHref) as! XMLNode)
        a.stringValue = normalizedText.isEmpty ? normalizedHref : normalizedText
        p.addChild(a)
        return try addRow(type: type, paragraph: p, parentID: parentID)
    }

    private func addRow(type: String, paragraph: XMLElement, parentID: String?) throws -> String {
        let li = XMLElement(name: "li")
        let id = try generateUniqueID()
        li.addAttribute(XMLNode.attribute(withName: "id", stringValue: id) as! XMLNode)
        li.addAttribute(XMLNode.attribute(withName: "data-type", stringValue: type) as! XMLNode)
        li.addChild(paragraph)

        if let parentID {
            guard let parent = findLI(id: parentID) else {
                throw CLIError(message: "Parent id not found: \(parentID)")
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
        return id
    }

    func setDone(id: String, markDone: Bool) throws -> Bool {
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

    func deleteRow(id: String) throws -> Bool {
        guard let li = findLI(id: id) else { return false }
        li.detach()
        return true
    }

    func saveWithBackup(writeMode: WriteMode = .coordinated, backupMode: BackupMode = .managed) throws {
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
        let xmlData = doc.xmlData(options: [.nodePrettyPrint, .nodeCompactEmptyElement])
        guard var xml = String(data: xmlData, encoding: .utf8) else {
            throw CLIError(message: "Unable to serialize XML as UTF-8.")
        }

        if !xml.hasPrefix("<?xml") {
            xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" + xml
        }
        // XMLDocument may emit <meta ...> in HTML style; normalize for strict XML parsing.
        xml = xml.replacingOccurrences(of: "<meta charset=\"utf-8\">", with: "<meta charset=\"utf-8\"/>")

        guard let outData = xml.data(using: .utf8) else {
            throw CLIError(message: "Unable to encode XML output as UTF-8.")
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
            throw CLIError(message: "Invalid Bike structure. Expected /html/body/ul.")
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

    private func generateUniqueID(maxAttempts: Int = 100) throws -> String {
        for _ in 0..<maxAttempts {
            let candidate = generateID()
            if findLI(id: candidate) == nil {
                return candidate
            }
        }
        throw CLIError(message: "Unable to generate unique id after \(maxAttempts) attempts.")
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
}

struct BackupEntry {
    let id: String
    let url: URL
    let createdDate: Date
    let sizeBytes: Int64

    var createdAt: String {
        BackupManager.humanDateFormatter.string(from: createdDate)
    }
}

enum BackupManager {
    static let defaultKeepCount = 10
    static let defaultMaxAgeDays = 30

    static let humanDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZ"
        return formatter
    }()

    static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmssSSS"
        return formatter
    }()

    static func createManagedBackup(for sourceURL: URL) throws -> URL {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw CLIError(message: "Cannot create backup. Source file not found: \(sourceURL.path)")
        }

        let sourceDirectory = sourceBackupsDirectory(for: sourceURL)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)

        let timestamp = filenameDateFormatter.string(from: Date())
        let backupFileName = "\(timestamp)-\(UUID().uuidString)-\(sourceURL.lastPathComponent).bak"
        let backupURL = sourceDirectory.appendingPathComponent(backupFileName)

        try FileManager.default.copyItem(at: sourceURL, to: backupURL)

        do {
            _ = try pruneBackups(for: sourceURL, keep: defaultKeepCount, maxAgeDays: defaultMaxAgeDays)
        } catch {
            fputs("Warning: backup prune failed for \(sourceURL.path): \(error)\n", stderr)
        }
        return backupURL
    }

    static func listBackups(for sourceURL: URL) throws -> [BackupEntry] {
        let sourceDirectory = sourceBackupsDirectory(for: sourceURL)
        guard FileManager.default.fileExists(atPath: sourceDirectory.path) else {
            return []
        }
        return try loadBackupEntries(in: sourceDirectory)
    }

    static func pruneBackups(for sourceURL: URL, keep: Int, maxAgeDays: Int) throws -> Int {
        let sourceDirectory = sourceBackupsDirectory(for: sourceURL)
        guard FileManager.default.fileExists(atPath: sourceDirectory.path) else {
            return 0
        }

        let removed = try pruneEntries(in: sourceDirectory, keep: keep, maxAgeDays: maxAgeDays)
        try deleteDirectoryIfEmpty(sourceDirectory)
        return removed
    }

    static func pruneAllBackups(keep: Int, maxAgeDays: Int) throws -> Int {
        let root = backupRootDirectory()
        guard FileManager.default.fileExists(atPath: root.path) else {
            return 0
        }

        let directories = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var removed = 0
        for directory in directories {
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }
            removed += try pruneEntries(in: directory, keep: keep, maxAgeDays: maxAgeDays)
            try deleteDirectoryIfEmpty(directory)
        }
        return removed
    }

    static func restoreBackup(for sourceURL: URL, backupID: String, writeMode: WriteMode) throws {
        let backupEntries = try listBackups(for: sourceURL)
        guard let backup = backupEntries.first(where: { $0.id == backupID }) else {
            throw CLIError(message: "Backup id not found for \(sourceURL.path): \(backupID)")
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: sourceURL.path) {
            _ = try createManagedBackup(for: sourceURL)
        } else {
            let parentDirectory = sourceURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        }

        let backupData = try Data(contentsOf: backup.url)
        switch writeMode {
        case .coordinated:
            if fileManager.fileExists(atPath: sourceURL.path) {
                let coordinator = NSFileCoordinator(filePresenter: nil)
                var coordinatorError: NSError?
                var writeError: Error?
                coordinator.coordinate(writingItemAt: sourceURL, options: .forReplacing, error: &coordinatorError) { coordinatedURL in
                    do {
                        try backupData.write(to: coordinatedURL, options: .atomic)
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
            } else {
                try backupData.write(to: sourceURL, options: .atomic)
            }
        case .atomic:
            try backupData.write(to: sourceURL, options: .atomic)
        case .inplace:
            try backupData.write(to: sourceURL)
        }
    }

    static func backupRootDirectory() -> URL {
        if let explicit = ProcessInfo.processInfo.environment["BIKETOOL_BACKUP_DIR"], !explicit.isEmpty {
            return URL(fileURLWithPath: explicit, isDirectory: true).standardizedFileURL
        }

        let codexHome: String
        if let configured = ProcessInfo.processInfo.environment["CODEX_HOME"], !configured.isEmpty {
            codexHome = configured
        } else {
            codexHome = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent(".codex", isDirectory: true)
                .path
        }

        return URL(fileURLWithPath: codexHome, isDirectory: true)
            .appendingPathComponent("state", isDirectory: true)
            .appendingPathComponent("bike-tool", isDirectory: true)
            .appendingPathComponent("backups", isDirectory: true)
            .standardizedFileURL
    }

    static func sourceBackupsDirectory(for sourceURL: URL) -> URL {
        let canonicalPath = sourceURL.standardizedFileURL.path
        var encoded = Data(canonicalPath.utf8).base64EncodedString()
        encoded = encoded
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        if encoded.isEmpty {
            encoded = "root"
        }
        return backupRootDirectory().appendingPathComponent(encoded, isDirectory: true)
    }

    private static func loadBackupEntries(in directory: URL) throws -> [BackupEntry] {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .creationDateKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        var entries: [BackupEntry] = []
        for file in files where file.pathExtension == "bak" {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .creationDateKey, .contentModificationDateKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            let createdDate = values.creationDate ?? values.contentModificationDate ?? .distantPast
            let sizeBytes = Int64(values.fileSize ?? 0)
            entries.append(BackupEntry(id: file.lastPathComponent, url: file, createdDate: createdDate, sizeBytes: sizeBytes))
        }

        entries.sort { $0.createdDate > $1.createdDate }
        return entries
    }

    private static func pruneEntries(in directory: URL, keep: Int, maxAgeDays: Int) throws -> Int {
        let entries = try loadBackupEntries(in: directory)
        guard !entries.isEmpty else { return 0 }

        let cutoffDate = Date().addingTimeInterval(-TimeInterval(maxAgeDays * 86_400))
        var removed = 0
        for (index, entry) in entries.enumerated() {
            if index >= keep || entry.createdDate < cutoffDate {
                try FileManager.default.removeItem(at: entry.url)
                removed += 1
            }
        }
        return removed
    }

    private static func deleteDirectoryIfEmpty(_ directory: URL) throws {
        let remaining = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        if remaining.isEmpty {
            try FileManager.default.removeItem(at: directory)
        }
    }
}

struct EncodableRow: Encodable {
    let id: String
    let type: String?
    let text: String
    let richText: String?
    let links: [RowLink]?
    let done: String?
    let attributes: [String: String]
    let children: [EncodableRow]

    init(from row: Row, includeRichText: Bool) {
        id = row.id
        type = row.type
        text = row.text
        richText = includeRichText ? row.richText : nil
        links = row.links.isEmpty ? nil : row.links
        done = row.done
        attributes = row.attributes
        children = row.children.map { EncodableRow(from: $0, includeRichText: includeRichText) }
    }
}
