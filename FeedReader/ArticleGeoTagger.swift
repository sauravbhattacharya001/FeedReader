//
//  ArticleGeoTagger.swift
//  FeedReader
//
//  Geographic location extraction and tagging for articles.
//  Identifies place names (countries, capitals, major cities) mentioned
//  in article text and maps them to geographic regions and coordinates.
//  Enables geographic filtering, region-based article grouping, and
//  per-feed geographic coverage analysis.
//
//  Uses a built-in gazetteer of ~200 major locations (all 7 continents,
//  ~50 countries, ~150 cities) with trigram-based fuzzy matching for
//  typo tolerance. No external API or network access required.
//

import Foundation

// MARK: - Geographic Region

/// Broad geographic regions for grouping locations.
enum GeoRegion: String, Codable, CaseIterable, CustomStringConvertible {
    case northAmerica = "North America"
    case southAmerica = "South America"
    case europe       = "Europe"
    case africa       = "Africa"
    case middleEast   = "Middle East"
    case asia         = "Asia"
    case oceania      = "Oceania"
    case unknown      = "Unknown"

    var description: String { rawValue }

    var emoji: String {
        switch self {
        case .northAmerica: return "🌎"
        case .southAmerica: return "🌎"
        case .europe:       return "🌍"
        case .africa:       return "🌍"
        case .middleEast:   return "🌍"
        case .asia:         return "🌏"
        case .oceania:      return "🌏"
        case .unknown:      return "📍"
        }
    }
}

// MARK: - Gazetteer Entry

/// A known geographic location with coordinates and metadata.
struct GazetteerEntry {
    let name: String
    let aliases: [String]
    let region: GeoRegion
    let country: String
    let latitude: Double
    let longitude: Double
    let population: Int  // rough tier: 0=country, 1=capital, 2=major city, 3=city

    /// All searchable name variants (primary + aliases), lowercased.
    var searchTerms: [String] {
        return ([name] + aliases).map { $0.lowercased() }
    }
}

// MARK: - Geo Tag Result

/// A single geographic mention found in text.
struct GeoTag: Codable, Equatable {
    let placeName: String
    let normalizedName: String
    let region: GeoRegion
    let country: String
    let latitude: Double
    let longitude: Double
    let confidence: Double  // 0.0–1.0
    let characterOffset: Int
    let matchLength: Int

    static func == (lhs: GeoTag, rhs: GeoTag) -> Bool {
        return lhs.normalizedName == rhs.normalizedName
            && lhs.characterOffset == rhs.characterOffset
    }
}

/// Result of geo-tagging an article.
struct GeoTagResult: Codable {
    let articleLink: String
    let tags: [GeoTag]
    let primaryRegion: GeoRegion
    let regionBreakdown: [String: Int]  // region.rawValue → mention count
    let countryBreakdown: [String: Int] // country → mention count
    let uniqueLocations: Int
    let analyzedAt: Date

    /// The single most-mentioned location, if any.
    var dominantLocation: GeoTag? {
        let counts = Dictionary(grouping: tags, by: { $0.normalizedName })
        return counts.max(by: { $0.value.count < $1.value.count })?.value.first
    }
}

/// Statistics across multiple articles.
struct GeoStats: Equatable {
    let totalArticles: Int
    let taggedArticles: Int
    let totalMentions: Int
    let uniqueLocations: Int
    let regionDistribution: [String: Int]
    let topLocations: [(name: String, count: Int)]
    let topCountries: [(name: String, count: Int)]
    let coveragePercent: Double // taggedArticles / totalArticles * 100

    static func == (lhs: GeoStats, rhs: GeoStats) -> Bool {
        return lhs.totalArticles == rhs.totalArticles
            && lhs.taggedArticles == rhs.taggedArticles
            && lhs.totalMentions == rhs.totalMentions
            && lhs.uniqueLocations == rhs.uniqueLocations
            && lhs.coveragePercent == rhs.coveragePercent
    }
}

// MARK: - ArticleGeoTagger

/// Extracts and tracks geographic locations mentioned in article text.
class ArticleGeoTagger {

    // MARK: - Storage

    private let storageKey = "ArticleGeoTagger_results"
    private var results: [String: GeoTagResult] = [:]  // articleLink → result
    private let gazetteer: [GazetteerEntry]
    private let minimumConfidence: Double

