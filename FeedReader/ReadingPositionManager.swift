//
//  ReadingPositionManager.swift
//  FeedReader
//
//  Tracks reading position (scroll percentage) for articles so users can
//  resume where they left off. Persists positions to disk and auto-expires
//  old entries to prevent unbounded growth.
//

import Foundation

/// Manages per-article reading positions for resume-where-you-left-off.
///
/// Usage:
///   - Call `savePosition(for:percentage:)` when the user scrolls an article.
///   - Call `position(for:)` to restore scroll offset when re-opening an article.
///   - Positions older than `expirationInterval` are pruned automatically on load.
///
/// Positions are keyed by article URL and stored as a percentage (0.0–1.0)
/// so they remain valid even if layout changes between sessions.
class ReadingPositionManager {
    
    // MARK: - Singleton
    
    static let shared = ReadingPositionManager()
    
    // MARK: - Types
    
    struct ReadingPosition: Codable {
        /// Scroll percentage (0.0 = top, 1.0 = bottom).
        let percentage: Double
        /// When this position was last updated.
        let updatedAt: Date
        /// Article title for display purposes.
        let title: String?
    }
    
    // MARK: - Properties
    
    /// How long to keep positions before auto-pruning (default: 30 days).
    var expirationInterval: TimeInterval = 30 * 24 * 60 * 60
    
    /// Minimum scroll percentage to bother saving (skip near-top positions).
    var minimumPercentageToSave: Double = 0.03
    
    /// In-memory cache of positions keyed by article URL.
    private var positions: [String: ReadingPosition] = [:]
    
    /// File URL for persistent storage.
    private let storageURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("reading_positions.json")
    }()
    
    // MARK: - Init
    
    private init() {
        load()
    }
    
    // MARK: - Public API
    
    /// Save reading position for an article.
    ///
    /// - Parameters:
    ///   - articleURL: The article's canonical URL string.
    ///   - percentage: Scroll percentage (0.0–1.0). Clamped to valid range.
    ///   - title: Optional article title for display in "continue reading" lists.
    func savePosition(for articleURL: String, percentage: Double, title: String? = nil) {
        let clamped = min(max(percentage, 0.0), 1.0)
        
        // Don't save if the user barely scrolled
        guard clamped >= minimumPercentageToSave else {
            // If they scrolled back to top, remove the saved position
            positions.removeValue(forKey: articleURL)
            persist()
            return
        }
        
        // If the article is basically done (>97%), mark as finished and remove
        if clamped > 0.97 {
            positions.removeValue(forKey: articleURL)
            persist()
            return
        }
        
        positions[articleURL] = ReadingPosition(
            percentage: clamped,
            updatedAt: Date(),
            title: title
        )
        persist()
    }
    
    /// Get saved reading position for an article.
    ///
    /// - Parameter articleURL: The article's canonical URL string.
    /// - Returns: The saved position, or `nil` if none exists or it expired.
    func position(for articleURL: String) -> ReadingPosition? {
        guard let pos = positions[articleURL] else { return nil }
        
        // Check expiration
        if Date().timeIntervalSince(pos.updatedAt) > expirationInterval {
            positions.removeValue(forKey: articleURL)
            persist()
            return nil
        }
        
        return pos
    }
    
    /// Get all in-progress articles sorted by most recently read.
    ///
    /// - Returns: Array of (URL, position) tuples, most recent first.
    func inProgressArticles() -> [(url: String, position: ReadingPosition)] {
        pruneExpired()
        return positions
            .map { (url: $0.key, position: $0.value) }
            .sorted { $0.position.updatedAt > $1.position.updatedAt }
    }
    
    /// Remove saved position for an article (e.g., when user finishes reading).
    ///
    /// - Parameter articleURL: The article's canonical URL string.
    func clearPosition(for articleURL: String) {
        positions.removeValue(forKey: articleURL)
        persist()
    }
    
    /// Remove all saved positions.
    func clearAll() {
        positions.removeAll()
        persist()
    }
    
    /// Number of articles with saved positions.
    var count: Int {
        return positions.count
    }
    
    // MARK: - Persistence
    
    private func persist() {
        do {
            let data = try JSONEncoder().encode(positions)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            // Silently fail — reading positions are non-critical
        }
    }
    
    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: storageURL)
            positions = try JSONDecoder().decode([String: ReadingPosition].self, from: data)
            pruneExpired()
        } catch {
            positions = [:]
        }
    }
    
    private func pruneExpired() {
        let now = Date()
        let before = positions.count
        positions = positions.filter { now.timeIntervalSince($0.value.updatedAt) <= expirationInterval }
        if positions.count != before {
            persist()
        }
    }
}
