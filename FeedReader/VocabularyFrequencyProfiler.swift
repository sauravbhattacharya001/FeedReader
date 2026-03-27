//
//  VocabularyFrequencyProfiler.swift
//  FeedReader
//
//  Analyzes article text using word frequency bands to profile vocabulary
//  richness and difficulty. Unlike readability formulas (Flesch, etc.) which
//  focus on sentence structure, this uses corpus-based word frequency ranks
//  to identify rare/advanced vocabulary.
//
//  Features:
//  - Classify words into frequency bands (top 1K, 2K, 3K, 5K, 10K, rare)
//  - Calculate vocabulary richness score (type-token ratio + band distribution)
//  - Identify advanced/rare words for vocabulary building
//  - Assign CEFR-like difficulty level (A1–C2) based on vocab profile
//  - Track vocabulary exposure over time
//  - Export vocabulary profile as JSON
//
//  Persistence: UserDefaults via Codable.
//

import Foundation

// MARK: - Frequency Band

/// Represents a word frequency band based on corpus rank.
enum FrequencyBand: String, Codable, CaseIterable, Comparable {
    case top500    = "Top 500"
    case top1000   = "Top 1K"
    case top2000   = "Top 2K"
    case top3000   = "Top 3K"
    case top5000   = "Top 5K"
    case top10000  = "Top 10K"
    case rare      = "Rare (10K+)"

    var sortOrder: Int {
        switch self {
        case .top500:   return 0
        case .top1000:  return 1
        case .top2000:  return 2
        case .top3000:  return 3
        case .top5000:  return 4
        case .top10000: return 5
        case .rare:     return 6
        }
    }

    static func < (lhs: FrequencyBand, rhs: FrequencyBand) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

// MARK: - CEFR Level

/// Common European Framework of Reference levels for language proficiency.
enum CEFRLevel: String, Codable, CaseIterable, Comparable {
    case a1 = "A1"
    case a2 = "A2"
    case b1 = "B1"
    case b2 = "B2"
    case c1 = "C1"
    case c2 = "C2"

    var description: String {
        switch self {
        case .a1: return "Beginner"
        case .a2: return "Elementary"
        case .b1: return "Intermediate"
        case .b2: return "Upper Intermediate"
        case .c1: return "Advanced"
        case .c2: return "Proficiency"
        }
    }

    var sortOrder: Int {
        switch self {
        case .a1: return 0
        case .a2: return 1
        case .b1: return 2
        case .b2: return 3
        case .c1: return 4
        case .c2: return 5
        }
    }

    static func < (lhs: CEFRLevel, rhs: CEFRLevel) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

// MARK: - Analysis Result

/// Result of vocabulary frequency analysis on an article.
struct VocabularyProfile: Codable {
    /// Article identifier (URL or title hash).
    let articleId: String
    /// Total tokens (all words including repeats).
    let totalTokens: Int
    /// Unique word types (distinct words, lowercased).
    let uniqueTypes: Int
    /// Type-Token Ratio (lexical diversity).
    let typeTokenRatio: Double
    /// Distribution of words across frequency bands.
    let bandDistribution: [String: Int]
    /// Percentage of words in each band.
    let bandPercentages: [String: Double]
    /// Estimated CEFR difficulty level.
    let cefrLevel: CEFRLevel
    /// Vocabulary richness score (0–100).
    let richnessScore: Double
    /// List of rare/advanced words found.
    let rareWords: [String]
    /// List of academic words found.
    let academicWords: [String]
    /// Timestamp of analysis.
    let analyzedAt: Date
}

/// Tracks vocabulary exposure over time.
struct VocabularyExposure: Codable {
    /// Words the user has been exposed to, with encounter count.
    var wordEncounters: [String: Int]
    /// Total articles profiled.
    var articlesProfiled: Int
    /// Total unique words encountered across all articles.
    var totalUniqueWords: Int
    /// Last updated timestamp.
    var lastUpdated: Date
}

// MARK: - Vocabulary Frequency Profiler

/// Profiles article vocabulary using word frequency ranks.
final class VocabularyFrequencyProfiler {

    // MARK: - Singleton

    static let shared = VocabularyFrequencyProfiler()

    // MARK: - Storage Keys

    private let exposureKey = "VocabularyFrequencyProfiler.exposure"
    private let historyKey  = "VocabularyFrequencyProfiler.history"

    // MARK: - Core Word Lists

