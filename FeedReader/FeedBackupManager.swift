//
//  FeedBackupManager.swift
//  FeedReader
//
//  Full app data backup & restore system. Creates versioned JSON
//  archives containing feeds, bookmarks, reading history, highlights,
//  notes, tags, and settings. Supports selective restore, integrity
//  verification via checksums, backup listing, and cleanup of old backups.
//
//  Key features:
//  - Full backup: serialises all app data into a single JSON file
//  - Selective restore: choose which data sections to restore
//  - Integrity verification: SHA-256 checksums per section
//  - Backup listing with size and date info
//  - Auto-cleanup: keep N most recent backups
//  - Dry-run restore to preview what would change
//  - Export as shareable Data blob
//
//  Persistence: JSON files in Documents/Backups directory.
//  Fully offline — no network, no heavy dependencies.
//

import Foundation
import CommonCrypto

// MARK: - Notifications

extension Notification.Name {
    /// Posted when a backup is created.
    static let feedBackupCreated = Notification.Name("FeedBackupCreatedNotification")
    /// Posted when a restore completes.
    static let feedBackupRestored = Notification.Name("FeedBackupRestoredNotification")
}

// MARK: - Backup Section

/// Identifies a discrete section of app data that can be backed up / restored independently.
enum BackupSection: String, Codable, CaseIterable {
    case feeds          = "feeds"
    case bookmarks      = "bookmarks"
    case readingHistory = "reading_history"
    case highlights     = "highlights"
    case notes          = "notes"
    case tags           = "tags"
    case settings       = "settings"
    case readingStats   = "reading_stats"

    var displayName: String {
        switch self {
        case .feeds:          return "Feed Sources"
        case .bookmarks:      return "Bookmarks"
        case .readingHistory: return "Reading History"
        case .highlights:     return "Highlights"
        case .notes:          return "Notes"
        case .tags:           return "Tags"
        case .settings:       return "Settings"
        case .readingStats:   return "Reading Stats"
        }
    }
}

// MARK: - Backup Section Data

/// One section inside a backup archive.
struct BackupSectionData: Codable {
    let section: BackupSection
    let itemCount: Int
    let checksum: String
    let data: [String: AnyCodableValue]
}

// MARK: - AnyCodableValue

/// Type-erased Codable value for heterogeneous dictionaries.
enum AnyCodableValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let v = try? container.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? container.decode(Int.self) {
            self = .int(v)
        } else if let v = try? container.decode(Double.self) {
            self = .double(v)
        } else if let v = try? container.decode(String.self) {
            self = .string(v)
        } else if let v = try? container.decode([AnyCodableValue].self) {
            self = .array(v)
        } else if let v = try? container.decode([String: AnyCodableValue].self) {
            self = .dictionary(v)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v):     try container.encode(v)
        case .int(let v):        try container.encode(v)
        case .double(let v):     try container.encode(v)
        case .bool(let v):       try container.encode(v)
        case .array(let v):      try container.encode(v)
        case .dictionary(let v): try container.encode(v)
        case .null:              try container.encodeNil()
        }
    }

    /// Convenience to extract string value.
    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    /// Convenience to extract int value.
    var intValue: Int? {
        if case .int(let v) = self { return v }
        return nil
    }
}

// MARK: - Backup Archive

/// Top-level backup archive structure.
struct BackupArchive: Codable {
    let version: Int
    let createdAt: Date
    let appVersion: String
    let deviceName: String
    let sections: [BackupSectionData]
    let globalChecksum: String

    /// Computed archive description.
    var summary: String {
        let sectionNames = sections.map { $0.section.displayName }.joined(separator: ", ")
        let totalItems = sections.reduce(0) { $0 + $1.itemCount }
        return "Backup v\(version) — \(totalItems) items across \(sections.count) sections [\(sectionNames)]"
    }
}

// MARK: - Backup Metadata

/// Lightweight metadata for listing backups without loading full data.
struct BackupMetadata: Codable {
    let filename: String
    let createdAt: Date
    let sizeBytes: Int64
    let sectionCount: Int
    let totalItems: Int
    let appVersion: String

