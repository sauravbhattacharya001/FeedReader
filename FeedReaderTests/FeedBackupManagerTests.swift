//
//  FeedBackupManagerTests.swift
//  FeedReaderTests
//
//  Tests for FeedBackupManager — backup creation, listing, integrity
//  verification, restore preview, selective restore, cleanup, and export.
//

import XCTest
@testable import FeedReader

class FeedBackupManagerTests: XCTestCase {

    var manager: FeedBackupManager!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FeedBackupTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        manager = FeedBackupManager(backupDirectory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Backup Section

    func testBackupSectionDisplayNames() {
        XCTAssertEqual(BackupSection.feeds.displayName, "Feed Sources")
        XCTAssertEqual(BackupSection.bookmarks.displayName, "Bookmarks")
        XCTAssertEqual(BackupSection.readingHistory.displayName, "Reading History")
        XCTAssertEqual(BackupSection.highlights.displayName, "Highlights")
        XCTAssertEqual(BackupSection.notes.displayName, "Notes")
        XCTAssertEqual(BackupSection.tags.displayName, "Tags")
        XCTAssertEqual(BackupSection.settings.displayName, "Settings")
        XCTAssertEqual(BackupSection.readingStats.displayName, "Reading Stats")
    }

    func testAllSectionsCount() {
        XCTAssertEqual(BackupSection.allCases.count, 8)
    }

    // MARK: - AnyCodableValue

    func testAnyCodableStringRoundTrip() {
        let value = AnyCodableValue.string("hello")
        XCTAssertEqual(value.stringValue, "hello")
        XCTAssertNil(value.intValue)
    }

    func testAnyCodableIntRoundTrip() {
        let value = AnyCodableValue.int(42)
        XCTAssertEqual(value.intValue, 42)
        XCTAssertNil(value.stringValue)
    }

    func testAnyCodableBool() {
        let value = AnyCodableValue.bool(true)
        XCTAssertNotEqual(value, .bool(false))
        XCTAssertEqual(value, .bool(true))
    }

    func testAnyCodableNull() {
        let value = AnyCodableValue.null
        XCTAssertNil(value.stringValue)
        XCTAssertNil(value.intValue)
    }

    func testAnyCodableArray() {
        let value = AnyCodableValue.array([.string("a"), .int(1)])
        XCTAssertEqual(value, .array([.string("a"), .int(1)]))
    }

    func testAnyCodableDictionary() {
        let value = AnyCodableValue.dictionary(["key": .string("val")])
        XCTAssertEqual(value, .dictionary(["key": .string("val")]))
    }

    func testAnyCodableEncodeDecode() throws {
        let original: [String: AnyCodableValue] = [
            "name": .string("test"),
            "count": .int(5),
            "active": .bool(true),
            "ratio": .double(3.14),
            "tags": .array([.string("a"), .string("b")]),
            "meta": .dictionary(["x": .int(1)]),
            "empty": .null
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode([String: AnyCodableValue].self, from: data)
        XCTAssertEqual(decoded["name"], .string("test"))
        XCTAssertEqual(decoded["count"], .int(5))
        XCTAssertEqual(decoded["active"], .bool(true))
        XCTAssertEqual(decoded["tags"], .array([.string("a"), .string("b")]))
        XCTAssertEqual(decoded["empty"], .null)
    }

    // MARK: - Create Backup

    func testCreateBackupReturnsArchive() {
        let archive = manager.createBackup(appVersion: "2.0", deviceName: "TestDevice")
        XCTAssertNotNil(archive)
        XCTAssertEqual(archive?.appVersion, "2.0")
        XCTAssertEqual(archive?.deviceName, "TestDevice")
        XCTAssertEqual(archive?.version, FeedBackupManager.currentVersion)
        XCTAssertEqual(archive?.sections.count, BackupSection.allCases.count)
    }

    func testCreateBackupSelectiveSections() {
        let archive = manager.createBackup(sections: [.feeds, .settings])
        XCTAssertNotNil(archive)
        XCTAssertEqual(archive?.sections.count, 2)
        let sectionTypes = archive?.sections.map { $0.section } ?? []
        XCTAssertTrue(sectionTypes.contains(.feeds))
        XCTAssertTrue(sectionTypes.contains(.settings))
        XCTAssertFalse(sectionTypes.contains(.bookmarks))
    }

    func testCreateBackupWritesFile() {
        manager.createBackup()
        let files = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        let backupFiles = files?.filter { $0.lastPathComponent.hasPrefix("feedreader_backup_") } ?? []
        XCTAssertEqual(backupFiles.count, 1)
    }

    func testCreateMultipleBackups() {
        manager.createBackup()
        // small delay to ensure different timestamps
        manager.createBackup()
        let backups = manager.listBackups()
        XCTAssertGreaterThanOrEqual(backups.count, 2)
    }

    // MARK: - List Backups

    func testListBackupsEmpty() {
        let backups = manager.listBackups()
        XCTAssertTrue(backups.isEmpty)
    }

    func testListBackupsReturnsMetadata() {
        manager.createBackup(appVersion: "3.0")
        let backups = manager.listBackups()
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(backups.first?.appVersion, "3.0")
        XCTAssertEqual(backups.first?.sectionCount, BackupSection.allCases.count)
        XCTAssertGreaterThan(backups.first?.sizeBytes ?? 0, 0)
    }

    func testListBackupsSortedMostRecentFirst() {
        manager.createBackup(appVersion: "1.0")
        manager.createBackup(appVersion: "2.0")
        let backups = manager.listBackups()
        XCTAssertEqual(backups.count, 2)
        // Most recent first
        XCTAssertTrue(backups[0].createdAt >= backups[1].createdAt)
    }

    // MARK: - Load Backup

    func testLoadBackupByFilename() {
        manager.createBackup(appVersion: "4.0")
        let backups = manager.listBackups()
        guard let filename = backups.first?.filename else {
            XCTFail("No backup found")
            return
        }
        let archive = manager.loadBackup(filename: filename)
        XCTAssertNotNil(archive)
        XCTAssertEqual(archive?.appVersion, "4.0")
    }

    func testLoadBackupFromData() {
        guard let archive = manager.createBackup() else {
            XCTFail("Failed to create backup")
            return
        }
        guard let data = manager.exportBackup(archive: archive) else {
            XCTFail("Failed to export")
            return
        }
        let loaded = manager.loadBackup(from: data)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.sections.count, archive.sections.count)
    }

    func testLoadNonexistentBackup() {
        let archive = manager.loadBackup(filename: "nonexistent.json")
        XCTAssertNil(archive)
    }

    // MARK: - Integrity Verification

    func testIntegrityValidForFreshBackup() {
        guard let archive = manager.createBackup() else {
            XCTFail("Failed to create backup")
            return
        }
        let result = manager.verifyIntegrity(of: archive)
        XCTAssertTrue(result.valid)
        XCTAssertTrue(result.failures.isEmpty)
    }

    func testIntegrityFailsForTamperedChecksum() {
        guard let archive = manager.createBackup() else {
            XCTFail("Failed to create backup")
            return
        }
        // Tamper with the archive
        let tampered = BackupArchive(
            version: archive.version,
            createdAt: archive.createdAt,
            appVersion: archive.appVersion,
            deviceName: archive.deviceName,
            sections: archive.sections,
            globalChecksum: "tampered_checksum"
        )
        let result = manager.verifyIntegrity(of: tampered)
        XCTAssertFalse(result.valid)
    }

    // MARK: - Restore Preview

    func testPreviewRestoreShowsAllSections() {
        guard let archive = manager.createBackup() else {
            XCTFail("Failed to create backup")
            return
        }
        let preview = manager.previewRestore(archive: archive)
        XCTAssertEqual(preview.sections.count, BackupSection.allCases.count)
        XCTAssertTrue(preview.integrityValid)
        XCTAssertTrue(preview.warnings.isEmpty)
    }

    func testPreviewRestoreSelectiveSections() {
        guard let archive = manager.createBackup() else {
            XCTFail("Failed to create backup")
            return
        }
        let preview = manager.previewRestore(archive: archive, sections: [.feeds, .tags])
        XCTAssertEqual(preview.sections.count, 2)
    }

    func testPreviewRestoreMissingSection() {
        let archive = manager.createBackup(sections: [.feeds])!
        let preview = manager.previewRestore(archive: archive, sections: [.feeds, .bookmarks])
        XCTAssertFalse(preview.warnings.isEmpty)
        XCTAssertTrue(preview.warnings.contains { $0.contains("Bookmarks") })
    }

    // MARK: - Restore

    func testRestoreDryRun() {
        guard let archive = manager.createBackup() else {
            XCTFail("Failed to create backup")
            return
        }
        let result = manager.restore(from: archive, dryRun: true)
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.sectionsRestored.count, BackupSection.allCases.count)
    }

