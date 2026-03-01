import Foundation
import BikeToolCore

struct CLIError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

@main
struct BikeTool {
    static let addTypeUsage = "item|body|task|note|heading|quote|code|ordered|unordered"
    static let canonicalAddTypes: Set<String> = [
        "item",
        "task",
        "note",
        "heading",
        "quote",
        "code",
        "ordered",
        "unordered",
    ]

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
        case "add-rich":
            try handleAddRich(args: Array(args.dropFirst()))
        case "set-rich-text":
            try handleSetRichText(args: Array(args.dropFirst()))
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
          bike-tool add <file.bike> --text "<text>" [--parent-id <id>] [--type \(addTypeUsage)] [--before-id <row-id> | --after-id <row-id> | --at-start | --at-end] [--write-mode coordinated|atomic|inplace] [--backup-mode managed|inline|none]
          bike-tool add-link <file.bike> --href "<uri>" [--text "<label>"] [--parent-id <id>] [--type \(addTypeUsage)] [--write-mode coordinated|atomic|inplace] [--backup-mode managed|inline|none]
          bike-tool add-rich <file.bike> --rich-text "<inline-xml-fragment>" [--parent-id <id>] [--type \(addTypeUsage)] [--before-id <row-id> | --after-id <row-id> | --at-start | --at-end] [--write-mode coordinated|atomic|inplace] [--backup-mode managed|inline|none]
          bike-tool set-rich-text <file.bike> --id <id> --rich-text "<inline-xml-fragment>" [--write-mode coordinated|atomic|inplace] [--backup-mode managed|inline|none]
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
            throw CLIError(message: "Usage: bike-tool add <file.bike> --text \"<text>\" [--parent-id <id>] [--type \(addTypeUsage)] [--before-id <row-id> | --after-id <row-id> | --at-start | --at-end] [--write-mode coordinated|atomic|inplace] [--backup-mode managed|inline|none]")
        }
        let flags = try parseFlags(Array(args.dropFirst()))
        guard let text = flags["text"] else {
            throw CLIError(message: "Missing required flag: --text")
        }
        let writeMode = try parseWriteMode(flags: flags)
        let backupMode = try parseBackupMode(flags: flags)
        let parentID = flags["parent-id"]
        let placement = try parseAddPlacement(flags: flags)
        let type = try parseAddType(rawValue: flags["type"], defaultType: "item")

        let bike = try BikeDocument(path: file)
        let newID = try bike.addRow(text: text, type: type, parentID: parentID, placement: placement)
        try bike.saveWithBackup(writeMode: writeMode, backupMode: backupMode)
        print("Added row id=\(newID)")
    }

    static func handleAddLink(args: [String]) throws {
        guard let file = args.first else {
            throw CLIError(message: "Usage: bike-tool add-link <file.bike> --href \"<uri>\" [--text \"<label>\"] [--parent-id <id>] [--type \(addTypeUsage)] [--write-mode coordinated|atomic|inplace] [--backup-mode managed|inline|none]")
        }
        let flags = try parseFlags(Array(args.dropFirst()))
        guard let href = flags["href"] else {
            throw CLIError(message: "Missing required flag: --href")
        }
        let writeMode = try parseWriteMode(flags: flags)
        let backupMode = try parseBackupMode(flags: flags)
        let parentID = flags["parent-id"]
        let type = try parseAddType(rawValue: flags["type"], defaultType: "item")

        let label = flags["text"] ?? href
        let bike = try BikeDocument(path: file)
        let newID = try bike.addLinkRow(href: href, text: label, type: type, parentID: parentID)
        try bike.saveWithBackup(writeMode: writeMode, backupMode: backupMode)
        print("Added link row id=\(newID)")
    }

    static func handleAddRich(args: [String]) throws {
        guard let file = args.first else {
            throw CLIError(message: "Usage: bike-tool add-rich <file.bike> --rich-text \"<inline-xml-fragment>\" [--parent-id <id>] [--type \(addTypeUsage)] [--before-id <row-id> | --after-id <row-id> | --at-start | --at-end] [--write-mode coordinated|atomic|inplace] [--backup-mode managed|inline|none]")
        }
        let flags = try parseFlags(Array(args.dropFirst()))
        guard let richText = flags["rich-text"] else {
            throw CLIError(message: "Missing required flag: --rich-text")
        }
        let writeMode = try parseWriteMode(flags: flags)
        let backupMode = try parseBackupMode(flags: flags)
        let parentID = flags["parent-id"]
        let placement = try parseAddPlacement(flags: flags)
        let type = try parseAddType(rawValue: flags["type"], defaultType: "item")

        let bike = try BikeDocument(path: file)
        let newID = try bike.addRichRow(richText: richText, type: type, parentID: parentID, placement: placement)
        try bike.saveWithBackup(writeMode: writeMode, backupMode: backupMode)
        print("Added rich row id=\(newID)")
    }

    static func handleSetRichText(args: [String]) throws {
        guard let file = args.first else {
            throw CLIError(message: "Usage: bike-tool set-rich-text <file.bike> --id <id> --rich-text \"<inline-xml-fragment>\" [--write-mode coordinated|atomic|inplace] [--backup-mode managed|inline|none]")
        }
        let flags = try parseFlags(Array(args.dropFirst()))
        guard let id = flags["id"] else {
            throw CLIError(message: "Missing required flag: --id")
        }
        guard let richText = flags["rich-text"] else {
            throw CLIError(message: "Missing required flag: --rich-text")
        }
        let writeMode = try parseWriteMode(flags: flags)
        let backupMode = try parseBackupMode(flags: flags)

        let bike = try BikeDocument(path: file)
        let changed = try bike.setRichText(id: id, richText: richText)
        guard changed else {
            throw CLIError(message: "No row found with id=\(id)")
        }
        try bike.saveWithBackup(writeMode: writeMode, backupMode: backupMode)
        print("Updated rich text id=\(id)")
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

    static func parseAddPlacement(flags: [String: String]) throws -> AddPlacement {
        let beforeID = flags["before-id"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let afterID = flags["after-id"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let atStartValue = flags["at-start"]
        let atEndValue = flags["at-end"]

        if let beforeID, beforeID.isEmpty {
            throw CLIError(message: "Missing value for --before-id.")
        }
        if let afterID, afterID.isEmpty {
            throw CLIError(message: "Missing value for --after-id.")
        }
        if let atStartValue, atStartValue != "true" {
            throw CLIError(message: "--at-start does not accept a value.")
        }
        if let atEndValue, atEndValue != "true" {
            throw CLIError(message: "--at-end does not accept a value.")
        }

        var setCount = 0
        if beforeID != nil { setCount += 1 }
        if afterID != nil { setCount += 1 }
        if atStartValue != nil { setCount += 1 }
        if atEndValue != nil { setCount += 1 }
        if setCount > 1 {
            throw CLIError(message: "Conflicting placement flags. Use only one of --before-id, --after-id, --at-start, --at-end.")
        }

        if let beforeID {
            return .before(id: beforeID)
        }
        if let afterID {
            return .after(id: afterID)
        }
        if atStartValue != nil {
            return .atStart
        }
        return .atEnd
    }

    static func parseAddType(rawValue: String?, defaultType: String) throws -> String {
        let candidate = (rawValue ?? defaultType)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !candidate.isEmpty else {
            throw CLIError(message: "Invalid --type ''. Use \(addTypeUsage).")
        }

        if candidate == "body" {
            return "item"
        }

        guard canonicalAddTypes.contains(candidate) else {
            throw CLIError(message: "Invalid --type '\(candidate)'. Use \(addTypeUsage).")
        }
        return candidate
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
