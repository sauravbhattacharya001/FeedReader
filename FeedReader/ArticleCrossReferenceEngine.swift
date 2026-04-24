//
//  ArticleCrossReferenceEngine.swift
//  FeedReader
//
//  Cross-references articles by extracting named entities (people, places,
//  organizations, events) and linking articles that share them. Unlike
//  ArticleSimilarityManager (overall topic similarity via TF-IDF), this
//  focuses on *specific* entity co-occurrence — answering "which other
//  articles mention the same people, companies, or places?"
//
//  Features:
//    - Named entity extraction using capitalized phrase heuristics
//    - Entity type classification (person, organization, place, event)
//    - Cross-reference index: entity → [article links]
//    - Article → related articles via shared entities
//    - Entity frequency tracking and trending entity detection
//    - Entity timeline: when entities first/last appeared
//    - Merge and disambiguation of entity variants
//    - JSON export/import of entity index
//
//  Persistence: UserDefaults via UserDefaultsCodableStore.
//  Works entirely offline with no external dependencies.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when the entity index is rebuilt or updated.
    static let entityIndexDidUpdate = Notification.Name("EntityIndexDidUpdateNotification")
}

// MARK: - Entity Types

/// Classification of a named entity.
enum EntityType: String, Codable, CaseIterable {
    case person
    case organization
    case place
    case event
    case product
    case unknown
}

/// A named entity extracted from article text.
struct NamedEntity: Codable, Hashable {
    let name: String           // Normalized canonical form
    let type: EntityType
    let originalForms: [String] // All surface forms seen (e.g., "Google", "Google Inc.")

    func hash(into hasher: inout Hasher) {
        hasher.combine(name.lowercased())
        hasher.combine(type)
    }

    static func == (lhs: NamedEntity, rhs: NamedEntity) -> Bool {
        lhs.name.lowercased() == rhs.name.lowercased() && lhs.type == rhs.type
    }
}

/// A cross-reference between an article and a named entity.
struct EntityOccurrence: Codable {
    let articleLink: String
    let articleTitle: String
    let feedName: String
    let count: Int             // How many times the entity appears in this article
    let firstSeen: Date
}

/// Statistics for a single entity across all articles.
struct EntityProfile: Codable {
    let entity: NamedEntity
    let totalMentions: Int     // Sum of all occurrence counts
    let articleCount: Int      // Number of distinct articles
    let feedCount: Int         // Number of distinct feeds
    let firstSeen: Date
    let lastSeen: Date
    let occurrences: [EntityOccurrence]

    /// Trending score: articles-per-day over the last 7 days.
    var recentVelocity: Double {
        let weekAgo = Date().addingTimeInterval(-7 * 86400)
        let recentCount = occurrences.filter { $0.firstSeen >= weekAgo }.count
        return Double(recentCount) / 7.0
    }
}

/// Cross-reference result: articles related to a given article via shared entities.
struct CrossReference {
    let relatedArticleLink: String
    let relatedArticleTitle: String
    let relatedFeedName: String
    let sharedEntities: [NamedEntity]
    let relevanceScore: Double  // 0.0 to 1.0

    /// Human-readable explanation of why this article is related.
    var explanation: String {
        let entityNames = sharedEntities.prefix(3).map { $0.name }
        let suffix = sharedEntities.count > 3 ? " and \(sharedEntities.count - 3) more" : ""
        return "Shares: \(entityNames.joined(separator: ", "))\(suffix)"
    }
}

/// Summary of the entire entity index.
struct EntityIndexSummary: Codable {
    let totalEntities: Int
    let totalArticlesIndexed: Int
    let entityTypeCounts: [EntityType: Int]
    let topEntities: [EntityProfile]   // Top 10 by article count
    let trendingEntities: [EntityProfile] // Top 5 by recent velocity
    let lastUpdated: Date
}

// MARK: - Persistence Model

/// Codable representation of the entity index for UserDefaults storage.
private struct EntityIndexStore: Codable {
    var entities: [String: NamedEntity]           // normalizedName → entity
    var occurrences: [String: [EntityOccurrence]] // normalizedName → occurrences
    var indexedArticles: Set<String>              // article links already indexed
    var lastUpdated: Date