    /// Top 500 most frequent English words (determiners, prepositions, common verbs, etc.).
    private let top500: Set<String> = [
        "the", "be", "to", "of", "and", "a", "in", "that", "have", "i",
        "it", "for", "not", "on", "with", "he", "as", "you", "do", "at",
        "this", "but", "his", "by", "from", "they", "we", "say", "her", "she",
        "or", "an", "will", "my", "one", "all", "would", "there", "their", "what",
        "so", "up", "out", "if", "about", "who", "get", "which", "go", "me",
        "when", "make", "can", "like", "time", "no", "just", "him", "know", "take",
        "people", "into", "year", "your", "good", "some", "could", "them", "see", "other",
        "than", "then", "now", "look", "only", "come", "its", "over", "think", "also",
        "back", "after", "use", "two", "how", "our", "work", "first", "well", "way",
        "even", "new", "want", "because", "any", "these", "give", "day", "most", "us",
        "been", "has", "had", "are", "is", "was", "were", "did", "does", "am",
        "being", "having", "got", "made", "said", "went", "going", "doing", "taken",
        "more", "very", "much", "too", "here", "still", "own", "such", "may", "should",
        "those", "never", "where", "while", "found", "each", "right", "long", "both",
        "through", "down", "between", "before", "same", "another", "must", "might",
        "great", "old", "off", "high", "last", "every", "under", "part", "keep",
        "let", "since", "many", "put", "tell", "place", "around", "help", "start",
        "show", "hand", "run", "again", "turn", "call", "set", "small", "end",
        "point", "home", "head", "left", "three", "number", "world", "life", "thing",
        "need", "house", "big", "group", "begin", "seem", "country", "might", "state",
        "move", "live", "find", "stand", "own", "try", "ask", "men", "change",
        "play", "read", "case", "open", "close", "hold", "learn", "lead", "understand"
    ]

    /// Additional words for the top 1000 band.
    private let top1000Extra: Set<String> = [
        "against", "early", "enough", "important", "level", "system", "program",
        "question", "during", "without", "business", "able", "problem", "line",
        "become", "power", "family", "city", "next", "face", "different", "possible",
        "money", "young", "water", "real", "until", "often", "side", "large",
        "company", "development", "social", "along", "public", "several", "already",
        "always", "believe", "least", "area", "school", "office", "always", "human",
        "local", "story", "child", "children", "political", "national", "member",
        "order", "provide", "late", "report", "free", "service", "market", "force",
        "certain", "body", "morning", "result", "fact", "sometimes", "sure", "idea",
        "nothing", "best", "half", "less", "form", "full", "leave", "view",
        "information", "support", "action", "course", "room", "night", "name",
        "second", "per", "however", "experience", "plan", "among", "control",
        "community", "process", "position", "reason", "together", "follow",
        "word", "common", "bring", "bit", "include", "continue", "ever", "increase",
        "care", "effect", "party", "clear", "kind", "pay", "almost", "interest",
        "given", "special", "yet", "produce", "above", "land", "either", "quite",
        "type", "age", "game", "law", "rather", "happen", "student", "history"
    ]