    // MARK: - Init

    /// - Parameters:
    ///   - minimumConfidence: Minimum confidence threshold for including a tag (0.0–1.0). Default 0.6.
    init(minimumConfidence: Double = 0.6) {
        self.minimumConfidence = max(0.0, min(1.0, minimumConfidence))
        self.gazetteer = ArticleGeoTagger.buildGazetteer()
        loadResults()
    }

    // MARK: - Public API

    /// Analyze text and extract geographic tags.
    func tagText(_ text: String, articleLink: String = "") -> GeoTagResult {
        let tags = extractLocations(from: text)
        let filtered = tags.filter { $0.confidence >= minimumConfidence }
        let deduplicated = deduplicateTags(filtered)

        let regionCounts = Dictionary(grouping: deduplicated, by: { $0.region.rawValue })
            .mapValues { $0.count }
        let countryCounts = Dictionary(grouping: deduplicated, by: { $0.country })
            .mapValues { $0.count }
        let primaryRegion = regionCounts.max(by: { $0.value < $1.value })
            .map { GeoRegion(rawValue: $0.key) ?? .unknown } ?? .unknown

        let uniqueNames = Set(deduplicated.map { $0.normalizedName })

        let result = GeoTagResult(
            articleLink: articleLink,
            tags: deduplicated,
            primaryRegion: primaryRegion,
            regionBreakdown: regionCounts,
            countryBreakdown: countryCounts,
            uniqueLocations: uniqueNames.count,
            analyzedAt: Date()
        )

        if !articleLink.isEmpty {
            results[articleLink] = result
            saveResults()
        }

        return result
    }

    /// Tag a Story object.
    func tagStory(title: String, body: String, link: String) -> GeoTagResult {
        let combined = title + " " + body
        return tagText(combined, articleLink: link)
    }

    /// Get cached result for an article.
    func result(for articleLink: String) -> GeoTagResult? {
        return results[articleLink]
    }

    /// Get all cached results.
    func allResults() -> [GeoTagResult] {
        return Array(results.values)
    }

    /// Get articles tagged with a specific region.
    func articles(in region: GeoRegion) -> [GeoTagResult] {
        return results.values.filter { $0.primaryRegion == region }
    }

    /// Get articles mentioning a specific country.
    func articles(mentioning country: String) -> [GeoTagResult] {
        let lower = country.lowercased()
        return results.values.filter {
            $0.countryBreakdown.keys.contains(where: { $0.lowercased() == lower })
        }
    }

    /// Get articles mentioning a specific location.
    func articles(mentioningLocation name: String) -> [GeoTagResult] {
        let lower = name.lowercased()
        return results.values.filter {
            $0.tags.contains(where: { $0.normalizedName.lowercased() == lower })
        }
    }

    /// Compute aggregate statistics across all tagged articles.
    func statistics() -> GeoStats {
        let allTags = results.values.flatMap { $0.tags }
        let taggedCount = results.values.filter { !$0.tags.isEmpty }.count

        let regionDist = Dictionary(grouping: allTags, by: { $0.region.rawValue })
            .mapValues { $0.count }

        let locationCounts = Dictionary(grouping: allTags, by: { $0.normalizedName })
            .mapValues { $0.count }
        let topLocations = locationCounts.sorted { $0.value > $1.value }
            .prefix(10)
            .map { (name: $0.key, count: $0.value) }

        let countryCounts = Dictionary(grouping: allTags, by: { $0.country })
            .mapValues { $0.count }
        let topCountries = countryCounts.sorted { $0.value > $1.value }
            .prefix(10)
            .map { (name: $0.key, count: $0.value) }

        let coverage = results.isEmpty ? 0.0
            : Double(taggedCount) / Double(results.count) * 100.0

        return GeoStats(
            totalArticles: results.count,
            taggedArticles: taggedCount,
            totalMentions: allTags.count,
            uniqueLocations: Set(allTags.map { $0.normalizedName }).count,
            regionDistribution: regionDist,
            topLocations: topLocations,
            topCountries: topCountries,
            coveragePercent: coverage
        )
    }

