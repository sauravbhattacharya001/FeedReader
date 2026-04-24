//
//  VersionedCodableStore.swift
//  FeedReader
//
//  Addresses issue #27: Silent data loss on schema changes.
//
//  Wraps UserDefaultsCodableStore with:
//  1. Schema versioning envelope (schemaVersion + data)
//  2. Backup-before-overwrite (preserves last-known-good state)
//  3. Migration registry for schema evolution
//  4. Error logging instead of silent nil returns
//  5. Graceful fallback: tries versioned decode → legacy decode → migrations
//

import Foundation
import os.log

/// Envelope that wraps persisted data with a schema version.
struct VersionedEnvelope<T: Codable>: Codable {
    let schemaVersion: Int
    let data: T
}

/// A persistence store with schema versioning, migration support, and
/// backup-before-overwrite to prevent silent data loss.
///
/// Usage:
/// ```swift
/// let store = VersionedCodableStore<[ReadingChallenge]>(
///     key: "reading_challenges",
///     schemaVersion: 2,
///     migrations: [
///         1: { oldData in
///             // Transform v1 JSON to v2 structure
///             // Return modified Data, or nil to skip
///             return modifiedData
///         }
///     ]
/// )
/// ```
final class VersionedCodableStore<T: Codable> {

    /// A migration closure that receives raw JSON Data at the old version
    /// and returns transformed Data compatible with the next version,
    /// or nil if migration is not possible.
    typealias Migration = (Data) -> Data?

    /// The UserDefaults key for the versioned data.
    let key: String

    /// Current schema version. Incremented when the Codable model changes.
    let schemaVersion: Int

    /// The backup key suffix.
    private let backupSuffix = ".backup"

    /// Date strategy for encoding/decoding.
    let dateStrategy: UserDefaultsCodableStore<T>.DateStrategy

    /// The underlying UserDefaults instance.
    let defaults: UserDefaults

    /// Registered migrations keyed by source version.
    /// Migration at key N transforms data from version N to version N+1.
    private let migrations: [Int: Migration]

    /// Tracks the last load error for diagnostics.
    private(set) var lastError: String?

    init(key: String,
         schemaVersion: Int = 1,
         dateStrategy: UserDefaultsCodableStore<T>.DateStrategy = .iso8601,
         defaults: UserDefaults = .standard,
         migrations: [Int: Migration] = [:]) {
        self.key = key
        self.schemaVersion = schemaVersion
        self.dateStrategy = dateStrategy
        self.defaults = defaults
        self.migrations = migrations
    }

    // MARK: - Save

    /// Save value wrapped in a versioned envelope.
    /// Creates a backup of the previous data before overwriting.
    @discardableResult
    func save(_ value: T) -> Bool {
        // Backup existing data before overwrite
        if let existingData = defaults.data(forKey: key) {
            defaults.set(existingData, forKey: key + backupSuffix)
        }

        let envelope = VersionedEnvelope(schemaVersion: schemaVersion, data: value)
        let encoder = JSONEncoder()
        applyDateEncoding(encoder)

        guard let data = try? encoder.encode(envelope) else {
            lastError = "Failed to encode value for key '\(key)'"
            logError(lastError!)
            return false
        }

        defaults.set(data, forKey: key)
        lastError = nil
        return true
    }

    // MARK: - Load

    /// Load and decode the stored value with full fallback chain:
    /// 1. Try versioned envelope decode at current version
    /// 2. Try versioned envelope decode at older version + run migrations
    /// 3. Try legacy (unversioned) decode for backward compatibility
    /// 4. Try restoring from backup
    func load() -> T? {
        guard let data = defaults.data(forKey: key) else {
            lastError = nil
            return nil
        }

        // 1. Try current-version envelope decode
        if let result = decodeEnvelope(from: data, expectedVersion: schemaVersion) {
            lastError = nil
            return result
        }

        // 2. Try older envelope with migrations
        if let migrated = attemptMigration(from: data) {
            lastError = nil
            // Re-save with current version to avoid future migration overhead
            save(migrated)
            return migrated
        }

        // 3. Try legacy (unversioned) decode
        if let legacy = decodeLegacy(from: data) {
            lastError = "Loaded legacy (unversioned) data for key '\(key)'. Re-saving with version \(schemaVersion)."
            logWarning(lastError!)
            // Upgrade to versioned format
            save(legacy)
            return legacy
        }

        // 4. Try backup
        if let backupData = defaults.data(forKey: key + backupSuffix) {
            if let fromBackup = decodeEnvelope(from: backupData, expectedVersion: schemaVersion) {
                lastError = "Primary data corrupted for key '\(key)'. Restored from backup."
                logWarning(lastError!)
                save(fromBackup)
                return fromBackup
            }
            if let legacyBackup = decodeLegacy(from: backupData) {
                lastError = "Primary data corrupted for key '\(key)'. Restored legacy data from backup."
                logWarning(lastError!)
                save(legacyBackup)
                return legacyBackup
            }
        }

        lastError = "Failed to decode data for key '\(key)'. All fallbacks exhausted. Data size: \(data.count) bytes."
        logError(lastError!)
        return nil
    }