    /// Academic Word List (AWL) — common in academic/formal writing.
    private let academicWordList: Set<String> = [
        "analyze", "approach", "area", "assess", "assume", "authority", "available",
        "benefit", "concept", "consist", "constitute", "context", "contract", "create",
        "data", "define", "derive", "distribute", "economy", "environment", "establish",
        "estimate", "evident", "export", "factor", "finance", "formula", "function",
        "identify", "income", "indicate", "individual", "interpret", "involve", "issue",
        "labour", "legal", "legislate", "major", "method", "occur", "percent", "period",
        "policy", "principle", "proceed", "process", "require", "research", "respond",
        "role", "section", "sector", "significant", "similar", "source", "specific",
        "structure", "theory", "variable", "achieve", "acquire", "administrate",
        "affect", "appropriate", "aspect", "assist", "category", "chapter", "commission",
        "community", "complex", "compute", "conclude", "conduct", "consequence",
        "construct", "consume", "credit", "culture", "design", "distinct", "element",
        "equate", "evaluate", "feature", "final", "focus", "impact", "injure",
        "institute", "invest", "item", "journal", "maintain", "normal", "obtain",
        "participate", "perceive", "positive", "potential", "previous", "primary",
        "purchase", "range", "region", "regulate", "relevant", "reside", "resource",
        "restrict", "secure", "seek", "select", "site", "strategy", "survey",
        "text", "tradition", "transfer", "adequate", "annual", "apparent", "compensate",
        "component", "consent", "considerable", "constant", "constrain", "contribute",
        "convention", "coordinate", "core", "corporate", "correspond", "criteria",
        "deduce", "demonstrate", "document", "dominate", "emphasis", "ensure",
        "exclude", "framework", "fund", "illustrate", "immigrate", "imply", "initial",
        "instance", "interact", "justify", "layer", "link", "locate", "maximize",
        "minor", "negate", "outcome", "partner", "philosophy", "physical", "proportion",
        "publish", "react", "regime", "resolve", "scheme", "sequence", "shift",
        "specify", "sufficient", "task", "technical", "technique", "technology",
        "valid", "volume", "abstract", "acknowledge", "aggregate", "allocate",
        "analogy", "anticipate", "arbitrary", "automate", "bias", "capacity",
        "cease", "coherent", "coincide", "commence", "compatible", "complement",
        "comprehensive", "comprise", "confirm", "contemporary", "contradict",
        "crucial", "currency", "detect", "deviate", "differentiate", "diminish",
        "discrete", "displace", "dynamic", "eliminate", "empirical", "equivalent",
        "erode", "ethic", "explicit", "exploit", "extract", "fluctuate",
        "fundamental", "generate", "globe", "guarantee", "hierarchy", "hypothesis",
        "identical", "ideology", "incentive", "incidence", "incorporate", "index",
        "induce", "inevitable", "infrastructure", "inherent", "inhibit", "innovate",
        "integrity", "intermediate", "internal", "intervene", "isolate", "liberal",
        "licence", "likewise", "logical", "margin", "mature", "mediate", "medium",
        "migrate", "military", "minimize", "ministry", "modify", "monitor",
        "mutual", "nonetheless", "notwithstanding", "nucleus", "objective", "orient",
        "paradigm", "paragraph", "passive", "phenomenon", "pose", "practitioner",
        "precede", "predominant", "presume", "prohibit", "prospect", "protocol",
        "psychology", "publication", "pursue", "qualitative", "radical", "random",
        "reinforce", "reluctance", "revenue", "rigid", "scenario", "scope",
        "simulate", "sole", "somewhat", "submit", "subordinate", "subsequent",
        "substitute", "successor", "supplement", "suspend", "sustain", "symbol",
        "target", "terminate", "theme", "thereby", "thesis", "transform",
        "transmit", "trigger", "ultimate", "undergo", "undertake", "uniform",
        "unify", "utilize", "verify", "via", "violate", "virtual", "visual",
        "welfare", "whereas", "widespread"
    ]

    // MARK: - Init

    private init() {}

    // MARK: - Public API

    /// Analyze article text and return a vocabulary profile.
    /// - Parameters:
    ///   - text: The article body text.
    ///   - articleId: Unique identifier for the article.
    /// - Returns: A `VocabularyProfile` with frequency band analysis.
    func analyze(text: String, articleId: String) -> VocabularyProfile {
        let tokens = tokenize(text)
        let types = Set(tokens)

        guard !tokens.isEmpty else {
            return VocabularyProfile(
                articleId: articleId,
                totalTokens: 0,
                uniqueTypes: 0,
                typeTokenRatio: 0,
                bandDistribution: [:],
                bandPercentages: [:],
                cefrLevel: .a1,
                richnessScore: 0,
                rareWords: [],
                academicWords: [],
                analyzedAt: Date()
            )
        }

        // Classify each unique word into frequency bands
        var bandCounts: [FrequencyBand: Int] = [:]
        for band in FrequencyBand.allCases {
            bandCounts[band] = 0
        }

        var foundRare: [String] = []
        var foundAcademic: [String] = []

        for word in types {
            let band = classifyWord(word)
            bandCounts[band, default: 0] += 1

            if band == .rare || band == .top10000 {
                foundRare.append(word)
            }
            if academicWordList.contains(word) {
                foundAcademic.append(word)
            }
        }

        let totalTypes = Double(types.count)
        let ttr = totalTypes / Double(tokens.count)

        // Build distribution and percentage dictionaries
        var distribution: [String: Int] = [:]
        var percentages: [String: Double] = [:]
        for (band, count) in bandCounts {
            distribution[band.rawValue] = count
            percentages[band.rawValue] = (Double(count) / totalTypes) * 100.0
        }

        // Calculate richness score (0–100)
        let richness = calculateRichnessScore(
            ttr: ttr,
            rarePercent: percentages[FrequencyBand.rare.rawValue] ?? 0,
            top10kPercent: percentages[FrequencyBand.top10000.rawValue] ?? 0,
            academicCount: foundAcademic.count,
            totalTypes: types.count
        )

        // Estimate CEFR level
        let cefr = estimateCEFR(
            rarePercent: percentages[FrequencyBand.rare.rawValue] ?? 0,
            top5kPercent: percentages[FrequencyBand.top5000.rawValue] ?? 0,
            top10kPercent: percentages[FrequencyBand.top10000.rawValue] ?? 0,
            academicCount: foundAcademic.count,
            totalTypes: types.count
        )

        return VocabularyProfile(
            articleId: articleId,
            totalTokens: tokens.count,
            uniqueTypes: types.count,
            typeTokenRatio: ttr,
            bandDistribution: distribution,
            bandPercentages: percentages,
            cefrLevel: cefr,
            richnessScore: richness,
            rareWords: foundRare.sorted(),
            academicWords: foundAcademic.sorted(),
            analyzedAt: Date()
        )
    }