    func testRestoreSelectiveSections() {
        guard let archive = manager.createBackup() else {
            XCTFail("Failed to create backup")
            return
        }
        let result = manager.restore(from: archive, sections: [.settings], dryRun: false)
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.sectionsRestored.count, 1)
        XCTAssertEqual(result.sectionsRestored.first, .settings)
    }

    func testRestoreMissingSectionWarning() {
        let archive = manager.createBackup(sections: [.feeds])!
        let result = manager.restore(from: archive, sections: [.bookmarks])
        XCTAssertTrue(result.success)
        XCTAssertFalse(result.warnings.isEmpty)
    }

    // MARK: - Delete Backup

    func testDeleteBackup() {
        manager.createBackup()
        let backups = manager.listBackups()
        XCTAssertEqual(backups.count, 1)

        let deleted = manager.deleteBackup(filename: backups.first!.filename)
        XCTAssertTrue(deleted)
        XCTAssertEqual(manager.listBackups().count, 0)
    }

    func testDeleteNonexistentBackup() {
        let deleted = manager.deleteBackup(filename: "nonexistent.json")
        XCTAssertFalse(deleted)
    }

    // MARK: - Cleanup

    func testCleanupKeepsRecentBackups() {
        for _ in 0..<5 {
            manager.createBackup()
        }
        XCTAssertEqual(manager.listBackups().count, 5)

        let removed = manager.cleanupOldBackups(keepCount: 3)
        XCTAssertEqual(removed, 2)
        XCTAssertEqual(manager.listBackups().count, 3)
    }

    func testCleanupNoOpWhenUnderLimit() {
        manager.createBackup()
        manager.createBackup()
        let removed = manager.cleanupOldBackups(keepCount: 5)
        XCTAssertEqual(removed, 0)
    }

    // MARK: - Export

    func testExportBackupAsData() {
        guard let archive = manager.createBackup() else {
            XCTFail("Failed to create backup")
            return
        }
        let data = manager.exportBackup(archive: archive)
        XCTAssertNotNil(data)
        XCTAssertGreaterThan(data?.count ?? 0, 0)
    }

    func testExportBackupByFilename() {
        manager.createBackup()
        let backups = manager.listBackups()
        let data = manager.exportBackup(filename: backups.first!.filename)
        XCTAssertNotNil(data)
    }

    // MARK: - Summary

    func testSummaryContainsSections() {
        guard let archive = manager.createBackup() else {
            XCTFail("Failed to create backup")
            return
        }
        let text = manager.summary(of: archive)
        XCTAssertTrue(text.contains("FeedReader Backup Summary"))
        XCTAssertTrue(text.contains("Feed Sources"))
        XCTAssertTrue(text.contains("Bookmarks"))
        XCTAssertTrue(text.contains("Integrity"))
    }

    func testArchiveSummaryProperty() {
        guard let archive = manager.createBackup(sections: [.feeds, .settings]) else {
            XCTFail("Failed to create backup")
            return
        }
        let summary = archive.summary
        XCTAssertTrue(summary.contains("Feed Sources"))
        XCTAssertTrue(summary.contains("Settings"))
    }

    // MARK: - Metadata

    func testMetadataFormattedSize() {
        manager.createBackup()
        let backups = manager.listBackups()
        XCTAssertNotNil(backups.first)
        XCTAssertFalse(backups.first!.formattedSize.isEmpty)
    }

    // MARK: - Notifications

    func testBackupCreatedNotification() {
        let expectation = self.expectation(forNotification: .feedBackupCreated, object: nil)
        manager.createBackup()
        wait(for: [expectation], timeout: 1.0)
    }

    func testRestoreNotification() {
        guard let archive = manager.createBackup() else {
            XCTFail("Failed to create backup")
            return
        }
        let expectation = self.expectation(forNotification: .feedBackupRestored, object: nil)
        manager.restore(from: archive)
        wait(for: [expectation], timeout: 1.0)
    }

    func testDryRunDoesNotPostRestoreNotification() {
        guard let archive = manager.createBackup() else {
            XCTFail("Failed to create backup")
            return
        }
        let expectation = self.expectation(forNotification: .feedBackupRestored, object: nil)
        expectation.isInverted = true
        manager.restore(from: archive, dryRun: true)
        wait(for: [expectation], timeout: 0.5)
    }
}