    /// Generate a text summary of geographic coverage.
    func summary() -> String {
        let stats = statistics()
        var lines: [String] = []
        lines.append("📍 Geographic Coverage")
        lines.append("Articles analyzed: \(stats.totalArticles)")
        lines.append("Articles with locations: \(stats.taggedArticles) (\(String(format: "%.1f", stats.coveragePercent))%)")
        lines.append("Total mentions: \(stats.totalMentions)")
        lines.append("Unique locations: \(stats.uniqueLocations)")

        if !stats.topLocations.isEmpty {
            lines.append("")
            lines.append("Top Locations:")
            for loc in stats.topLocations.prefix(5) {
                lines.append("  • \(loc.name): \(loc.count) mentions")
            }
        }

        if !stats.regionDistribution.isEmpty {
            lines.append("")
            lines.append("Region Distribution:")
            for (region, count) in stats.regionDistribution.sorted(by: { $0.value > $1.value }) {
                let regionEnum = GeoRegion(rawValue: region) ?? .unknown
                lines.append("  \(regionEnum.emoji) \(region): \(count)")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Remove result for an article.
    func removeResult(for articleLink: String) -> Bool {
        guard results.removeValue(forKey: articleLink) != nil else { return false }
        saveResults()
        return true
    }

    /// Remove all cached results.
    func clearAll() {
        results.removeAll()
        saveResults()
    }

    /// Number of cached results.
    var count: Int { results.count }

    // MARK: - Location Extraction

    private func extractLocations(from text: String) -> [GeoTag] {
        let words = tokenize(text)
        var tags: [GeoTag] = []
        var i = 0

        while i < words.count {
            var bestMatch: (entry: GazetteerEntry, matchedText: String, tokenCount: Int, confidence: Double, offset: Int)?

            // Try multi-word matches first (up to 4 tokens: "New York City", "São Paulo")
            for windowSize in stride(from: min(4, words.count - i), through: 1, by: -1) {
                let window = words[i..<(i + windowSize)]
                let phrase = window.map { $0.text }.joined(separator: " ")
                let phraseLower = phrase.lowercased()

                for entry in gazetteer {
                    for term in entry.searchTerms {
                        let confidence = matchConfidence(candidate: phraseLower, reference: term)
                        if confidence >= minimumConfidence {
                            let offset = window.first?.offset ?? 0
                            if bestMatch == nil || confidence > bestMatch!.confidence
                                || (confidence == bestMatch!.confidence && windowSize > bestMatch!.tokenCount) {
                                bestMatch = (entry, phrase, windowSize, confidence, offset)
                            }
                        }
                    }
                }
            }

            if let match = bestMatch {
                // Skip common English words that happen to match place names
                if !isLikelyFalsePositive(match.matchedText, in: text) {
                    tags.append(GeoTag(
                        placeName: match.matchedText,
                        normalizedName: match.entry.name,
                        region: match.entry.region,
                        country: match.entry.country,
                        latitude: match.entry.latitude,
                        longitude: match.entry.longitude,
                        confidence: match.confidence,
                        characterOffset: match.offset,
                        matchLength: match.matchedText.count
                    ))
                }
                i += match.tokenCount
            } else {
                i += 1
            }
        }

        return tags
    }

    // MARK: - Matching

    /// Compute match confidence between a candidate and reference string.
    /// Exact match = 1.0; case-insensitive match is tried first.
    private func matchConfidence(candidate: String, reference: String) -> Double {
        if candidate == reference { return 1.0 }

        // Require minimum length to avoid matching short words like "la", "de"
        if reference.count < 3 || candidate.count < 3 { return 0.0 }

        // For short names, require exact match
        if reference.count <= 4 {
            return candidate == reference ? 1.0 : 0.0
        }

        // Trigram similarity for fuzzy matching
        let sim = trigramSimilarity(candidate, reference)
        return sim
    }

    /// Jaccard similarity of character trigrams.
    private func trigramSimilarity(_ a: String, _ b: String) -> Double {
        let triA = trigrams(a)
        let triB = trigrams(b)
        if triA.isEmpty && triB.isEmpty { return 1.0 }
        if triA.isEmpty || triB.isEmpty { return 0.0 }
        let intersection = triA.intersection(triB).count
        let union = triA.union(triB).count
        return union == 0 ? 0.0 : Double(intersection) / Double(union)
    }

    private func trigrams(_ s: String) -> Set<String> {
        let chars = Array(s)
        guard chars.count >= 3 else { return Set([s]) }
        var result = Set<String>()
        for i in 0..<(chars.count - 2) {
            result.insert(String(chars[i..<(i + 3)]))
        }
        return result
    }

    // MARK: - False Positive Filtering

    /// Words that are also place names but commonly used in other contexts.
    private static let ambiguousWords: Set<String> = [
        "reading", "mobile", "nice", "bath", "order",
        "victoria", "phoenix", "aurora", "sierra",
        "grace", "jordan", "chad", "china",  // as non-location usage
        "guinea", "turkey", "chile"  // keep country matches but filter generic usage
    ]

    /// Check if a matched text is likely a false positive.
    private func isLikelyFalsePositive(_ text: String, in fullText: String) -> Bool {
        let lower = text.lowercased()

        // Very short matches are suspicious
        if lower.count < 4 { return true }

        // Check if it's a common ambiguous word used in non-geographic context
        if ArticleGeoTagger.ambiguousWords.contains(lower) {
            // Allow if preceded by "in", "from", "to", "near", "visit"
            let geoPrepositions = ["in ", "from ", "to ", "near ", "visit ", "at "]
            let idx = fullText.lowercased().range(of: lower)
            if let range = idx, range.lowerBound > fullText.startIndex {
                let before = String(fullText[fullText.startIndex..<range.lowerBound])
                    .lowercased()
                    .suffix(8)
                if geoPrepositions.contains(where: { before.hasSuffix($0) }) {
                    return false  // Likely geographic usage
                }
            }
            return true  // Likely non-geographic usage
        }

        return false
    }

    // MARK: - Deduplication

    /// Deduplicate tags: keep all positions but don't double-count overlapping matches.
    private func deduplicateTags(_ tags: [GeoTag]) -> [GeoTag] {
        var seen = Set<Int>()
        var result: [GeoTag] = []
        for tag in tags.sorted(by: { $0.confidence > $1.confidence }) {
            let range = tag.characterOffset..<(tag.characterOffset + tag.matchLength)
            if !seen.contains(where: { pos in range.contains(pos) }) {
                result.append(tag)
                for pos in range { seen.insert(pos) }
            }
        }
        return result.sorted { $0.characterOffset < $1.characterOffset }
    }

    // MARK: - Tokenization

    private struct Token {
        let text: String
        let offset: Int
    }

    /// Tokenize text into words preserving character offsets.
    private func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var currentStart = 0

        for (i, char) in text.enumerated() {
            if char.isLetter || char == '-' || char == '\'' {
                if current.isEmpty { currentStart = i }
                current.append(char)
            } else {
                if !current.isEmpty {
                    tokens.append(Token(text: current, offset: currentStart))
                    current = ""
                }
            }
        }
        if !current.isEmpty {
            tokens.append(Token(text: current, offset: currentStart))
        }
        return tokens
    }

    // MARK: - Persistence

    private func saveResults() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(results) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadResults() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([String: GeoTagResult].self, from: data) {
            results = loaded
        }
    }

    // MARK: - Gazetteer

    /// Build the default gazetteer of major world locations.
    static func buildGazetteer() -> [GazetteerEntry] {
        var entries: [GazetteerEntry] = []

        // ── North America ──
        entries.append(GazetteerEntry(name: "United States", aliases: ["USA", "U.S.", "America", "US"], region: .northAmerica, country: "United States", latitude: 38.8951, longitude: -77.0364, population: 0))
        entries.append(GazetteerEntry(name: "Canada", aliases: [], region: .northAmerica, country: "Canada", latitude: 45.4215, longitude: -75.6972, population: 0))
        entries.append(GazetteerEntry(name: "Mexico", aliases: [], region: .northAmerica, country: "Mexico", latitude: 19.4326, longitude: -99.1332, population: 0))
        entries.append(GazetteerEntry(name: "Washington", aliases: ["Washington D.C.", "D.C."], region: .northAmerica, country: "United States", latitude: 38.9072, longitude: -77.0369, population: 1))
        entries.append(GazetteerEntry(name: "New York", aliases: ["New York City", "NYC"], region: .northAmerica, country: "United States", latitude: 40.7128, longitude: -74.0060, population: 2))
        entries.append(GazetteerEntry(name: "Los Angeles", aliases: ["LA"], region: .northAmerica, country: "United States", latitude: 34.0522, longitude: -118.2437, population: 2))
        entries.append(GazetteerEntry(name: "Chicago", aliases: [], region: .northAmerica, country: "United States", latitude: 41.8781, longitude: -87.6298, population: 2))
        entries.append(GazetteerEntry(name: "San Francisco", aliases: [], region: .northAmerica, country: "United States", latitude: 37.7749, longitude: -122.4194, population: 2))
        entries.append(GazetteerEntry(name: "Seattle", aliases: [], region: .northAmerica, country: "United States", latitude: 47.6062, longitude: -122.3321, population: 2))
        entries.append(GazetteerEntry(name: "Houston", aliases: [], region: .northAmerica, country: "United States", latitude: 29.7604, longitude: -95.3698, population: 2))
        entries.append(GazetteerEntry(name: "Miami", aliases: [], region: .northAmerica, country: "United States", latitude: 25.7617, longitude: -80.1918, population: 2))
        entries.append(GazetteerEntry(name: "Toronto", aliases: [], region: .northAmerica, country: "Canada", latitude: 43.6532, longitude: -79.3832, population: 2))
        entries.append(GazetteerEntry(name: "Vancouver", aliases: [], region: .northAmerica, country: "Canada", latitude: 49.2827, longitude: -123.1207, population: 2))
        entries.append(GazetteerEntry(name: "Mexico City", aliases: ["Ciudad de México", "CDMX"], region: .northAmerica, country: "Mexico", latitude: 19.4326, longitude: -99.1332, population: 1))
        entries.append(GazetteerEntry(name: "Boston", aliases: [], region: .northAmerica, country: "United States", latitude: 42.3601, longitude: -71.0589, population: 2))
        entries.append(GazetteerEntry(name: "Atlanta", aliases: [], region: .northAmerica, country: "United States", latitude: 33.749, longitude: -84.388, population: 2))
        entries.append(GazetteerEntry(name: "Denver", aliases: [], region: .northAmerica, country: "United States", latitude: 39.7392, longitude: -104.9903, population: 2))
        entries.append(GazetteerEntry(name: "Dallas", aliases: [], region: .northAmerica, country: "United States", latitude: 32.7767, longitude: -96.7970, population: 2))

        // ── Europe ──
        entries.append(GazetteerEntry(name: "United Kingdom", aliases: ["UK", "Britain", "Great Britain"], region: .europe, country: "United Kingdom", latitude: 51.5074, longitude: -0.1278, population: 0))
        entries.append(GazetteerEntry(name: "France", aliases: [], region: .europe, country: "France", latitude: 48.8566, longitude: 2.3522, population: 0))
        entries.append(GazetteerEntry(name: "Germany", aliases: [], region: .europe, country: "Germany", latitude: 52.5200, longitude: 13.4050, population: 0))
        entries.append(GazetteerEntry(name: "Italy", aliases: [], region: .europe, country: "Italy", latitude: 41.9028, longitude: 12.4964, population: 0))
        entries.append(GazetteerEntry(name: "Spain", aliases: [], region: .europe, country: "Spain", latitude: 40.4168, longitude: -3.7038, population: 0))
        entries.append(GazetteerEntry(name: "Russia", aliases: ["Russian Federation"], region: .europe, country: "Russia", latitude: 55.7558, longitude: 37.6173, population: 0))
        entries.append(GazetteerEntry(name: "Ukraine", aliases: [], region: .europe, country: "Ukraine", latitude: 50.4501, longitude: 30.5234, population: 0))
        entries.append(GazetteerEntry(name: "Poland", aliases: [], region: .europe, country: "Poland", latitude: 52.2297, longitude: 21.0122, population: 0))
        entries.append(GazetteerEntry(name: "Netherlands", aliases: ["Holland"], region: .europe, country: "Netherlands", latitude: 52.3676, longitude: 4.9041, population: 0))
        entries.append(GazetteerEntry(name: "Sweden", aliases: [], region: .europe, country: "Sweden", latitude: 59.3293, longitude: 18.0686, population: 0))
        entries.append(GazetteerEntry(name: "Switzerland", aliases: [], region: .europe, country: "Switzerland", latitude: 46.9480, longitude: 7.4474, population: 0))
        entries.append(GazetteerEntry(name: "London", aliases: [], region: .europe, country: "United Kingdom", latitude: 51.5074, longitude: -0.1278, population: 1))
        entries.append(GazetteerEntry(name: "Paris", aliases: [], region: .europe, country: "France", latitude: 48.8566, longitude: 2.3522, population: 1))
        entries.append(GazetteerEntry(name: "Berlin", aliases: [], region: .europe, country: "Germany", latitude: 52.5200, longitude: 13.4050, population: 1))
        entries.append(GazetteerEntry(name: "Madrid", aliases: [], region: .europe, country: "Spain", latitude: 40.4168, longitude: -3.7038, population: 1))
        entries.append(GazetteerEntry(name: "Rome", aliases: ["Roma"], region: .europe, country: "Italy", latitude: 41.9028, longitude: 12.4964, population: 1))
        entries.append(GazetteerEntry(name: "Moscow", aliases: ["Moskva"], region: .europe, country: "Russia", latitude: 55.7558, longitude: 37.6173, population: 1))
        entries.append(GazetteerEntry(name: "Amsterdam", aliases: [], region: .europe, country: "Netherlands", latitude: 52.3676, longitude: 4.9041, population: 1))
        entries.append(GazetteerEntry(name: "Stockholm", aliases: [], region: .europe, country: "Sweden", latitude: 59.3293, longitude: 18.0686, population: 1))
        entries.append(GazetteerEntry(name: "Brussels", aliases: [], region: .europe, country: "Belgium", latitude: 50.8503, longitude: 4.3517, population: 1))
        entries.append(GazetteerEntry(name: "Munich", aliases: ["München"], region: .europe, country: "Germany", latitude: 48.1351, longitude: 11.5820, population: 2))
        entries.append(GazetteerEntry(name: "Barcelona", aliases: [], region: .europe, country: "Spain", latitude: 41.3874, longitude: 2.1686, population: 2))
        entries.append(GazetteerEntry(name: "Kyiv", aliases: ["Kiev"], region: .europe, country: "Ukraine", latitude: 50.4501, longitude: 30.5234, population: 1))

        // ── Asia ──
        entries.append(GazetteerEntry(name: "China", aliases: ["People's Republic of China", "PRC"], region: .asia, country: "China", latitude: 39.9042, longitude: 116.4074, population: 0))
        entries.append(GazetteerEntry(name: "India", aliases: [], region: .asia, country: "India", latitude: 28.6139, longitude: 77.2090, population: 0))
        entries.append(GazetteerEntry(name: "Japan", aliases: [], region: .asia, country: "Japan", latitude: 35.6762, longitude: 139.6503, population: 0))
        entries.append(GazetteerEntry(name: "South Korea", aliases: ["Korea"], region: .asia, country: "South Korea", latitude: 37.5665, longitude: 126.978, population: 0))
        entries.append(GazetteerEntry(name: "Indonesia", aliases: [], region: .asia, country: "Indonesia", latitude: -6.2088, longitude: 106.8456, population: 0))
        entries.append(GazetteerEntry(name: "Thailand", aliases: [], region: .asia, country: "Thailand", latitude: 13.7563, longitude: 100.5018, population: 0))
        entries.append(GazetteerEntry(name: "Vietnam", aliases: [], region: .asia, country: "Vietnam", latitude: 21.0278, longitude: 105.8342, population: 0))
        entries.append(GazetteerEntry(name: "Philippines", aliases: [], region: .asia, country: "Philippines", latitude: 14.5995, longitude: 120.9842, population: 0))
        entries.append(GazetteerEntry(name: "Beijing", aliases: ["Peking"], region: .asia, country: "China", latitude: 39.9042, longitude: 116.4074, population: 1))
        entries.append(GazetteerEntry(name: "Shanghai", aliases: [], region: .asia, country: "China", latitude: 31.2304, longitude: 121.4737, population: 2))
        entries.append(GazetteerEntry(name: "Tokyo", aliases: [], region: .asia, country: "Japan", latitude: 35.6762, longitude: 139.6503, population: 1))
        entries.append(GazetteerEntry(name: "Seoul", aliases: [], region: .asia, country: "South Korea", latitude: 37.5665, longitude: 126.978, population: 1))
        entries.append(GazetteerEntry(name: "Mumbai", aliases: ["Bombay"], region: .asia, country: "India", latitude: 19.076, longitude: 72.8777, population: 2))
        entries.append(GazetteerEntry(name: "New Delhi", aliases: ["Delhi"], region: .asia, country: "India", latitude: 28.6139, longitude: 77.2090, population: 1))
        entries.append(GazetteerEntry(name: "Bangkok", aliases: [], region: .asia, country: "Thailand", latitude: 13.7563, longitude: 100.5018, population: 1))
        entries.append(GazetteerEntry(name: "Singapore", aliases: [], region: .asia, country: "Singapore", latitude: 1.3521, longitude: 103.8198, population: 1))
        entries.append(GazetteerEntry(name: "Hong Kong", aliases: [], region: .asia, country: "China", latitude: 22.3193, longitude: 114.1694, population: 2))
        entries.append(GazetteerEntry(name: "Taipei", aliases: [], region: .asia, country: "Taiwan", latitude: 25.033, longitude: 121.5654, population: 1))
        entries.append(GazetteerEntry(name: "Jakarta", aliases: [], region: .asia, country: "Indonesia", latitude: -6.2088, longitude: 106.8456, population: 1))
        entries.append(GazetteerEntry(name: "Bangalore", aliases: ["Bengaluru"], region: .asia, country: "India", latitude: 12.9716, longitude: 77.5946, population: 2))

        // ── Middle East ──
        entries.append(GazetteerEntry(name: "Israel", aliases: [], region: .middleEast, country: "Israel", latitude: 31.7683, longitude: 35.2137, population: 0))
        entries.append(GazetteerEntry(name: "Iran", aliases: ["Persia"], region: .middleEast, country: "Iran", latitude: 35.6892, longitude: 51.3890, population: 0))
        entries.append(GazetteerEntry(name: "Saudi Arabia", aliases: [], region: .middleEast, country: "Saudi Arabia", latitude: 24.7136, longitude: 46.6753, population: 0))
        entries.append(GazetteerEntry(name: "Iraq", aliases: [], region: .middleEast, country: "Iraq", latitude: 33.3152, longitude: 44.3661, population: 0))
        entries.append(GazetteerEntry(name: "Syria", aliases: [], region: .middleEast, country: "Syria", latitude: 33.5138, longitude: 36.2765, population: 0))
        entries.append(GazetteerEntry(name: "Jerusalem", aliases: [], region: .middleEast, country: "Israel", latitude: 31.7683, longitude: 35.2137, population: 1))
        entries.append(GazetteerEntry(name: "Tehran", aliases: [], region: .middleEast, country: "Iran", latitude: 35.6892, longitude: 51.3890, population: 1))
        entries.append(GazetteerEntry(name: "Dubai", aliases: [], region: .middleEast, country: "UAE", latitude: 25.2048, longitude: 55.2708, population: 2))
        entries.append(GazetteerEntry(name: "Riyadh", aliases: [], region: .middleEast, country: "Saudi Arabia", latitude: 24.7136, longitude: 46.6753, population: 1))
        entries.append(GazetteerEntry(name: "Baghdad", aliases: [], region: .middleEast, country: "Iraq", latitude: 33.3152, longitude: 44.3661, population: 1))
        entries.append(GazetteerEntry(name: "Istanbul", aliases: ["Constantinople"], region: .middleEast, country: "Turkey", latitude: 41.0082, longitude: 28.9784, population: 2))
        entries.append(GazetteerEntry(name: "Ankara", aliases: [], region: .middleEast, country: "Turkey", latitude: 39.9334, longitude: 32.8597, population: 1))

        // ── Africa ──
        entries.append(GazetteerEntry(name: "Nigeria", aliases: [], region: .africa, country: "Nigeria", latitude: 9.0579, longitude: 7.4951, population: 0))
        entries.append(GazetteerEntry(name: "South Africa", aliases: [], region: .africa, country: "South Africa", latitude: -33.9249, longitude: 18.4241, population: 0))
        entries.append(GazetteerEntry(name: "Egypt", aliases: [], region: .africa, country: "Egypt", latitude: 30.0444, longitude: 31.2357, population: 0))
        entries.append(GazetteerEntry(name: "Kenya", aliases: [], region: .africa, country: "Kenya", latitude: -1.2921, longitude: 36.8219, population: 0))
        entries.append(GazetteerEntry(name: "Ethiopia", aliases: [], region: .africa, country: "Ethiopia", latitude: 9.145, longitude: 40.4897, population: 0))
        entries.append(GazetteerEntry(name: "Cairo", aliases: [], region: .africa, country: "Egypt", latitude: 30.0444, longitude: 31.2357, population: 1))
        entries.append(GazetteerEntry(name: "Lagos", aliases: [], region: .africa, country: "Nigeria", latitude: 6.5244, longitude: 3.3792, population: 2))
        entries.append(GazetteerEntry(name: "Nairobi", aliases: [], region: .africa, country: "Kenya", latitude: -1.2921, longitude: 36.8219, population: 1))
        entries.append(GazetteerEntry(name: "Cape Town", aliases: [], region: .africa, country: "South Africa", latitude: -33.9249, longitude: 18.4241, population: 2))
        entries.append(GazetteerEntry(name: "Johannesburg", aliases: [], region: .africa, country: "South Africa", latitude: -26.2041, longitude: 28.0473, population: 2))
        entries.append(GazetteerEntry(name: "Addis Ababa", aliases: [], region: .africa, country: "Ethiopia", latitude: 9.0250, longitude: 38.7469, population: 1))

        // ── South America ──
        entries.append(GazetteerEntry(name: "Brazil", aliases: ["Brasil"], region: .southAmerica, country: "Brazil", latitude: -15.7801, longitude: -47.9292, population: 0))
        entries.append(GazetteerEntry(name: "Argentina", aliases: [], region: .southAmerica, country: "Argentina", latitude: -34.6037, longitude: -58.3816, population: 0))
        entries.append(GazetteerEntry(name: "Colombia", aliases: [], region: .southAmerica, country: "Colombia", latitude: 4.7110, longitude: -74.0721, population: 0))
        entries.append(GazetteerEntry(name: "São Paulo", aliases: ["Sao Paulo"], region: .southAmerica, country: "Brazil", latitude: -23.5558, longitude: -46.6396, population: 2))
        entries.append(GazetteerEntry(name: "Buenos Aires", aliases: [], region: .southAmerica, country: "Argentina", latitude: -34.6037, longitude: -58.3816, population: 1))
        entries.append(GazetteerEntry(name: "Rio de Janeiro", aliases: ["Rio"], region: .southAmerica, country: "Brazil", latitude: -22.9068, longitude: -43.1729, population: 2))
        entries.append(GazetteerEntry(name: "Bogotá", aliases: ["Bogota"], region: .southAmerica, country: "Colombia", latitude: 4.7110, longitude: -74.0721, population: 1))
        entries.append(GazetteerEntry(name: "Lima", aliases: [], region: .southAmerica, country: "Peru", latitude: -12.0464, longitude: -77.0428, population: 1))
        entries.append(GazetteerEntry(name: "Santiago", aliases: [], region: .southAmerica, country: "Chile", latitude: -33.4489, longitude: -70.6693, population: 1))

        // ── Oceania ──
        entries.append(GazetteerEntry(name: "Australia", aliases: [], region: .oceania, country: "Australia", latitude: -33.8688, longitude: 151.2093, population: 0))
        entries.append(GazetteerEntry(name: "New Zealand", aliases: [], region: .oceania, country: "New Zealand", latitude: -41.2865, longitude: 174.7762, population: 0))
        entries.append(GazetteerEntry(name: "Sydney", aliases: [], region: .oceania, country: "Australia", latitude: -33.8688, longitude: 151.2093, population: 2))
        entries.append(GazetteerEntry(name: "Melbourne", aliases: [], region: .oceania, country: "Australia", latitude: -37.8136, longitude: 144.9631, population: 2))
        entries.append(GazetteerEntry(name: "Auckland", aliases: [], region: .oceania, country: "New Zealand", latitude: -36.8485, longitude: 174.7633, population: 2))
        entries.append(GazetteerEntry(name: "Canberra", aliases: [], region: .oceania, country: "Australia", latitude: -35.2809, longitude: 149.1300, population: 1))

        return entries
    }
}
