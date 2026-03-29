//
//  FeedRatingManager.swift
//  FeedReader
//
//  Allows users to rate feeds on a 1-5 star scale. Ratings are persisted
//  using UserDefaults and can be used to sort/filter feeds by quality.
//

import Foundation

/// Manages user ratings for RSS feeds on a 1-5 star scale.
/// Ratings persist across sessions and can drive feed sorting/recommendations.
class FeedRatingManager {
    
    // MARK: - Singleton
    
    static let shared = FeedRatingManager()
    
    // MARK: - Notifications
    
    /// Posted when any feed rating changes. The `userInfo` contains "feedIdentifier" and "rating".
    static let ratingDidChangeNotification = Notification.Name("FeedRatingDidChange")
    
    // MARK: - Storage
    
    private let defaults = UserDefaults.standard
    private let storageKey = "com.feedreader.feedRatings"
    
    /// In-memory cache of ratings: [feedIdentifier: rating]
    private var ratings: [String: Int] = [:]
    
    // MARK: - Initialization
    
    private init() {
        loadRatings()
    }
    
    // MARK: - Public API
    
    /// Set a rating (1-5) for a feed. Pass nil to remove the rating.
    /// - Parameters:
    ///   - rating: Star rating from 1 to 5, or nil to clear.
    ///   - feed: The feed to rate.
    func setRating(_ rating: Int?, for feed: Feed) {
        setRating(rating, forIdentifier: feed.identifier)
    }
    
    /// Set a rating (1-5) for a feed identifier. Pass nil to remove.
    func setRating(_ rating: Int?, forIdentifier identifier: String) {
        if let rating = rating {
            let clamped = min(max(rating, 1), 5)
            ratings[identifier] = clamped
        } else {
            ratings.removeValue(forKey: identifier)
        }
        saveRatings()
        
        NotificationCenter.default.post(
            name: FeedRatingManager.ratingDidChangeNotification,
            object: self,
            userInfo: [
                "feedIdentifier": identifier,
                "rating": rating as Any
            ]
        )
    }
    
    /// Get the rating for a feed, or nil if unrated.
    func rating(for feed: Feed) -> Int? {
        return ratings[feed.identifier]
    }
    
    /// Get the rating for a feed identifier, or nil if unrated.
    func rating(forIdentifier identifier: String) -> Int? {
        return ratings[identifier]
    }
    
    /// Get the average rating across all rated feeds, or nil if none are rated.
    func averageRating() -> Double? {
        guard !ratings.isEmpty else { return nil }
        let sum = ratings.values.reduce(0, +)
        return Double(sum) / Double(ratings.count)
    }
    
    /// Get all rated feed identifiers sorted by rating (highest first).
    func topRatedIdentifiers() -> [String] {
        return ratings.sorted { $0.value > $1.value }.map { $0.key }
    }
    
    /// Sort an array of feeds by rating (highest first). Unrated feeds go to the end.
    func sortedByRating(_ feeds: [Feed]) -> [Feed] {
        return feeds.sorted { a, b in
            let ratingA = rating(for: a) ?? 0
            let ratingB = rating(for: b) ?? 0
            if ratingA != ratingB {
                return ratingA > ratingB
            }
            return a.name < b.name
        }
    }
    
    /// Get all feeds from an array that have a minimum rating.
    func feeds(_ feeds: [Feed], withMinimumRating minRating: Int) -> [Feed] {
        return feeds.filter { (rating(for: $0) ?? 0) >= minRating }
    }
    
    /// Returns a star string representation (e.g., "★★★☆☆" for rating 3).
    static func starString(for rating: Int) -> String {
        let clamped = min(max(rating, 0), 5)
        let filled = String(repeating: "★", count: clamped)
        let empty = String(repeating: "☆", count: 5 - clamped)
        return filled + empty
    }
    
    /// Returns a star string for an optional rating, showing "☆☆☆☆☆" if unrated.
    static func starString(forOptional rating: Int?) -> String {
        return starString(for: rating ?? 0)
    }
    
    /// Get statistics about ratings distribution.
    func ratingDistribution() -> [Int: Int] {
        var distribution: [Int: Int] = [1: 0, 2: 0, 3: 0, 4: 0, 5: 0]
        for rating in ratings.values {
            distribution[rating, default: 0] += 1
        }
        return distribution
    }
    
    /// Number of rated feeds.
    var ratedCount: Int {
        return ratings.count
    }
    
    /// Remove all ratings.
    func clearAllRatings() {
        ratings.removeAll()
        saveRatings()
    }
    
    /// Export ratings as a dictionary for backup/sharing.
    func exportRatings() -> [String: Int] {
        return ratings
    }
    
    /// Import ratings from a dictionary, merging with existing (import wins on conflict).
    func importRatings(_ imported: [String: Int]) {
        for (key, value) in imported {
            let clamped = min(max(value, 1), 5)
            ratings[key] = clamped
        }
        saveRatings()
    }
    
    // MARK: - Persistence
    
    private func loadRatings() {
        if let stored = defaults.dictionary(forKey: storageKey) as? [String: Int] {
            ratings = stored
        }
    }
    
    private func saveRatings() {
        defaults.set(ratings, forKey: storageKey)
    }
}
