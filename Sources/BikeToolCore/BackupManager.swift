import Foundation

public struct BackupEntry {
    public let id: String
    public let url: URL
    public let createdDate: Date
    public let sizeBytes: Int64

    public var createdAt: String {
        BackupManager.humanDateFormatter.string(from: createdDate)
    }
}

public enum BackupManager {
    public static let defaultKeepCount = 10
    public static let defaultMaxAgeDays = 30

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

    public static func createManagedBackup(for sourceURL: URL) throws -> URL {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw BikeToolCoreError(message: "Cannot create backup. Source file not found: \(sourceURL.path)")
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

    public static func listBackups(for sourceURL: URL) throws -> [BackupEntry] {
        let sourceDirectory = sourceBackupsDirectory(for: sourceURL)
        guard FileManager.default.fileExists(atPath: sourceDirectory.path) else {
            return []
        }
        return try loadBackupEntries(in: sourceDirectory)
    }

    public static func pruneBackups(for sourceURL: URL, keep: Int, maxAgeDays: Int) throws -> Int {
        let sourceDirectory = sourceBackupsDirectory(for: sourceURL)
        guard FileManager.default.fileExists(atPath: sourceDirectory.path) else {
            return 0
        }

        let removed = try pruneEntries(in: sourceDirectory, keep: keep, maxAgeDays: maxAgeDays)
        try deleteDirectoryIfEmpty(sourceDirectory)
        return removed
    }

    public static func pruneAllBackups(keep: Int, maxAgeDays: Int) throws -> Int {
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

    public static func restoreBackup(for sourceURL: URL, backupID: String, writeMode: WriteMode) throws {
        let backupEntries = try listBackups(for: sourceURL)
        guard let backup = backupEntries.first(where: { $0.id == backupID }) else {
            throw BikeToolCoreError(message: "Backup id not found for \(sourceURL.path): \(backupID)")
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

    public static func backupRootDirectory() -> URL {
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

    public static func sourceBackupsDirectory(for sourceURL: URL) -> URL {
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