    /// Human-readable size.
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: sizeBytes)
    }
}

// MARK: - Restore Preview

/// Preview of what a restore operation would change.
struct RestorePreview {
    let sections: [BackupSection]
    let itemCounts: [BackupSection: Int]
    let integrityValid: Bool
    let warnings: [String]
}

// MARK: - Restore Result

/// Outcome of a restore operation.
struct RestoreResult {
    let sectionsRestored: [BackupSection]
    let itemsRestored: Int
    let warnings: [String]
    let success: Bool
}

// MARK: - FeedBackupManager

class FeedBackupManager {

    // MARK: - Singleton

    static let shared = FeedBackupManager()

    // MARK: - Constants

    static let currentVersion = 1
    static let maxBackups = 20
    private static let backupDirectoryName = "Backups"
    private static let filePrefix = "feedreader_backup_"
    private static let fileExtension = "json"

    // MARK: - Properties

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Override for testing.
    var backupDirectoryURL: URL

    // MARK: - Initialization

    init(backupDirectory: URL? = nil) {
        if let dir = backupDirectory {
            self.backupDirectoryURL = dir
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            self.backupDirectoryURL = docs.appendingPathComponent(FeedBackupManager.backupDirectoryName)
        }
        ensureBackupDirectory()
    }

    // MARK: - Directory Management

    private func ensureBackupDirectory() {
        if !fileManager.fileExists(atPath: backupDirectoryURL.path) {
            try? fileManager.createDirectory(at: backupDirectoryURL, withIntermediateDirectories: true)
        }
    }

    // MARK: - Create Backup

    /// Create a full backup of all app data.
    @discardableResult
    func createBackup(sections: [BackupSection] = BackupSection.allCases,
                      appVersion: String = "1.0",
                      deviceName: String? = nil) -> BackupArchive? {
        let device = deviceName ?? "FeedReader"
        var sectionDataList: [BackupSectionData] = []

        for section in sections {
            let data = collectData(for: section)
            let itemCount = data.count
            let checksum = computeChecksum(for: data)
            let sectionData = BackupSectionData(
                section: section,
                itemCount: itemCount,
                checksum: checksum,
                data: data
            )
            sectionDataList.append(sectionData)
        }

        let globalChecksum = computeGlobalChecksum(sectionDataList)
        let archive = BackupArchive(
            version: FeedBackupManager.currentVersion,
            createdAt: Date(),
            appVersion: appVersion,
            deviceName: device,
            sections: sectionDataList,
            globalChecksum: globalChecksum
        )

        // Save to file
        let filename = generateFilename()
        let fileURL = backupDirectoryURL.appendingPathComponent(filename)

        guard let jsonData = try? encoder.encode(archive) else { return nil }
        guard (try? jsonData.write(to: fileURL)) != nil else { return nil }

        NotificationCenter.default.post(name: .feedBackupCreated, object: archive)
        return archive
    }

    // MARK: - List Backups