    static var empty: EntityIndexStore {
        EntityIndexStore(entities: [:], occurrences: [:], indexedArticles: [], lastUpdated: Date())
    }
}

// MARK: - ArticleCrossReferenceEngine

/// Extracts named entities from articles and builds a cross-reference index.
class ArticleCrossReferenceEngine {

    // MARK: - Singleton

    static let shared = ArticleCrossReferenceEngine()

    // MARK: - Properties

    private var store: EntityIndexStore
    private let storageKey = "ArticleCrossReferenceEngine.index"
    private let defaults = UserDefaults.standard
    /// Delegates to the canonical stop-word list in TextAnalyzer.
    private var stopWords: Set<String> { TextAnalyzer.stopWords }

    /// Common title prefixes that indicate person names.
    private let personPrefixes: Set<String> = [
        "mr", "mrs", "ms", "dr", "prof", "president", "ceo", "cto",
        "senator", "governor", "mayor", "judge", "general", "captain",
        "minister", "prime", "king", "queen", "prince", "princess"
    ]

    /// Common organization suffixes.
    private let orgSuffixes: Set<String> = [
        "inc", "corp", "ltd", "llc", "co", "company", "group", "foundation",
        "institute", "university", "college", "association", "organization",
        "department", "agency", "commission", "council", "authority",
        "bank", "fund", "trust", "partners", "labs", "technologies",
        "solutions", "services", "systems", "industries", "global",
        "international", "network", "media", "press", "times", "post",
        "news", "journal", "review", "tribune", "herald", "gazette"
    ]

    /// Common place indicators.
    private let placeIndicators: Set<String> = [
        "city", "state", "county", "province", "region", "district",
        "island", "mountain", "river", "lake", "ocean", "sea", "bay",
        "valley", "peninsula", "strait", "gulf", "cape", "port",
        "north", "south", "east", "west", "central", "united",
        "republic", "kingdom", "states", "union"
    ]

    // MARK: - Initialization

