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

struct Row {
    let id: String
    let type: String?
    let text: String
    let richText: String
    let done: String?
    let attributes: [String: String]
    let children: [Row]
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
        case "done":
            try handleDone(args: Array(args.dropFirst()), markDone: true)
        case "undone":
            try handleDone(args: Array(args.dropFirst()), markDone: false)
        case "delete":
            try handleDelete(args: Array(args.dropFirst()))
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
          bike-tool add <file.bike> --text "<text>" [--parent-id <id>] [--type task|note|heading] [--write-mode coordinated|atomic|inplace]
          bike-tool done <file.bike> --id <id> [--write-mode coordinated|atomic|inplace]
          bike-tool undone <file.bike> --id <id> [--write-mode coordinated|atomic|inplace]
          bike-tool delete <file.bike> --id <id> [--write-mode coordinated|atomic|inplace]
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
            throw CLIError(message: "Usage: bike-tool add <file.bike> --text \"<text>\" [--parent-id <id>] [--type task|note|heading] [--write-mode coordinated|atomic|inplace]")
        }
        let flags = try parseFlags(Array(args.dropFirst()))
        guard let text = flags["text"] else {
            throw CLIError(message: "Missing required flag: --text")
        }
        let writeMode = try parseWriteMode(flags: flags)
        let parentID = flags["parent-id"]
        let type = flags["type"] ?? "task"
        guard ["task", "note", "heading"].contains(type) else {
            throw CLIError(message: "Invalid --type '\(type)'. Use task|note|heading.")
        }

        let bike = try BikeDocument(path: file)
        let newID = try bike.addRow(text: text, type: type, parentID: parentID)
        try bike.saveWithBackup(writeMode: writeMode)
        print("Added row id=\(newID)")
    }

    static func handleDone(args: [String], markDone: Bool) throws {
        guard let file = args.first else {
            let cmd = markDone ? "done" : "undone"
            throw CLIError(message: "Usage: bike-tool \(cmd) <file.bike> --id <id>")
        }
        let flags = try parseFlags(Array(args.dropFirst()))
        guard let id = flags["id"] else {
            throw CLIError(message: "Missing required flag: --id")
        }
        let writeMode = try parseWriteMode(flags: flags)

        let bike = try BikeDocument(path: file)
        let changed = try bike.setDone(id: id, markDone: markDone)
        guard changed else {
            throw CLIError(message: "No row found with id=\(id)")
        }
        try bike.saveWithBackup(writeMode: writeMode)
        if markDone {
            print("Marked done id=\(id)")
        } else {
            print("Marked undone id=\(id)")
        }
    }

    static func handleDelete(args: [String]) throws {
        guard let file = args.first else {
            throw CLIError(message: "Usage: bike-tool delete <file.bike> --id <id> [--write-mode coordinated|atomic|inplace]")
        }
        let flags = try parseFlags(Array(args.dropFirst()))
        guard let id = flags["id"] else {
            throw CLIError(message: "Missing required flag: --id")
        }
        let writeMode = try parseWriteMode(flags: flags)

        let bike = try BikeDocument(path: file)
        let changed = try bike.deleteRow(id: id)
        guard changed else {
            throw CLIError(message: "No row found with id=\(id)")
        }
        try bike.saveWithBackup(writeMode: writeMode)
        print("Deleted id=\(id)")
    }

    static func parseWriteMode(flags: [String: String]) throws -> WriteMode {
        let raw = flags["write-mode"] ?? WriteMode.coordinated.rawValue
        guard let mode = WriteMode(rawValue: raw) else {
            throw CLIError(message: "Invalid --write-mode '\(raw)'. Use coordinated|atomic|inplace.")
        }
        return mode
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
        let li = XMLElement(name: "li")
        let id = try generateUniqueID()
        li.addAttribute(XMLNode.attribute(withName: "id", stringValue: id) as! XMLNode)
        li.addAttribute(XMLNode.attribute(withName: "data-type", stringValue: type) as! XMLNode)

        let p = XMLElement(name: "p")
        p.stringValue = text
        li.addChild(p)

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

    func saveWithBackup(writeMode: WriteMode = .coordinated) throws {
        let outData = try serializedXML()
        switch writeMode {
        case .coordinated:
            try writeCoordinated(outData)
        case .atomic:
            try writeNonCoordinated(outData, atomic: true)
        case .inplace:
            try writeNonCoordinated(outData, atomic: false)
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

    private func writeNonCoordinated(_ data: Data, atomic: Bool) throws {
        try writeBackup(for: url)
        if atomic {
            try data.write(to: url, options: .atomic)
        } else {
            try data.write(to: url)
        }
    }

    private func writeCoordinated(_ data: Data) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinatorError: NSError?
        var writeError: Error?

        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { coordinatedURL in
            do {
                try writeBackup(for: coordinatedURL)
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

    private func writeBackup(for sourceURL: URL) throws {
        let backupURL = URL(fileURLWithPath: sourceURL.path + ".bak")
        if FileManager.default.fileExists(atPath: backupURL.path) {
            try FileManager.default.removeItem(at: backupURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: backupURL)
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

        var children: [Row] = []
        if let childUL = firstChildElement(named: "ul", in: li) {
            children = parseRows(in: childUL)
        }
        return Row(
            id: id,
            type: type,
            text: text,
            richText: richText,
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

    private static func iso8601Now() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter.string(from: Date())
    }
}

struct EncodableRow: Encodable {
    let id: String
    let type: String?
    let text: String
    let richText: String?
    let done: String?
    let attributes: [String: String]
    let children: [EncodableRow]

    init(from row: Row, includeRichText: Bool) {
        id = row.id
        type = row.type
        text = row.text
        richText = includeRichText ? row.richText : nil
        done = row.done
        attributes = row.attributes
        children = row.children.map { EncodableRow(from: $0, includeRichText: includeRichText) }
    }
}