    /// Record vocabulary exposure from an analyzed article.
    func recordExposure(from profile: VocabularyProfile) {
        var exposure = loadExposure()
        for word in profile.rareWords + profile.academicWords {
            exposure.wordEncounters[word, default: 0] += 1
        }
        exposure.articlesProfiled += 1
        exposure.totalUniqueWords = exposure.wordEncounters.count
        exposure.lastUpdated = Date()
        saveExposure(exposure)
    }

    /// Get current vocabulary exposure stats.
    func getExposure() -> VocabularyExposure {
        return loadExposure()
    }

    /// Get the most frequently encountered advanced words.
    /// - Parameter limit: Maximum number of words to return.
    func topEncounteredWords(limit: Int = 20) -> [(word: String, count: Int)] {
        let exposure = loadExposure()
        return exposure.wordEncounters
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { (word: $0.key, count: $0.value) }
    }

    /// Get words encountered only once (potential vocabulary gaps).
    func singleEncounterWords() -> [String] {
        let exposure = loadExposure()
        return exposure.wordEncounters
            .filter { $0.value == 1 }
            .map { $0.key }
            .sorted()
    }

    /// Export a vocabulary profile as JSON data.
    func exportProfileJSON(_ profile: VocabularyProfile) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(profile)
    }

    /// Format profile as a human-readable summary string.
    func formatSummary(_ profile: VocabularyProfile) -> String {
        var lines: [String] = []
        lines.append("📚 Vocabulary Profile")
        lines.append("═══════════════════════════════════")
        lines.append("Total words:    \(profile.totalTokens)")
        lines.append("Unique words:   \(profile.uniqueTypes)")
        lines.append("Lexical diversity (TTR): \(String(format: "%.2f", profile.typeTokenRatio))")
        lines.append("")
        lines.append("CEFR Level:     \(profile.cefrLevel.rawValue) (\(profile.cefrLevel.description))")
        lines.append("Richness Score: \(String(format: "%.1f", profile.richnessScore))/100")
        lines.append("")
        lines.append("Frequency Band Distribution:")

        for band in FrequencyBand.allCases {
            let count = profile.bandDistribution[band.rawValue] ?? 0
            let pct = profile.bandPercentages[band.rawValue] ?? 0
            let bar = String(repeating: "█", count: Int(pct / 5))
            lines.append("  \(band.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0)) \(String(format: "%3d", count)) (\(String(format: "%5.1f%%", pct))) \(bar)")
        }

        if !profile.academicWords.isEmpty {
            lines.append("")
            lines.append("Academic words (\(profile.academicWords.count)):")
            let joined = profile.academicWords.prefix(15).joined(separator: ", ")
            lines.append("  \(joined)\(profile.academicWords.count > 15 ? "..." : "")")
        }

        if !profile.rareWords.isEmpty {
            lines.append("")
            lines.append("Rare/advanced words (\(profile.rareWords.count)):")
            let joined = profile.rareWords.prefix(15).joined(separator: ", ")
            lines.append("  \(joined)\(profile.rareWords.count > 15 ? "..." : "")")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private Helpers

    /// Tokenize text into lowercased words, stripping punctuation.
    private func tokenize(_ text: String) -> [String] {
        let cleaned = text.lowercased()
        let allowed = CharacterSet.letters.union(.whitespaces)
        let filtered = cleaned.unicodeScalars.map { allowed.contains($0) ? Character($0) : Character(" ") }
        let words = String(filtered)
            .split(separator: " ")
            .map { String($0) }
            .filter { $0.count >= 2 } // skip single-char tokens
        return words
    }

    /// Classify a word into a frequency band.
    private func classifyWord(_ word: String) -> FrequencyBand {
        if top500.contains(word) { return .top500 }
        if top1000Extra.contains(word) { return .top1000 }

        // Heuristic: common words not in our lists but short and familiar
        // Use word length + common suffix patterns as proxy for frequency
        let len = word.count

        if len <= 4 && isCommonPattern(word) { return .top2000 }
        if len <= 5 && hasCommonSuffix(word, ["ed", "er", "ly", "ing", "es"]) { return .top3000 }
        if len <= 7 && hasCommonSuffix(word, ["tion", "ment", "ness", "able", "ible"]) { return .top5000 }
        if len <= 9 && hasCommonSuffix(word, ["ology", "ical", "eous", "ious"]) { return .top10000 }
        if len > 9 { return .rare }

        // Default mid-range
        return .top5000
    }

    private func isCommonPattern(_ word: String) -> Bool {
        // Very short words are usually common
        let commonShort: Set<String> = [
            "able", "air", "away", "bad", "boy", "car", "cut", "dark", "dead",
            "deal", "deep", "door", "draw", "drop", "eat", "eye", "fall", "far",
            "fast", "fear", "feel", "fill", "fire", "five", "fix", "fly", "food",
            "foot", "four", "girl", "god", "gold", "gone", "grow", "hair", "hang",
            "hard", "hat", "hear", "heat", "hit", "hot", "hour", "idea", "job",
            "join", "joy", "kill", "king", "knew", "lack", "laid", "lay", "lose",
            "lost", "lot", "love", "low", "mark", "mind", "miss", "moon", "move",
            "near", "news", "nice", "note", "pain", "past", "pick", "plan", "poor",
            "pull", "push", "rain", "rate", "rest", "rich", "rise", "road", "rock",
            "rule", "safe", "save", "sell", "send", "sign", "sing", "sit", "skin",
            "son", "soon", "sort", "soul", "step", "stop", "sure", "talk", "team",
            "test", "top", "tree", "true", "wait", "wake", "walk", "wall", "warm",
            "wash", "watch", "wear", "week", "wife", "wild", "win", "wind", "wood",
            "wore", "yeah", "yes"
        ]
        return commonShort.contains(word)
    }

    private func hasCommonSuffix(_ word: String, _ suffixes: [String]) -> Bool {
        for suffix in suffixes {
            if word.hasSuffix(suffix) { return true }
        }
        return false
    }

    /// Calculate vocabulary richness score (0–100).
    private func calculateRichnessScore(
        ttr: Double,
        rarePercent: Double,
        top10kPercent: Double,
        academicCount: Int,
        totalTypes: Int
    ) -> Double {
        guard totalTypes > 0 else { return 0 }

        // Components:
        // 1. TTR contribution (0–30): higher diversity = richer
        let ttrScore = min(ttr * 100, 30.0)

        // 2. Rare word contribution (0–30): more rare words = richer
        let rareScore = min(rarePercent * 1.5, 30.0)

        // 3. Top 10K contribution (0–20): words beyond top 5K
        let advancedScore = min(top10kPercent * 1.0, 20.0)

        // 4. Academic vocabulary (0–20): academic register presence
        let academicRatio = Double(academicCount) / Double(totalTypes) * 100
        let academicScore = min(academicRatio * 2.0, 20.0)

        return min(ttrScore + rareScore + advancedScore + academicScore, 100.0)
    }

    /// Estimate CEFR level from vocabulary profile.
    private func estimateCEFR(
        rarePercent: Double,
        top5kPercent: Double,
        top10kPercent: Double,
        academicCount: Int,
        totalTypes: Int
    ) -> CEFRLevel {
        let advancedPercent = rarePercent + top10kPercent + top5kPercent
        let academicRatio = totalTypes > 0 ? Double(academicCount) / Double(totalTypes) * 100 : 0

        // Thresholds based on vocabulary complexity
        if advancedPercent > 40 || academicRatio > 15 { return .c2 }
        if advancedPercent > 30 || academicRatio > 10 { return .c1 }
        if advancedPercent > 20 || academicRatio > 7  { return .b2 }
        if advancedPercent > 12 || academicRatio > 4  { return .b1 }
        if advancedPercent > 5                         { return .a2 }
        return .a1
    }

    // MARK: - Persistence

    private func loadExposure() -> VocabularyExposure {
        guard let data = UserDefaults.standard.data(forKey: exposureKey),
              let exposure = try? JSONDecoder().decode(VocabularyExposure.self, from: data) else {
            return VocabularyExposure(
                wordEncounters: [:],
                articlesProfiled: 0,
                totalUniqueWords: 0,
                lastUpdated: Date()
            )
        }
        return exposure
    }

    private func saveExposure(_ exposure: VocabularyExposure) {
        if let data = try? JSONEncoder().encode(exposure) {
            UserDefaults.standard.set(data, forKey: exposureKey)
        }
    }
}