    // MARK: - Backup Management

    /// Check if a backup exists for this key.
    var hasBackup: Bool {
        return defaults.data(forKey: key + backupSuffix) != nil
    }

    /// Remove the backup for this key.
    func removeBackup() {
        defaults.removeObject(forKey: key + backupSuffix)
    }

    /// Remove both primary data and backup.
    func removeAll() {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: key + backupSuffix)
    }

    /// Check whether any data exists for this key.
    var exists: Bool {
        return defaults.data(forKey: key) != nil
    }

    /// Returns the stored schema version, or nil if no versioned data exists.
    var storedVersion: Int? {
        guard let data = defaults.data(forKey: key) else { return nil }
        // Decode just the version field without requiring T
        struct VersionOnly: Codable { let schemaVersion: Int }
        return try? JSONDecoder().decode(VersionOnly.self, from: data).schemaVersion
    }

    // MARK: - Private Decode Helpers

    private func decodeEnvelope(from data: Data, expectedVersion: Int) -> T? {
        let decoder = JSONDecoder()
        applyDateDecoding(decoder)
        guard let envelope = try? decoder.decode(VersionedEnvelope<T>.self, from: data),
              envelope.schemaVersion == expectedVersion else {
            return nil
        }
        return envelope.data
    }

    private func decodeLegacy(from data: Data) -> T? {
        let decoder = JSONDecoder()
        applyDateDecoding(decoder)
        return try? decoder.decode(T.self, from: data)
    }

    /// Attempt to decode an older-version envelope, then apply sequential
    /// migrations from that version up to the current schema version.
    private func attemptMigration(from data: Data) -> T? {
        // Extract the stored version
        struct VersionOnly: Codable { let schemaVersion: Int }
        guard let versionInfo = try? JSONDecoder().decode(VersionOnly.self, from: data) else {
            return nil
        }

        let storedVersion = versionInfo.schemaVersion
        guard storedVersion < schemaVersion else { return nil }

        // Extract the raw "data" field from the envelope
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let innerData = json["data"],
              let innerBytes = try? JSONSerialization.data(withJSONObject: innerData) else {
            return nil
        }

        // Apply migrations sequentially: v(stored) → v(stored+1) → ... → v(current)
        var currentData = innerBytes
        for version in storedVersion..<schemaVersion {
            guard let migration = migrations[version] else {
                logWarning("No migration registered for version \(version) → \(version + 1) on key '\(key)'")
                return nil
            }
            guard let migrated = migration(currentData) else {
                logError("Migration \(version) → \(version + 1) failed for key '\(key)'")
                return nil
            }
            currentData = migrated
        }

        // Try to decode the migrated data
        let decoder = JSONDecoder()
        applyDateDecoding(decoder)
        return try? decoder.decode(T.self, from: currentData)
    }

    // MARK: - Date Strategy

    private func applyDateEncoding(_ encoder: JSONEncoder) {
        switch dateStrategy {
        case .iso8601:
            encoder.dateEncodingStrategy = .iso8601
        case .deferredToDate:
            break
        }
    }

    private func applyDateDecoding(_ decoder: JSONDecoder) {
        switch dateStrategy {
        case .iso8601:
            decoder.dateDecodingStrategy = .iso8601
        case .deferredToDate:
            break
        }
    }

    // MARK: - Logging

    private func logError(_ message: String) {
        os_log("[VersionedCodableStore] %{private}s", log: FeedReaderLogger.storage, type: .error, message)
    }

    private func logWarning(_ message: String) {
        os_log("[VersionedCodableStore] %{private}s", log: FeedReaderLogger.storage, type: .info, message)
    }
}
