import Foundation

/// Metadata describing a stored managed backup file.
public struct BackupEntry {
    /// Backup file identifier (filename).
    public let id: String
    /// Full backup file URL.
    public let url: URL
    /// Backup creation/modification timestamp used for ordering/pruning.
    public let createdDate: Date
    /// Backup file size in bytes.
    public let sizeBytes: Int64

    /// Human-readable local timestamp for display.
    public var createdAt: String {
        BackupManager.humanDateFormatter.string(from: createdDate)
    }
}

/// Managed backup storage and lifecycle utilities for `.bike` files.
public enum BackupManager {
    /// Default number of recent backups retained per source file.
    public static let defaultKeepCount = 10
    /// Default maximum backup age in days.
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

    /// Creates a managed backup for a source file and applies default pruning.
    /// - Parameter sourceURL: URL of the source `.bike` file.
    /// - Returns: URL of the newly created backup.
    /// - Throws: ``BikeToolCoreError`` when source file is missing or copy/prune operations fail.
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

    /// Lists managed backups for a source file, newest first.
    /// - Parameter sourceURL: URL of the source `.bike` file.
    /// - Returns: Backup metadata entries sorted by creation date descending.
    /// - Throws: File-system errors when backup directory contents cannot be read.
    public static func listBackups(for sourceURL: URL) throws -> [BackupEntry] {
        let sourceDirectory = sourceBackupsDirectory(for: sourceURL)
        guard FileManager.default.fileExists(atPath: sourceDirectory.path) else {
            return []
        }
        return try loadBackupEntries(in: sourceDirectory)
    }

    /// Prunes managed backups for one source file by count and age policy.
    /// - Parameters:
    ///   - sourceURL: URL of the source `.bike` file.
    ///   - keep: Maximum number of newest backups to retain.
    ///   - maxAgeDays: Maximum backup age in days.
    /// - Returns: Number of removed backup files.
    /// - Throws: File-system errors when pruning fails.
    public static func pruneBackups(for sourceURL: URL, keep: Int, maxAgeDays: Int) throws -> Int {
        let sourceDirectory = sourceBackupsDirectory(for: sourceURL)
        guard FileManager.default.fileExists(atPath: sourceDirectory.path) else {
            return 0
        }

        let removed = try pruneEntries(in: sourceDirectory, keep: keep, maxAgeDays: maxAgeDays)
        try deleteDirectoryIfEmpty(sourceDirectory)
        return removed
    }

    /// Prunes all managed backup directories under the backup root.
    /// - Parameters:
    ///   - keep: Maximum number of newest backups to retain per source file.
    ///   - maxAgeDays: Maximum backup age in days.
    /// - Returns: Total number of removed backup files.
    /// - Throws: File-system errors when traversal or deletion fails.
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

    /// Restores a managed backup to a source file.
    ///
    /// If the source file exists, this method creates a fresh managed backup before restoring.
    /// - Parameters:
    ///   - sourceURL: URL of the source `.bike` file to restore.
    ///   - backupID: Backup identifier returned by ``listBackups(for:)``.
    ///   - writeMode: Write strategy used for restore.
    /// - Throws: ``BikeToolCoreError`` if `backupID` is not found, plus file coordination/write errors.
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

    /// Returns the root directory where managed backups are stored.
    ///
    /// Resolution order:
    /// 1. `BIKETOOL_BACKUP_DIR` when set
    /// 2. `$CODEX_HOME/state/bike-tool/backups`
    /// 3. `~/.codex/state/bike-tool/backups`
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

    /// Returns the managed backup directory for a source file.
    ///
    /// The source path is normalized and encoded to provide a stable directory name.
    /// - Parameter sourceURL: URL of the source `.bike` file.
    /// - Returns: Per-source directory under ``backupRootDirectory()``.
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