    private init() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONCoding.iso8601Decoder.decode(EntityIndexStore.self, from: data) {
            store = decoded
        } else {
            store = .empty
        }
    }

    // MARK: - Indexing

    /// Index a single article, extracting entities and adding to the cross-reference index.
    func indexArticle(_ story: Story) {
        let link = story.link
        guard !store.indexedArticles.contains(link) else { return }

        let entities = extractEntities(from: story)
        let now = Date()

        for (entity, count) in entities {
            let key = entity.name.lowercased()

            // Store/update entity
            if let existing = store.entities[key] {
                // Merge original forms
                var forms = Set(existing.originalForms)
                forms.formUnion(entity.originalForms)
                store.entities[key] = NamedEntity(
                    name: existing.name,
                    type: existing.type,
                    originalForms: Array(forms).sorted()
                )
            } else {
                store.entities[key] = entity
            }

            // Add occurrence
            let occurrence = EntityOccurrence(
                articleLink: link,
                articleTitle: story.title,
                feedName: story.sourceFeedName ?? "Unknown",
                count: count,
                firstSeen: now
            )
            store.occurrences[key, default: []].append(occurrence)
        }

        store.indexedArticles.insert(link)
        store.lastUpdated = now
        save()

        NotificationCenter.default.post(name: .entityIndexDidUpdate, object: self)
    }

    /// Index multiple articles at once.
    func indexArticles(_ stories: [Story]) {
        for story in stories {
            indexArticle(story)
        }
    }

    /// Remove an article from the index.
    func removeArticle(link: String) {
        guard store.indexedArticles.contains(link) else { return }

        store.indexedArticles.remove(link)

        // Remove occurrences referencing this article
        for (key, occurrences) in store.occurrences {
            store.occurrences[key] = occurrences.filter { $0.articleLink != link }
            if store.occurrences[key]?.isEmpty == true {
                store.occurrences.removeValue(forKey: key)
                store.entities.removeValue(forKey: key)
            }
        }

        store.lastUpdated = Date()
        save()
    }

    /// Clear the entire index.
    func clearIndex() {
        store = .empty
        save()
        NotificationCenter.default.post(name: .entityIndexDidUpdate, object: self)
    }

    // MARK: - Cross-Referencing

    /// Find articles related to a given article via shared entities.
    /// Returns results sorted by relevance (most shared entities first).
    func findCrossReferences(for story: Story, limit: Int = 10) -> [CrossReference] {
        let entities = extractEntities(from: story)
        let entityKeys = Set(entities.keys.map { $0.name.lowercased() })

        guard !entityKeys.isEmpty else { return [] }

        // Find all articles that share at least one entity
        var articleScores: [String: (title: String, feed: String, shared: [NamedEntity], score: Double)] = [:]

        for key in entityKeys {
            guard let entity = store.entities[key],
                  let occurrences = store.occurrences[key] else { continue }

            for occ in occurrences where occ.articleLink != story.link {
                if var existing = articleScores[occ.articleLink] {
                    existing.shared.append(entity)
                    existing.score += 1.0 + Double(occ.count) * 0.1
                    articleScores[occ.articleLink] = existing
                } else {
                    articleScores[occ.articleLink] = (
                        title: occ.articleTitle,
                        feed: occ.feedName,
                        shared: [entity],
                        score: 1.0 + Double(occ.count) * 0.1
                    )
                }
            }
        }

        // Normalize scores
        let maxScore = articleScores.values.map(\.score).max() ?? 1.0

        return articleScores
            .map { (link, info) in
                CrossReference(
                    relatedArticleLink: link,
                    relatedArticleTitle: info.title,
                    relatedFeedName: info.feed,
                    sharedEntities: info.shared,
                    relevanceScore: min(1.0, info.score / max(maxScore, 1.0))
                )
            }
            .sorted { $0.relevanceScore > $1.relevanceScore }
            .prefix(limit)
            .map { $0 }
    }

    /// Find all articles mentioning a specific entity.
    func articles(mentioning entityName: String) -> [EntityOccurrence] {
        let key = entityName.lowercased()
        return store.occurrences[key] ?? []
    }

    /// Get the full profile for a named entity.
    func profile(for entityName: String) -> EntityProfile? {
        let key = entityName.lowercased()
        guard let entity = store.entities[key],
              let occurrences = store.occurrences[key],
              !occurrences.isEmpty else { return nil }

        let feeds = Set(occurrences.map(\.feedName))
        let dates = occurrences.map(\.firstSeen)

        return EntityProfile(
            entity: entity,
            totalMentions: occurrences.reduce(0) { $0 + $1.count },
            articleCount: occurrences.count,
            feedCount: feeds.count,
            firstSeen: dates.min() ?? Date(),
            lastSeen: dates.max() ?? Date(),
            occurrences: occurrences.sorted { $0.firstSeen > $1.firstSeen }
        )
    }

    // MARK: - Entity Discovery

    /// Get all known entities, optionally filtered by type.
    func allEntities(ofType type: EntityType? = nil) -> [NamedEntity] {
        if let type = type {
            return store.entities.values.filter { $0.type == type }.sorted { $0.name < $1.name }
        }
        return store.entities.values.sorted { $0.name < $1.name }
    }

    /// Search entities by name prefix.
    func searchEntities(prefix: String) -> [NamedEntity] {
        let lowerPrefix = prefix.lowercased()
        return store.entities.values
            .filter { $0.name.lowercased().hasPrefix(lowerPrefix) }
            .sorted { $0.name < $1.name }
    }

    /// Get trending entities (most mentioned in the last 7 days).
    func trendingEntities(limit: Int = 10) -> [EntityProfile] {
        let weekAgo = Date().addingTimeInterval(-7 * 86400)

        return store.entities.keys.compactMap { key -> EntityProfile? in
            guard let entity = store.entities[key],
                  let occurrences = store.occurrences[key] else { return nil }
            let recent = occurrences.filter { $0.firstSeen >= weekAgo }
            guard !recent.isEmpty else { return nil }

            let feeds = Set(occurrences.map(\.feedName))
            let dates = occurrences.map(\.firstSeen)

            return EntityProfile(
                entity: entity,
                totalMentions: occurrences.reduce(0) { $0 + $1.count },
                articleCount: occurrences.count,
                feedCount: feeds.count,
                firstSeen: dates.min() ?? Date(),
                lastSeen: dates.max() ?? Date(),
                occurrences: occurrences
            )
        }
        .sorted { $0.recentVelocity > $1.recentVelocity }
        .prefix(limit)
        .map { $0 }
    }

    /// Get a summary of the entire entity index.
    func indexSummary() -> EntityIndexSummary {
        var typeCounts: [EntityType: Int] = [:]
        for entity in store.entities.values {
            typeCounts[entity.type, default: 0] += 1
        }

        let profiles = store.entities.keys.compactMap { profile(for: $0) }
        let sorted = profiles.sorted { $0.articleCount > $1.articleCount }

        let weekAgo = Date().addingTimeInterval(-7 * 86400)
        let trending = profiles
            .filter { $0.occurrences.contains { $0.firstSeen >= weekAgo } }
            .sorted { $0.recentVelocity > $1.recentVelocity }

        return EntityIndexSummary(
            totalEntities: store.entities.count,
            totalArticlesIndexed: store.indexedArticles.count,
            entityTypeCounts: typeCounts,
            topEntities: Array(sorted.prefix(10)),
            trendingEntities: Array(trending.prefix(5)),
            lastUpdated: store.lastUpdated
        )
    }

    // MARK: - Entity Merge / Disambiguation

    /// Merge two entities that refer to the same real-world entity.
    /// Keeps the primary entity's name, merges occurrences and forms.
    func mergeEntities(primary: String, duplicate: String) {
        let primaryKey = primary.lowercased()
        let dupeKey = duplicate.lowercased()

        guard let primaryEntity = store.entities[primaryKey],
              let dupeEntity = store.entities[dupeKey] else { return }

        // Merge original forms
        var forms = Set(primaryEntity.originalForms)
        forms.formUnion(dupeEntity.originalForms)
        store.entities[primaryKey] = NamedEntity(
            name: primaryEntity.name,
            type: primaryEntity.type,
            originalForms: Array(forms).sorted()
        )

        // Merge occurrences
        let dupeOccurrences = store.occurrences[dupeKey] ?? []
        store.occurrences[primaryKey, default: []].append(contentsOf: dupeOccurrences)

        // Remove duplicate
        store.entities.removeValue(forKey: dupeKey)
        store.occurrences.removeValue(forKey: dupeKey)

        store.lastUpdated = Date()
        save()
    }

    // MARK: - Export/Import

    /// Export the entity index as JSON data.
    func exportJSON(prettyPrint: Bool = true) -> Data? {
        let encoder = prettyPrint ? JSONCoding.iso8601PrettyEncoder : JSONCoding.iso8601Encoder
        return try? encoder.encode(store)
    }

    /// Import an entity index from JSON data, merging with existing.
    func importJSON(_ data: Data, merge: Bool = true) -> Bool {
        guard let imported = try? JSONCoding.iso8601Decoder.decode(EntityIndexStore.self, from: data) else {
            return false
        }

        if merge {
            // Merge entities
            for (key, entity) in imported.entities {
                if let existing = store.entities[key] {
                    var forms = Set(existing.originalForms)
                    forms.formUnion(entity.originalForms)
                    store.entities[key] = NamedEntity(
                        name: existing.name,
                        type: existing.type,
                        originalForms: Array(forms).sorted()
                    )
                } else {
                    store.entities[key] = entity
                }
            }

            // Merge occurrences (deduplicate by article link)
            for (key, occurrences) in imported.occurrences {
                let existing = Set((store.occurrences[key] ?? []).map(\.articleLink))
                let newOccurrences = occurrences.filter { !existing.contains($0.articleLink) }
                store.occurrences[key, default: []].append(contentsOf: newOccurrences)
            }

            store.indexedArticles.formUnion(imported.indexedArticles)
        } else {
            store = imported
        }

        store.lastUpdated = Date()
        save()
        NotificationCenter.default.post(name: .entityIndexDidUpdate, object: self)
        return true
    }

    // MARK: - Entity Extraction

    /// Extract named entities from a story. Returns entity → mention count.
    func extractEntities(from story: Story) -> [NamedEntity: Int] {
        let text = "\(story.title) \(story.body)"
        return extractEntitiesFromText(text)
    }

    /// Core entity extraction from raw text using capitalization heuristics.
    func extractEntitiesFromText(_ text: String) -> [NamedEntity: Int] {
        let cleanText = text
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&[a-zA-Z]+;", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&#\\d+;", with: " ", options: .regularExpression)

        // Split into sentences for context
        let sentences = cleanText.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))

        var entityCounts: [String: (entity: NamedEntity, count: Int)] = [:]

        for sentence in sentences {
            let words = sentence.split(separator: " ").map { String($0) }
            let phrases = extractCapitalizedPhrases(from: words)

            for phrase in phrases {
                let normalized = normalizeEntityName(phrase)
                guard normalized.count >= 2 else { continue }
                guard !isStopPhrase(normalized) else { continue }

                let type = classifyEntity(normalized, context: sentence)
                let key = normalized.lowercased()

                if var existing = entityCounts[key] {
                    existing.count += 1
                    // Add original form if new
                    if !existing.entity.originalForms.contains(phrase) {
                        var forms = existing.entity.originalForms
                        forms.append(phrase)
                        existing.entity = NamedEntity(
                            name: existing.entity.name,
                            type: existing.entity.type,
                            originalForms: forms
                        )
                    }
                    entityCounts[key] = existing
                } else {
                    let entity = NamedEntity(
                        name: normalized,
                        type: type,
                        originalForms: [phrase]
                    )
                    entityCounts[key] = (entity: entity, count: 1)
                }
            }
        }

        var result: [NamedEntity: Int] = [:]
        for (_, value) in entityCounts {
            result[value.entity] = value.count
        }
        return result
    }

    // MARK: - Private Helpers

    /// Extract capitalized multi-word phrases from a word list.
    private func extractCapitalizedPhrases(from words: [String]) -> [String] {
        var phrases: [String] = []
        var currentPhrase: [String] = []

        for (index, word) in words.enumerated() {
            let cleaned = word.trimmingCharacters(in: .punctuationCharacters)
            guard !cleaned.isEmpty else {
                if !currentPhrase.isEmpty {
                    phrases.append(currentPhrase.joined(separator: " "))
                    currentPhrase = []
                }
                continue
            }

            let isCapitalized = cleaned.first?.isUppercase == true
            let isShortConnector = ["of", "the", "and", "for", "in", "de", "van", "von", "al", "el", "la", "le"].contains(cleaned.lowercased())

            if isCapitalized {
                // Skip if it's the first word of a sentence (might just be capitalized)
                if index == 0 && currentPhrase.isEmpty {
                    // Only include if next word is also capitalized (proper noun phrase)
                    if index + 1 < words.count {
                        let nextCleaned = words[index + 1].trimmingCharacters(in: .punctuationCharacters)
                        if nextCleaned.first?.isUppercase == true {
                            currentPhrase.append(cleaned)
                        }
                    }
                    // Single capitalized word at sentence start — skip to avoid false positives
                    continue
                }
                currentPhrase.append(cleaned)
            } else if isShortConnector && !currentPhrase.isEmpty {
                // Allow "of", "the" etc. in the middle of entity names
                // e.g., "Bank of America", "University of Washington"
                currentPhrase.append(cleaned)
            } else {
                if !currentPhrase.isEmpty {
                    // Drop trailing connectors
                    while let last = currentPhrase.last,
                          ["of", "the", "and", "for", "in", "de", "van", "von", "al", "el", "la", "le"].contains(last.lowercased()) {
                        currentPhrase.removeLast()
                    }
                    if !currentPhrase.isEmpty {
                        phrases.append(currentPhrase.joined(separator: " "))
                    }
                    currentPhrase = []
                }
            }
        }

        // Flush remaining
        if !currentPhrase.isEmpty {
            while let last = currentPhrase.last,
                  ["of", "the", "and", "for", "in", "de", "van", "von", "al", "el", "la", "le"].contains(last.lowercased()) {
                currentPhrase.removeLast()
            }
            if !currentPhrase.isEmpty {
                phrases.append(currentPhrase.joined(separator: " "))
            }
        }

        return phrases
    }

    /// Normalize an entity name: trim, collapse whitespace, title-case.
    private func normalizeEntityName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = trimmed.replacingOccurrences(
            of: "\\s+", with: " ", options: .regularExpression
        )
        // Keep original casing for proper nouns
        return collapsed
    }

    /// Check if a phrase is a common false positive.
    private func isStopPhrase(_ phrase: String) -> Bool {
        let lower = phrase.lowercased()

        // Single word stop words
        if stopWords.contains(lower) { return true }

        // Common false positive patterns
        let falsePositives: Set<String> = [
            "read more", "click here", "sign up", "log in", "share this",
            "related articles", "breaking news", "top stories", "more news",
            "follow us", "subscribe now", "latest news", "view all",
            "copyright", "all rights reserved", "terms of service",
            "privacy policy", "contact us", "about us", "see also"
        ]
        if falsePositives.contains(lower) { return true }

        // All-digit strings
        if lower.allSatisfy({ $0.isNumber || $0 == " " }) { return true }

        // Too short
        if phrase.count < 2 { return true }

        // Dates (e.g., "January 2024", "March 15")
        let months: Set<String> = [
            "january", "february", "march", "april", "may", "june",
            "july", "august", "september", "october", "november", "december",
            "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "oct", "nov", "dec",
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"
        ]
        let words = lower.split(separator: " ")
        if words.count <= 2 && words.contains(where: { months.contains(String($0)) }) {
            return true
        }

        return false
    }

    /// Classify an entity by type using heuristic rules.
    private func classifyEntity(_ name: String, context: String) -> EntityType {
        let lowerName = name.lowercased()
        let lowerContext = context.lowercased()
        let words = lowerName.split(separator: " ").map { String($0) }

        // Check for person indicators
        if words.count >= 1 && words.count <= 4 {
            // Title prefix (Dr., Mr., etc.)
            if let first = words.first, personPrefixes.contains(first) {
                return .person
            }
            // Context clues for people
            let personVerbs = ["said", "told", "announced", "stated", "wrote", "tweeted",
                             "posted", "explained", "argued", "claimed", "believes",
                             "spoke", "testified", "confirmed", "denied"]
            for verb in personVerbs {
                if lowerContext.contains("\(lowerName) \(verb)") ||
                   lowerContext.contains("\(verb) \(lowerName)") {
                    return .person
                }
            }
            // 2-3 word phrases that look like names (First Last)
            if words.count >= 2 && words.count <= 3 &&
               words.allSatisfy({ $0.count >= 2 }) &&
               !words.contains(where: { orgSuffixes.contains($0) }) &&
               !words.contains(where: { placeIndicators.contains($0) }) {
                // Likely a person name if no org/place indicators
                return .person
            }
        }

        // Check for organization suffixes
        if let last = words.last, orgSuffixes.contains(last) {
            return .organization
        }
        // Multi-word with "of" often indicates org
        if words.contains("of") && words.count >= 3 {
            if let last = words.last, placeIndicators.contains(last) {
                return .place
            }
            return .organization
        }

        // Check for place indicators
        for word in words {
            if placeIndicators.contains(word) {
                return .place
            }
        }

        // Context clues for places
        let placePreps = ["in \(lowerName)", "from \(lowerName)", "near \(lowerName)",
                         "across \(lowerName)", "throughout \(lowerName)"]
        for prep in placePreps {
            if lowerContext.contains(prep) {
                return .place
            }
        }

        // Context clues for products/events
        let productVerbs = ["launched", "released", "updated", "announced",
                           "unveiled", "introduced", "ships", "available"]
        for verb in productVerbs {
            if lowerContext.contains("\(verb) \(lowerName)") ||
               lowerContext.contains("\(lowerName) \(verb)") {
                return .product
            }
        }

        return .unknown
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONCoding.iso8601Encoder.encode(store) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
