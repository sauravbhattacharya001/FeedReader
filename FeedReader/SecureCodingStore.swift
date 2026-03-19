//
//  SecureCodingStore.swift
//  FeedReader
//
//  Generic persistence layer for NSSecureCoding-compliant collections.
//  Eliminates duplicated NSKeyedArchiver/NSKeyedUnarchiver boilerplate
//  across BookmarkManager, FeedManager, OfflineCacheManager, and others.
//
//  Usage:
//      let store = SecureCodingStore<Story>(filename: "bookmarks")
//      store.save(stories)
//      let loaded = store.load()
//

import Foundation

/// A reusable, type-safe persistence wrapper around NSKeyedArchiver/NSKeyedUnarchiver
/// for arrays of NSSecureCoding objects stored in the Documents directory.
///
/// Thread-safety: callers are responsible for synchronization. Individual
/// save/load calls are atomic (writes use `.atomic` option).
final class SecureCodingStore<T: NSObject & NSSecureCoding> {

    // MARK: - Properties

    private let archiveURL: URL
    private let allowedClasses: [AnyClass]

    /// Human-readable label for error messages.
    private let label: String

    // MARK: - Initialization

    /// Create a store that persists to `<Documents>/<filename>`.
    ///
    /// - Parameters:
    ///   - filename: Name of the archive file in the Documents directory.
    ///   - additionalClasses: Extra classes the unarchiver should allow
    ///     beyond `NSArray` and `T` (e.g., nested `NSDate`, `NSString`).
    init(filename: String, additionalClasses: [AnyClass] = []) {
        let documentsDirectory = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        self.archiveURL = documentsDirectory.appendingPathComponent(filename)
        self.label = filename
        self.allowedClasses = [NSArray.self, T.self] + additionalClasses
    }

    // MARK: - Public API

    /// Save an array of objects to disk. Uses atomic writes to prevent
    /// partial-write corruption.
    func save(_ items: [T]) {
        do {
            let data = try NSKeyedArchiver.archivedData(
                withRootObject: items,
                requiringSecureCoding: true
            )
            try data.write(to: archiveURL, options: .atomic)
        } catch {
            print("[\(label)] Failed to save: \(error)")
        }
    }

    /// Load the persisted array from disk. Returns an empty array if the
    /// file doesn't exist or can't be decoded.
    func load() -> [T] {
        guard let data = try? Data(contentsOf: archiveURL) else {
            return []
        }
        if let loaded = (try? NSKeyedUnarchiver.unarchivedObject(
            ofClasses: allowedClasses,
            from: data
        )) as? [T] {
            return loaded
        }
        return []
    }

    /// Delete the archive file from disk.
    func delete() {
        try? FileManager.default.removeItem(at: archiveURL)
    }

    /// Check whether the archive file exists on disk.
    var exists: Bool {
        return FileManager.default.fileExists(atPath: archiveURL.path)
    }
}
