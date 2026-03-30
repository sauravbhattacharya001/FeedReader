//
//  SmartFeedMixer.swift
//  FeedReader
//
//  Blends articles from multiple feeds into a single mixed timeline with
//  configurable ratios. Users can assign weight percentages to each feed,
//  and the mixer produces a balanced reading queue that respects those
//  proportions while maintaining chronological order within each feed.
//
//  Usage:
//    let mixer = SmartFeedMixer()
//    mixer.setWeight(for: "TechCrunch", weight: 40)
//    mixer.setWeight(for: "ArsTechnica", weight: 30)
//    mixer.setWeight(for: "HackerNews", weight: 30)
//    let mixed = mixer.mix(articles: allArticles, limit: 50)
//    let queue = mixer.generateReadingQueue(from: allArticles)
//

import Foundation

// MARK: - Models

/// Weight configuration for a single feed in the mixer.
struct FeedWeight: Codable, Equatable {
    let feedName: String
    var weight: Int  // percentage (0-100)
    var isPinned: Bool  // pinned feeds always appear first
    
    init(feedName: String, weight: Int = 50, isPinned: Bool = false) {
        self.feedName = feedName
        self.weight = max(0, min(100, weight))
        self.isPinned = isPinned
    }
}

/// An article in the mixer pipeline.
struct MixableArticle: Codable, Equatable {
    let id: String
    let title: String
    let feedName: String
    let publishedAt: Date
    let url: String
    let summary: String?
    
    init(id: String = UUID().uuidString, title: String, feedName: String,
         publishedAt: Date = Date(), url: String = "", summary: String? = nil) {
        self.id = id
        self.title = title
        self.feedName = feedName
        self.publishedAt = publishedAt
        self.url = url
        self.summary = summary
    }
}

/// A mixed reading queue with metadata.
struct MixedQueue: Codable, Equatable {
    let articles: [MixableArticle]
    let feedBreakdown: [FeedBreakdown]
    let generatedAt: Date
    let totalArticles: Int
}

/// Breakdown of how many articles came from each feed in a mix.
struct FeedBreakdown: Codable, Equatable {
    let feedName: String
    let count: Int
    let targetPercentage: Int
    let actualPercentage: Double
}

/// A saved mixer preset for quick switching.
struct MixerPreset: Codable, Equatable {
    let id: String
    let name: String
    let weights: [FeedWeight]
    let createdAt: Date
    
    init(name: String, weights: [FeedWeight]) {
        self.id = UUID().uuidString
        self.name = name
        self.weights = weights
        self.createdAt = Date()
    }
}

// MARK: - SmartFeedMixer

/// Blends articles from multiple feeds into a balanced reading queue.
final class SmartFeedMixer {
    
    private var weights: [String: FeedWeight] = [:]
    private var presets: [MixerPreset] = []
    private let storageKey = "SmartFeedMixer_Weights"
    private let presetsKey = "SmartFeedMixer_Presets"
    
    init() {
        loadWeights()
        loadPresets()
    }
    
    // MARK: - Weight Management
    
    /// Set the weight for a specific feed (0-100).
    func setWeight(for feedName: String, weight: Int) {
        var fw = weights[feedName] ?? FeedWeight(feedName: feedName)
        fw.weight = max(0, min(100, weight))
        weights[feedName] = fw
        saveWeights()
    }
    
    /// Pin or unpin a feed (pinned articles appear first).
    func setPinned(for feedName: String, pinned: Bool) {
        var fw = weights[feedName] ?? FeedWeight(feedName: feedName)
        fw.isPinned = pinned
        weights[feedName] = fw
        saveWeights()
    }
    
    /// Remove weight configuration for a feed.
    func removeWeight(for feedName: String) {
        weights.removeValue(forKey: feedName)
        saveWeights()
    }
    
    /// Get current weight for a feed (defaults to 50 if not set).
    func getWeight(for feedName: String) -> FeedWeight {
        return weights[feedName] ?? FeedWeight(feedName: feedName)
    }
    
    /// Get all configured weights.
    func allWeights() -> [FeedWeight] {
        return Array(weights.values).sorted { $0.weight > $1.weight }
    }
    
    /// Reset all weights to equal distribution.
    func equalizeWeights() {
        let feeds = Array(weights.keys)
        guard !feeds.isEmpty else { return }
        let equalWeight = 100 / feeds.count
        for feed in feeds {
            weights[feed] = FeedWeight(feedName: feed, weight: equalWeight,
                                        isPinned: weights[feed]?.isPinned ?? false)
        }
        saveWeights()
    }
    
    // MARK: - Mixing
    