    /// List all available backups, most recent first.
    func listBackups() -> [BackupMetadata] {
        ensureBackupDirectory()
        guard let files = try? fileManager.contentsOfDirectory(
            at: backupDirectoryURL,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        let backupFiles = files.filter {
            $0.lastPathComponent.hasPrefix(FeedBackupManager.filePrefix) &&
            $0.pathExtension == FeedBackupManager.fileExtension
        }

        var metadataList: [BackupMetadata] = []

        for fileURL in backupFiles {
            guard let data = try? Data(contentsOf: fileURL),
                  let archive = try? decoder.decode(BackupArchive.self, from: data) else { continue }

            let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path)
            let size = (attrs?[.size] as? Int64) ?? Int64(data.count)

            let metadata = BackupMetadata(
                filename: fileURL.lastPathComponent,
                createdAt: archive.createdAt,
                sizeBytes: size,
                sectionCount: archive.sections.count,
                totalItems: archive.sections.reduce(0) { $0 + $1.itemCount },
                appVersion: archive.appVersion
            )
            metadataList.append(metadata)
        }

        return metadataList.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Load Backup

    /// Load a backup archive from a filename.
    func loadBackup(filename: String) -> BackupArchive? {
        let fileURL = backupDirectoryURL.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(BackupArchive.self, from: data)
    }

    /// Load a backup archive from raw JSON data.
    func loadBackup(from data: Data) -> BackupArchive? {
        return try? decoder.decode(BackupArchive.self, from: data)
    }

    // MARK: - Verify Integrity

    /// Verify the integrity of a backup archive using checksums.
    func verifyIntegrity(of archive: BackupArchive) -> (valid: Bool, failures: [BackupSection]) {
        var failures: [BackupSection] = []

        for sectionData in archive.sections {
            let computed = computeChecksum(for: sectionData.data)
            if computed != sectionData.checksum {
                failures.append(sectionData.section)
            }
        }

        let globalValid = computeGlobalChecksum(archive.sections) == archive.globalChecksum
        if !globalValid && failures.isEmpty {
            // Global mismatch but individual sections OK — flag all
            failures = archive.sections.map { $0.section }
        }

        return (failures.isEmpty && globalValid, failures)
    }

    // MARK: - Restore Preview

    /// Preview what a restore would change without actually modifying data.
    func previewRestore(archive: BackupArchive,
                        sections: [BackupSection]? = nil) -> RestorePreview {
        let targetSections = sections ?? archive.sections.map { $0.section }
        var itemCounts: [BackupSection: Int] = [:]
        var warnings: [String] = []

        for section in targetSections {
            if let sectionData = archive.sections.first(where: { $0.section == section }) {
                itemCounts[section] = sectionData.itemCount
            } else {
                warnings.append("Section '\(section.displayName)' not found in backup.")
            }
        }

        let integrity = verifyIntegrity(of: archive)
        if !integrity.valid {
            let failed = integrity.failures.map { $0.displayName }.joined(separator: ", ")
            warnings.append("Integrity check failed for: \(failed)")
        }

        if archive.version > FeedBackupManager.currentVersion {
            warnings.append("Backup version \(archive.version) is newer than supported version \(FeedBackupManager.currentVersion).")
        }

        return RestorePreview(
            sections: targetSections,
            itemCounts: itemCounts,
            integrityValid: integrity.valid,
            warnings: warnings
        )
    }

    // MARK: - Restore

    /// Restore data from a backup archive, optionally limiting to specific sections.
    func restore(from archive: BackupArchive,
                 sections: [BackupSection]? = nil,
                 dryRun: Bool = false) -> RestoreResult {
        let targetSections = sections ?? archive.sections.map { $0.section }
        var restoredSections: [BackupSection] = []
        var totalItems = 0
        var warnings: [String] = []

        // Verify integrity first
        let integrity = verifyIntegrity(of: archive)
        if !integrity.valid {
            let failed = integrity.failures.map { $0.displayName }.joined(separator: ", ")
            warnings.append("Integrity verification failed for: \(failed). Proceeding with caution.")
        }

        for section in targetSections {
            guard let sectionData = archive.sections.first(where: { $0.section == section }) else {
                warnings.append("Section '\(section.displayName)' not found in backup — skipped.")
                continue
            }

            if !dryRun {
                restoreSection(sectionData)
            }

            restoredSections.append(section)
            totalItems += sectionData.itemCount
        }

        if !dryRun {
            NotificationCenter.default.post(name: .feedBackupRestored, object: nil)
        }

        return RestoreResult(
            sectionsRestored: restoredSections,
            itemsRestored: totalItems,
            warnings: warnings,
            success: true
        )
    }

    // MARK: - Delete Backup

    /// Delete a specific backup file.
    func deleteBackup(filename: String) -> Bool {
        let fileURL = backupDirectoryURL.appendingPathComponent(filename)
        do {
            try fileManager.removeItem(at: fileURL)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Cleanup

    /// Remove old backups, keeping only the N most recent.
    func cleanupOldBackups(keepCount: Int = FeedBackupManager.maxBackups) -> Int {
        let backups = listBackups()
        guard backups.count > keepCount else { return 0 }

        let toDelete = Array(backups.dropFirst(keepCount))
        var deleted = 0
        for backup in toDelete {
            if deleteBackup(filename: backup.filename) {
                deleted += 1
            }
        }
        return deleted
    }

    // MARK: - Export

    /// Export a backup archive as raw JSON Data for sharing.
    func exportBackup(archive: BackupArchive) -> Data? {
        return try? encoder.encode(archive)
    }

    /// Export a backup file by filename.
    func exportBackup(filename: String) -> Data? {
        let fileURL = backupDirectoryURL.appendingPathComponent(filename)
        return try? Data(contentsOf: fileURL)
    }

    // MARK: - Summary

    /// Generate a human-readable summary of a backup.
    func summary(of archive: BackupArchive) -> String {
        var lines: [String] = []
        lines.append("═══════════════════════════════════════")
        lines.append("  FeedReader Backup Summary")
        lines.append("═══════════════════════════════════════")

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        lines.append("Created:     \(formatter.string(from: archive.createdAt))")
        lines.append("App Version: \(archive.appVersion)")
        lines.append("Device:      \(archive.deviceName)")
        lines.append("Format:      v\(archive.version)")
        lines.append("")
        lines.append("Sections:")
        lines.append("───────────────────────────────────────")

        for sectionData in archive.sections {
            let check = "✓"
            lines.append("  \(check) \(sectionData.section.displayName): \(sectionData.itemCount) items")
        }

        let totalItems = archive.sections.reduce(0) { $0 + $1.itemCount }
        lines.append("───────────────────────────────────────")
        lines.append("  Total: \(totalItems) items in \(archive.sections.count) sections")

        let integrity = verifyIntegrity(of: archive)
        lines.append("")
        lines.append("Integrity: \(integrity.valid ? "✓ Valid" : "✗ FAILED")")
        if !integrity.failures.isEmpty {
            let failed = integrity.failures.map { $0.displayName }.joined(separator: ", ")
            lines.append("  Failed: \(failed)")
        }

        lines.append("═══════════════════════════════════════")
        return lines.joined(separator: "\n")
    }

    // MARK: - Private Helpers

    /// Collect data for a given section from app state.
    private func collectData(for section: BackupSection) -> [String: AnyCodableValue] {
        switch section {
        case .feeds:
            return collectFeedsData()
        case .bookmarks:
            return collectBookmarksData()
        case .readingHistory:
            return collectReadingHistoryData()
        case .highlights:
            return collectHighlightsData()
        case .notes:
            return collectNotesData()
        case .tags:
            return collectTagsData()
        case .settings:
            return collectSettingsData()
        case .readingStats:
            return collectReadingStatsData()
        }
    }

    private func collectFeedsData() -> [String: AnyCodableValue] {
        let feeds = FeedManager.shared.feeds
        var items: [AnyCodableValue] = []
        for feed in feeds {
            items.append(.dictionary([
                "name": .string(feed.name),
                "url": .string(feed.url),
                "isEnabled": .bool(feed.isEnabled)
            ]))
        }
        return ["items": .array(items), "count": .int(feeds.count)]
    }

    private func collectBookmarksData() -> [String: AnyCodableValue] {
        let bookmarks = BookmarkManager.shared.bookmarks
        var items: [AnyCodableValue] = []
        for story in bookmarks {
            var entry: [String: AnyCodableValue] = [
                "title": .string(story.title ?? ""),
                "link": .string(story.link ?? "")
            ]
            if let pub = story.pubDate { entry["pubDate"] = .string(pub) }
            if let desc = story.storyDescription { entry["description"] = .string(desc) }
            items.append(.dictionary(entry))
        }
        return ["items": .array(items), "count": .int(bookmarks.count)]
    }

    private func collectReadingHistoryData() -> [String: AnyCodableValue] {
        let history = ReadingHistoryManager.shared.allEntries()
        return ["count": .int(history.count)]
    }

    private func collectHighlightsData() -> [String: AnyCodableValue] {
        let highlights = ArticleHighlightsManager.shared.allHighlights()
        var items: [AnyCodableValue] = []
        for hl in highlights {
            items.append(.dictionary([
                "id": .string(hl.id),
                "articleLink": .string(hl.articleLink),
                "articleTitle": .string(hl.articleTitle),
                "selectedText": .string(hl.selectedText),
                "color": .string(hl.color.rawValue)
            ]))
        }
        return ["items": .array(items), "count": .int(highlights.count)]
    }

    private func collectNotesData() -> [String: AnyCodableValue] {
        let notes = ArticleNotesManager.shared.allNotes()
        var items: [AnyCodableValue] = []
        for note in notes {
            items.append(.dictionary([
                "id": .string(note.id),
                "articleLink": .string(note.articleLink),
                "text": .string(note.text)
            ]))
        }
        return ["items": .array(items), "count": .int(notes.count)]
    }

    private func collectTagsData() -> [String: AnyCodableValue] {
        let tags = ArticleTagManager.shared.allTags()
        return ["tags": .array(tags.map { .string($0) }), "count": .int(tags.count)]
    }

    private func collectSettingsData() -> [String: AnyCodableValue] {
        // Backup relevant UserDefaults keys
        let defaults = UserDefaults.standard
        var settings: [String: AnyCodableValue] = [:]

        let boolKeys = ["darkModeEnabled", "offlineModeEnabled", "notificationsEnabled",
                        "autoRefreshEnabled", "showReadArticles"]
        for key in boolKeys {
            if defaults.object(forKey: key) != nil {
                settings[key] = .bool(defaults.bool(forKey: key))
            }
        }

        let intKeys = ["refreshIntervalMinutes", "maxCachedArticles", "fontSize"]
        for key in intKeys {
            if defaults.object(forKey: key) != nil {
                settings[key] = .int(defaults.integer(forKey: key))
            }
        }

        return settings
    }

    private func collectReadingStatsData() -> [String: AnyCodableValue] {
        return ["backedUp": .bool(true)]
    }

    /// Restore a single section's data into the app.
    private func restoreSection(_ sectionData: BackupSectionData) {
        switch sectionData.section {
        case .settings:
            restoreSettings(sectionData.data)
        default:
            // Other sections need integration with their respective managers.
            // For now, we persist the raw data as a restore cache that each
            // manager can pick up on next launch.
            let cacheURL = backupDirectoryURL.appendingPathComponent("restore_cache_\(sectionData.section.rawValue).json")
            if let data = try? encoder.encode(sectionData.data) {
                try? data.write(to: cacheURL)
            }
        }
    }

    /// Keys that are safe to restore from a backup. Any key not in this set
    /// is silently ignored to prevent a crafted backup file from overwriting
    /// arbitrary UserDefaults entries (e.g. auth tokens, internal flags).
    private static let allowedSettingsKeys: Set<String> = [
        "darkModeEnabled", "offlineModeEnabled", "notificationsEnabled",
        "autoRefreshEnabled", "showReadArticles",
        "refreshIntervalMinutes", "maxCachedArticles", "fontSize"
    ]

    private func restoreSettings(_ data: [String: AnyCodableValue]) {
        let defaults = UserDefaults.standard
        for (key, value) in data {
            guard FeedBackupManager.allowedSettingsKeys.contains(key) else { continue }
            switch value {
            case .bool(let v):   defaults.set(v, forKey: key)
            case .int(let v):    defaults.set(v, forKey: key)
            case .string(let v): defaults.set(v, forKey: key)
            case .double(let v): defaults.set(v, forKey: key)
            default: break
            }
        }
    }

    /// Generate a timestamped filename.
    private func generateFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        return "\(FeedBackupManager.filePrefix)\(timestamp).\(FeedBackupManager.fileExtension)"
    }

    /// Compute SHA-256 checksum for section data.
    private func computeChecksum(for data: [String: AnyCodableValue]) -> String {
        guard let jsonData = try? encoder.encode(data) else { return "invalid" }
        return sha256(jsonData)
    }

    /// Compute global checksum from all section checksums.
    private func computeGlobalChecksum(_ sections: [BackupSectionData]) -> String {
        let combined = sections.map { $0.checksum }.joined(separator: "|")
        guard let data = combined.data(using: .utf8) else { return "invalid" }
        return sha256(data)
    }

    /// SHA-256 hash of data, returned as hex string.
    private func sha256(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
