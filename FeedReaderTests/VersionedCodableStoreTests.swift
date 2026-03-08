//
//  VersionedCodableStoreTests.swift
//  FeedReaderTests
//
//  Tests for VersionedCodableStore — schema versioning, migrations,
//  backup/restore, and backward compatibility with legacy data.
//

import XCTest
@testable import FeedReader

final class VersionedCodableStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "VersionedCodableStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
        // Clear all keys before each test
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Test Models

    struct SampleV1: Codable, Equatable {
        let name: String
        let count: Int
    }

    struct SampleV2: Codable, Equatable {
        let name: String
        let count: Int
        let active: Bool
    }

    // MARK: - Save & Load

    func testSaveAndLoad_roundTrips() {
        let store = VersionedCodableStore<SampleV1>(
            key: "test_basic", defaults: defaults)

        let value = SampleV1(name: "hello", count: 42)
        XCTAssertTrue(store.save(value))

        let loaded = store.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded, value)
    }

    func testLoad_noData_returnsNil() {
        let store = VersionedCodableStore<SampleV1>(
            key: "nonexistent", defaults: defaults)
        XCTAssertNil(store.load())
        XCTAssertNil(store.lastError)
    }

    func testSave_overwritesPrevious() {
        let store = VersionedCodableStore<SampleV1>(
            key: "test_overwrite", defaults: defaults)

        store.save(SampleV1(name: "first", count: 1))
        store.save(SampleV1(name: "second", count: 2))

        let loaded = store.load()
        XCTAssertEqual(loaded?.name, "second")
        XCTAssertEqual(loaded?.count, 2)
    }

    func testSave_createsBackup() {
        let store = VersionedCodableStore<SampleV1>(
            key: "test_backup", defaults: defaults)

        store.save(SampleV1(name: "original", count: 1))
        XCTAssertFalse(store.hasBackup) // No backup on first save

        store.save(SampleV1(name: "updated", count: 2))
        XCTAssertTrue(store.hasBackup) // Backup created on second save
    }

    // MARK: - Schema Versioning

    func testVersionedEnvelope_storedVersion() {
        let store = VersionedCodableStore<SampleV1>(
            key: "test_version", schemaVersion: 3, defaults: defaults)

        store.save(SampleV1(name: "test", count: 1))
        XCTAssertEqual(store.storedVersion, 3)
    }

    func testLoad_wrongVersion_withoutMigration_returnsNil() {
        // Save at version 1
        let storeV1 = VersionedCodableStore<SampleV1>(
            key: "test_ver_mismatch", schemaVersion: 1, defaults: defaults)
        storeV1.save(SampleV1(name: "old", count: 1))

        // Try to load at version 2 without migration
        let storeV2 = VersionedCodableStore<SampleV1>(
            key: "test_ver_mismatch", schemaVersion: 2, defaults: defaults)
        // Should still fall back to legacy or fail
        // Since the data is in an envelope with version 1, and no migration for 1→2,
        // it won't decode at version 2, but will try legacy decode (which fails
        // because the data is enveloped), then backup
        let loaded = storeV2.load()
        XCTAssertNil(loaded)
        XCTAssertNotNil(storeV2.lastError)
    }

    // MARK: - Legacy Compatibility

    func testLoad_legacyUnversionedData() {
        // Simulate pre-versioned data: write raw Codable directly
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let legacy = SampleV1(name: "legacy", count: 99)
        let data = try! encoder.encode(legacy)
        defaults.set(data, forKey: "test_legacy")

        let store = VersionedCodableStore<SampleV1>(
            key: "test_legacy", schemaVersion: 1, defaults: defaults)
        let loaded = store.load()

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.name, "legacy")
        XCTAssertEqual(loaded?.count, 99)

        // After loading legacy data, it should be re-saved with version envelope
        XCTAssertEqual(store.storedVersion, 1)
    }

    // MARK: - Migration

    func testMigration_v1ToV2() {
        // Save at version 1
        let storeV1 = VersionedCodableStore<SampleV1>(
            key: "test_migration", schemaVersion: 1, defaults: defaults)
        storeV1.save(SampleV1(name: "migrating", count: 5))

        // Define migration: add "active" field defaulting to true
        let migration: VersionedCodableStore<SampleV2>.Migration = { oldData in
            guard var json = try? JSONSerialization.jsonObject(with: oldData) as? [String: Any] else {
                return nil
            }
            json["active"] = true
            return try? JSONSerialization.data(withJSONObject: json)
        }

        let storeV2 = VersionedCodableStore<SampleV2>(
            key: "test_migration", schemaVersion: 2,
            defaults: defaults, migrations: [1: migration])

        let loaded = storeV2.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.name, "migrating")
        XCTAssertEqual(loaded?.count, 5)
        XCTAssertEqual(loaded?.active, true)

        // After migration, stored version should be updated
        XCTAssertEqual(storeV2.storedVersion, 2)
    }

    func testMigration_failedMigration_returnsNil() {
        let storeV1 = VersionedCodableStore<SampleV1>(
            key: "test_fail_migration", schemaVersion: 1, defaults: defaults)
        storeV1.save(SampleV1(name: "fail", count: 1))

        // Migration that always fails
        let failMigration: VersionedCodableStore<SampleV1>.Migration = { _ in nil }

        let storeV2 = VersionedCodableStore<SampleV1>(
            key: "test_fail_migration", schemaVersion: 2,
            defaults: defaults, migrations: [1: failMigration])

        let loaded = storeV2.load()
        XCTAssertNil(loaded)
    }

    // MARK: - Backup Restore

    func testLoad_corruptedPrimary_restoresFromBackup() {
        let store = VersionedCodableStore<SampleV1>(
            key: "test_corrupt", schemaVersion: 1, defaults: defaults)

        // Save good data twice (first save stores data, second creates backup)
        store.save(SampleV1(name: "good", count: 1))
        store.save(SampleV1(name: "good2", count: 2))

        // Corrupt the primary data
        defaults.set(Data("garbage".utf8), forKey: "test_corrupt")

        // Load should restore from backup (which has "good" data)
        let loaded = store.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.name, "good")
        XCTAssertTrue(store.lastError?.contains("backup") ?? false)
    }

    // MARK: - Removal

    func testRemoveAll_clearsDataAndBackup() {
        let store = VersionedCodableStore<SampleV1>(
            key: "test_remove", defaults: defaults)

        store.save(SampleV1(name: "a", count: 1))
        store.save(SampleV1(name: "b", count: 2))

        XCTAssertTrue(store.exists)
        XCTAssertTrue(store.hasBackup)

        store.removeAll()

        XCTAssertFalse(store.exists)
        XCTAssertFalse(store.hasBackup)
    }

    func testRemoveBackup_keepsData() {
        let store = VersionedCodableStore<SampleV1>(
            key: "test_remove_backup", defaults: defaults)

        store.save(SampleV1(name: "keep", count: 1))
        store.save(SampleV1(name: "keep2", count: 2))

        store.removeBackup()
        XCTAssertTrue(store.exists)
        XCTAssertFalse(store.hasBackup)
    }

    // MARK: - Array Storage

    func testSave_array() {
        let store = VersionedCodableStore<[SampleV1]>(
            key: "test_array", defaults: defaults)

        let items = [
            SampleV1(name: "a", count: 1),
            SampleV1(name: "b", count: 2),
            SampleV1(name: "c", count: 3)
        ]
        store.save(items)

        let loaded = store.load()
        XCTAssertEqual(loaded?.count, 3)
        XCTAssertEqual(loaded?[1].name, "b")
    }

    // MARK: - Date Strategy

    func testDateStrategy_iso8601() {
        struct Dated: Codable, Equatable {
            let when: Date
        }

        let store = VersionedCodableStore<Dated>(
            key: "test_date_iso", dateStrategy: .iso8601, defaults: defaults)

        let now = Date()
        store.save(Dated(when: now))

        let loaded = store.load()
        XCTAssertNotNil(loaded)
        // ISO 8601 rounds to seconds
        XCTAssertEqual(loaded!.when.timeIntervalSinceReferenceDate,
                       now.timeIntervalSinceReferenceDate, accuracy: 1.0)
    }

    func testDateStrategy_deferred() {
        struct Dated: Codable, Equatable {
            let when: Date
        }

        let store = VersionedCodableStore<Dated>(
            key: "test_date_deferred", dateStrategy: .deferredToDate, defaults: defaults)

        let now = Date()
        store.save(Dated(when: now))

        let loaded = store.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded!.when.timeIntervalSinceReferenceDate,
                       now.timeIntervalSinceReferenceDate, accuracy: 0.001)
    }

    // MARK: - Exists

    func testExists_falseWhenEmpty() {
        let store = VersionedCodableStore<SampleV1>(
            key: "test_exists_empty", defaults: defaults)
        XCTAssertFalse(store.exists)
    }

    func testExists_trueAfterSave() {
        let store = VersionedCodableStore<SampleV1>(
            key: "test_exists_save", defaults: defaults)
        store.save(SampleV1(name: "hi", count: 1))
        XCTAssertTrue(store.exists)
    }
}