    /// Mix articles from multiple feeds according to configured weights.
    /// Returns a balanced list respecting weight proportions.
    func mix(articles: [MixableArticle], limit: Int = 50) -> [MixableArticle] {
        guard !articles.isEmpty else { return [] }
        
        // Group articles by feed, sorted by date within each group
        var byFeed: [String: [MixableArticle]] = [:]
        for article in articles {
            byFeed[article.feedName, default: []].append(article)
        }
        for key in byFeed.keys {
            byFeed[key]?.sort { $0.publishedAt > $1.publishedAt }
        }
        
        // Calculate normalized weights for feeds that have articles
        let activeFeeds = byFeed.keys
        let totalWeight = activeFeeds.reduce(0) { sum, feed in
            sum + (weights[feed]?.weight ?? 50)
        }
        guard totalWeight > 0 else {
            // No weights; fall back to chronological
            return Array(articles.sorted { $0.publishedAt > $1.publishedAt }.prefix(limit))
        }
        
        // Calculate target counts per feed
        var targets: [String: Int] = [:]
        for feed in activeFeeds {
            let w = weights[feed]?.weight ?? 50
            let target = max(1, Int(round(Double(w) * Double(limit) / Double(totalWeight))))
            targets[feed] = target
        }
        
        // Build result: pinned first, then interleaved by weight
        var result: [MixableArticle] = []
        var cursors: [String: Int] = [:]
        for feed in activeFeeds { cursors[feed] = 0 }
        
        // Phase 1: Pinned feeds' articles first
        let pinnedFeeds = activeFeeds.filter { weights[$0]?.isPinned == true }
        for feed in pinnedFeeds {
            guard let feedArticles = byFeed[feed] else { continue }
            let count = min(targets[feed] ?? 1, feedArticles.count)
            for i in 0..<count {
                result.append(feedArticles[i])
                cursors[feed] = i + 1
            }
        }
        
        // Phase 2: Round-robin from remaining feeds weighted by target count
        let unpinnedFeeds = activeFeeds.filter { weights[$0]?.isPinned != true }
            .sorted { (weights[$0]?.weight ?? 50) > (weights[$1]?.weight ?? 50) }
        
        var remaining = limit - result.count
        var changed = true
        while remaining > 0 && changed {
            changed = false
            for feed in unpinnedFeeds {
                guard remaining > 0 else { break }
                guard let feedArticles = byFeed[feed] else { continue }
                let cursor = cursors[feed] ?? 0
                let target = targets[feed] ?? 1
                let taken = result.filter { $0.feedName == feed }.count
                if taken < target && cursor < feedArticles.count {
                    result.append(feedArticles[cursor])
                    cursors[feed] = cursor + 1
                    remaining -= 1
                    changed = true
                }
            }
        }
        
        // If still under limit, fill with remaining articles chronologically
        if result.count < limit {
            let usedIds = Set(result.map { $0.id })
            let extras = articles
                .filter { !usedIds.contains($0.id) }
                .sorted { $0.publishedAt > $1.publishedAt }
            result.append(contentsOf: extras.prefix(limit - result.count))
        }
        
        return Array(result.prefix(limit))
    }
    
    /// Generate a full reading queue with metadata.
    func generateReadingQueue(from articles: [MixableArticle], limit: Int = 50) -> MixedQueue {
        let mixed = mix(articles: articles, limit: limit)
        
        // Calculate breakdown
        var feedCounts: [String: Int] = [:]
        for article in mixed {
            feedCounts[article.feedName, default: 0] += 1
        }
        
        let breakdown = feedCounts.map { feed, count in
            FeedBreakdown(
                feedName: feed,
                count: count,
                targetPercentage: weights[feed]?.weight ?? 50,
                actualPercentage: mixed.isEmpty ? 0 : Double(count) / Double(mixed.count) * 100
            )
        }.sorted { $0.count > $1.count }
        
        return MixedQueue(
            articles: mixed,
            feedBreakdown: breakdown,
            generatedAt: Date(),
            totalArticles: mixed.count
        )
    }
    
    // MARK: - Presets
    
    /// Save current weights as a named preset.
    func savePreset(name: String) -> MixerPreset {
        let preset = MixerPreset(name: name, weights: Array(weights.values))
        presets.removeAll { $0.name == name }
        presets.append(preset)
        savePresets()
        return preset
    }
    
    /// Load a preset by name, replacing current weights.
    func loadPreset(name: String) -> Bool {
        guard let preset = presets.first(where: { $0.name == name }) else { return false }
        weights = [:]
        for fw in preset.weights {
            weights[fw.feedName] = fw
        }
        saveWeights()
        return true
    }
    
    /// Delete a preset by name.
    func deletePreset(name: String) {
        presets.removeAll { $0.name == name }
        savePresets()
    }
    
    /// List all saved presets.
    func listPresets() -> [MixerPreset] {
        return presets.sorted { $0.createdAt > $1.createdAt }
    }
    
    // MARK: - Discovery
    
    /// Auto-discover feeds from articles and assign equal weights to any new ones.
    func discoverFeeds(from articles: [MixableArticle]) -> [String] {
        let feedNames = Set(articles.map { $0.feedName })
        var newFeeds: [String] = []
        for feed in feedNames {
            if weights[feed] == nil {
                weights[feed] = FeedWeight(feedName: feed)
                newFeeds.append(feed)
            }
        }
        if !newFeeds.isEmpty { saveWeights() }
        return newFeeds.sorted()
    }
    
    /// Get feed diversity score (0-100). Higher = more evenly distributed.
    func diversityScore(for articles: [MixableArticle]) -> Int {
        let mixed = mix(articles: articles)
        guard !mixed.isEmpty else { return 0 }
        
        var feedCounts: [String: Int] = [:]
        for article in mixed {
            feedCounts[article.feedName, default: 0] += 1
        }
        
        let n = feedCounts.count
        guard n > 1 else { return 0 }
        
        // Shannon entropy normalized to 0-100
        let total = Double(mixed.count)
        var entropy = 0.0
        for count in feedCounts.values {
            let p = Double(count) / total
            if p > 0 { entropy -= p * log2(p) }
        }
        let maxEntropy = log2(Double(n))
        return maxEntropy > 0 ? Int(round(entropy / maxEntropy * 100)) : 0
    }
    
    // MARK: - Persistence
    
    private func saveWeights() {
        if let data = try? JSONEncoder().encode(Array(weights.values)) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    private func loadWeights() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let loaded = try? JSONDecoder().decode([FeedWeight].self, from: data) else { return }
        weights = [:]
        for fw in loaded {
            weights[fw.feedName] = fw
        }
    }
    
    private func savePresets() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: presetsKey)
        }
    }
    
    private func loadPresets() {
        guard let data = UserDefaults.standard.data(forKey: presetsKey),
              let loaded = try? JSONDecoder().decode([MixerPreset].self, from: data) else { return }
        presets = loaded
    }
}
