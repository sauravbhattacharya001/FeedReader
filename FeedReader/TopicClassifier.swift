//
//  TopicClassifier.swift
//  FeedReader
//
//  Automatic article topic classification using keyword-based NLP.
//  Classifies stories into broad topics (Technology, Science, Politics,
//  Business, Health, Sports, Entertainment, Environment, Education,
//  Lifestyle) using weighted keyword matching against curated topic
//  vocabularies. Supports multi-label classification, confidence scores,
//  per-feed topic profiles, and trending topic detection.
//
//  Unlike ArticleTagManager (manual user tags), TopicClassifier works
//  automatically with zero user input — every article gets classified
//  on arrival. Integrates with TextAnalyzer for consistent tokenization.
//

import Foundation

// MARK: - Topic Definitions

/// Broad article topic categories.
enum ArticleTopic: String, Codable, CaseIterable, CustomStringConvertible {
    case technology   = "Technology"
    case science      = "Science"
    case politics     = "Politics"
    case business     = "Business"
    case health       = "Health"
    case sports       = "Sports"
    case entertainment = "Entertainment"
    case environment  = "Environment"
    case education    = "Education"
    case lifestyle    = "Lifestyle"
    case world        = "World"
    case uncategorized = "Uncategorized"

    var description: String { rawValue }

    /// Emoji shorthand for UI display.
    var emoji: String {
        switch self {
        case .technology:    return "💻"
        case .science:       return "🔬"
        case .politics:      return "🏛️"
        case .business:      return "📈"
        case .health:        return "🏥"
        case .sports:        return "⚽"
        case .entertainment: return "🎬"
        case .environment:   return "🌍"
        case .education:     return "📚"
        case .lifestyle:     return "🏠"
        case .world:         return "🌐"
        case .uncategorized: return "📄"
        }
    }
}

// MARK: - Classification Result

/// Result of classifying a single article.
struct TopicClassification: Codable {
    /// Primary (highest-confidence) topic.
    let primary: ArticleTopic
    /// All topics with confidence scores above the threshold.
    let topics: [TopicScore]
    /// Number of keyword matches that drove the classification.
    let matchCount: Int
    /// Overall classification confidence (0.0–1.0).
    let confidence: Double

    /// Whether the article is multi-topic (2+ topics above threshold).
    var isMultiTopic: Bool { topics.count > 1 }

    /// Display label: "Technology (92%)" or "Technology / Science"
    var label: String {
        if topics.count <= 1 {
            return "\(primary.emoji) \(primary.rawValue)"
        }
        return topics.prefix(2)
            .map { "\($0.topic.emoji) \($0.topic.rawValue)" }
            .joined(separator: " / ")
    }
}

/// A topic with its confidence score.
struct TopicScore: Codable, Comparable {
    let topic: ArticleTopic
    let score: Double

    static func < (lhs: TopicScore, rhs: TopicScore) -> Bool {
        return lhs.score < rhs.score
    }
}

// MARK: - Feed Topic Profile

/// Aggregated topic distribution for a feed.
struct FeedTopicProfile: Codable {
    let feedName: String
    /// Number of articles analyzed.
    let articleCount: Int
    /// Topic distribution: topic → fraction of articles (0.0–1.0).
    let distribution: [ArticleTopic: Double]
    /// Dominant topic (highest fraction).
    let dominantTopic: ArticleTopic
    /// Topic diversity score (Shannon entropy / max entropy, 0.0–1.0).
    let diversity: Double

    /// Human-readable summary.
    var summary: String {
        let sorted = distribution.sorted { $0.value > $1.value }
        let top3 = sorted.prefix(3)
            .map { "\($0.key.emoji) \($0.key.rawValue): \(Int($0.value * 100))%" }
            .joined(separator: ", ")
        return "\(feedName) (\(articleCount) articles): \(top3)"
    }
}

// MARK: - Trending Topic

/// A topic that has seen increased coverage recently.
struct TrendingTopic: Codable {
    let topic: ArticleTopic
    /// Recent frequency (articles in current window).
    let recentCount: Int
    /// Baseline frequency (articles in reference window).
    let baselineCount: Int
    /// Trend strength: recentCount / baselineCount ratio.
    let trendStrength: Double
    /// Direction: up, down, or stable.
    let direction: TrendDirection

    enum TrendDirection: String, Codable {
        case rising  = "Rising"
        case falling = "Falling"
        case stable  = "Stable"
    }
}

// MARK: - Topic Classifier

/// Automatic topic classifier for RSS articles.
///
/// Uses a curated keyword vocabulary per topic, with weighted matching.
/// "Core" keywords (highly specific to a topic) receive 2x weight;
/// "signal" keywords (common but indicative) receive 1x. The classifier
/// tokenizes the article title + body using `TextAnalyzer`, counts
/// weighted keyword hits per topic, normalizes, and returns all topics
/// above a configurable confidence threshold.
///
/// Usage:
/// ```swift
/// let result = TopicClassifier.shared.classify(story)
/// print(result.primary)     // .technology
/// print(result.confidence)  // 0.85
/// print(result.label)       // "💻 Technology"
/// ```
class TopicClassifier {

    // MARK: - Singleton

    static let shared = TopicClassifier()

    // MARK: - Configuration

    /// Minimum confidence score for a topic to be included in results.
    var confidenceThreshold: Double = 0.15

    /// Minimum number of keyword matches required for classification.
    /// Below this, the article is marked as "Uncategorized".
    var minimumMatches: Int = 2

    // MARK: - Topic Vocabularies

    /// Topic keyword dictionaries. Each topic has "core" (2x weight) and
    /// "signal" (1x weight) keywords. Core keywords are highly specific
    /// (e.g., "algorithm" → Technology); signal keywords are common but
    /// directional (e.g., "digital" could be Tech or Business).
    private struct TopicVocabulary {
        let core: Set<String>    // 2x weight
        let signal: Set<String>  // 1x weight
    }

    private let vocabularies: [ArticleTopic: TopicVocabulary] = [
        .technology: TopicVocabulary(
            core: [
                "algorithm", "software", "hardware", "programming", "cybersecurity",
                "blockchain", "cryptocurrency", "bitcoin", "ethereum", "startup",
                "silicon", "computing", "processor", "gpu", "cpu", "server",
                "database", "cloud", "saas", "devops", "kubernetes", "docker",
                "api", "frontend", "backend", "fullstack", "microservices",
                "machine", "neural", "deeplearning", "chatbot", "robotics",
                "automation", "linux", "windows", "macos", "android", "ios",
                "smartphone", "gadget", "wearable", "drone", "metaverse",
                "virtual", "augmented", "quantum", "semiconductor", "chip",
                "5g", "wifi", "broadband", "fiber", "optic", "bandwidth",
                "encryption", "malware", "ransomware", "phishing", "firewall",
                "vulnerability", "exploit", "patch", "update",
            ],
            signal: [
                "tech", "digital", "internet", "online", "web", "app", "data",
                "code", "developer", "engineer", "platform", "device",
                "artificial", "intelligence", "innovation", "cyber",
                "network", "computer", "laptop", "tablet", "mobile",
            ]
        ),
        .science: TopicVocabulary(
            core: [
                "research", "study", "experiment", "hypothesis", "theory",
                "physics", "chemistry", "biology", "astronomy", "geology",
                "neuroscience", "genetics", "genome", "dna", "rna", "protein",
                "molecule", "atom", "particle", "photon", "neutron", "proton",
                "telescope", "microscope", "laboratory", "peer", "journal",
                "published", "findings", "discovery", "breakthrough",
                "species", "evolution", "fossil", "dinosaur", "organism",
                "bacteria", "virus", "cell", "mutation", "gene",
                "mars", "moon", "asteroid", "comet", "galaxy", "nebula",
                "exoplanet", "spacecraft", "nasa", "esa", "spacex",
                "cern", "superconductor", "fusion", "fission",
            ],
            signal: [
                "scientist", "researcher", "professor", "university",
                "academic", "evidence", "data", "analysis", "observation",
                "phenomenon", "equation", "mathematical", "statistical",
            ]
        ),
        .politics: TopicVocabulary(
            core: [
                "election", "vote", "voter", "ballot", "campaign", "candidate",
                "democrat", "republican", "congress", "senate", "parliament",
                "legislation", "lawmaker", "politician", "governor", "mayor",
                "president", "minister", "cabinet", "diplomatic", "embassy",
                "constitution", "amendment", "impeach", "filibuster",
                "geopolitical", "sanctions", "treaty", "nato", "bilateral",
                "referendum", "constituency", "caucus", "partisan",
                "conservative", "liberal", "progressive", "populist",
                "authoritarian", "democracy", "republic", "monarchy",
            ],
            signal: [
                "government", "policy", "political", "party", "opposition",
                "administration", "federal", "regulation", "law", "reform",
                "debate", "protest", "rally", "rights", "civil",
            ]
        ),
        .business: TopicVocabulary(
            core: [
                "revenue", "profit", "earnings", "quarterly", "fiscal",
                "stock", "shares", "investor", "portfolio", "dividend",
                "merger", "acquisition", "ipo", "valuation", "venture",
                "capital", "funding", "startup", "entrepreneur", "ceo",
                "cfo", "cto", "shareholder", "stakeholder", "boardroom",
                "bankruptcy", "restructuring", "layoff", "downsizing",
                "gdp", "inflation", "recession", "deflation", "stimulus",
                "tariff", "trade", "export", "import", "supply",
                "demand", "logistics", "retail", "ecommerce", "consumer",
                "marketing", "advertising", "brand", "franchise",
            ],
            signal: [
                "market", "economy", "economic", "financial", "industry",
                "company", "corporate", "business", "commercial", "growth",
                "investment", "bank", "banking", "finance", "insurance",
            ]
        ),
        .health: TopicVocabulary(
            core: [
                "vaccine", "vaccination", "immunization", "antibody",
                "diagnosis", "symptom", "treatment", "therapy", "surgery",
                "patient", "hospital", "clinic", "physician", "surgeon",
                "pharmaceutical", "drug", "medication", "prescription",
                "cancer", "tumor", "diabetes", "heart", "cardiac",
                "stroke", "alzheimer", "dementia", "parkinson", "autism",
                "pandemic", "epidemic", "outbreak", "quarantine",
                "mental", "anxiety", "depression", "psychiatry", "psychology",
                "nutrition", "obesity", "cholesterol", "blood",
                "organ", "transplant", "prosthetic", "rehabilitation",
            ],
            signal: [
                "health", "medical", "clinical", "disease", "illness",
                "condition", "healthcare", "wellness", "fitness",
                "doctor", "nurse", "care", "healing", "recovery",
            ]
        ),
        .sports: TopicVocabulary(
            core: [
                "touchdown", "goal", "score", "championship", "tournament",
                "playoff", "semifinals", "finals", "league", "division",
                "nfl", "nba", "mlb", "nhl", "fifa", "uefa", "olympics",
                "athlete", "player", "coach", "referee", "umpire",
                "football", "basketball", "baseball", "soccer", "tennis",
                "golf", "cricket", "rugby", "hockey", "boxing",
                "swimming", "marathon", "sprint", "relay", "medal",
                "stadium", "arena", "roster", "draft", "transfer",
                "injury", "concussion", "doping", "steroid",
            ],
            signal: [
                "game", "match", "team", "season", "win", "loss",
                "defeat", "victory", "record", "performance", "training",
                "competition", "sport", "athletic", "fitness",
            ]
        ),
        .entertainment: TopicVocabulary(
            core: [
                "movie", "film", "cinema", "director", "actor", "actress",
                "oscar", "emmy", "grammy", "golden", "nomination",
                "streaming", "netflix", "disney", "hbo", "hulu", "spotify",
                "album", "single", "concert", "tour", "festival",
                "celebrity", "paparazzi", "gossip", "tabloid",
                "tv", "television", "series", "sitcom", "drama", "comedy",
                "animation", "cartoon", "anime", "manga",
                "gaming", "videogame", "esports", "twitch", "playstation",
                "xbox", "nintendo", "steam",
                "novel", "bestseller", "fiction", "thriller", "romance",
                "broadway", "theater", "musical", "ballet", "opera",
            ],
            signal: [
                "show", "star", "fan", "release", "premiere", "episode",
                "cast", "sequel", "franchise", "box", "office",
                "music", "song", "band", "artist", "performance",
            ]
        ),
        .environment: TopicVocabulary(
            core: [
                "climate", "warming", "carbon", "emission", "greenhouse",
                "renewable", "solar", "wind", "hydroelectric", "geothermal",
                "biodiversity", "ecosystem", "habitat", "conservation",
                "deforestation", "reforestation", "wildfire", "drought",
                "flooding", "hurricane", "typhoon", "tornado", "earthquake",
                "pollution", "contamination", "toxic", "waste", "recycling",
                "sustainability", "sustainable", "ecological", "endangered",
                "extinction", "coral", "reef", "arctic", "antarctic",
                "glacier", "icecap", "ozone", "methane",
                "pesticide", "herbicide", "organic", "permaculture",
            ],
            signal: [
                "environment", "environmental", "nature", "natural",
                "green", "clean", "energy", "fossil", "fuel",
                "ocean", "forest", "wildlife", "species", "planet",
            ]
        ),
        .education: TopicVocabulary(
            core: [
                "student", "teacher", "professor", "curriculum", "syllabus",
                "enrollment", "graduation", "diploma", "degree", "phd",
                "scholarship", "tuition", "campus", "dormitory",
                "classroom", "lecture", "seminar", "tutorial", "homework",
                "exam", "quiz", "grading", "gpa", "standardized",
                "literacy", "numeracy", "kindergarten", "elementary",
                "highschool", "undergraduate", "postgraduate", "doctoral",
                "mooc", "elearning", "edtech", "coursework",
            ],
            signal: [
                "education", "school", "college", "university", "academic",
                "learning", "teaching", "knowledge", "training", "skill",
                "study", "course", "program", "institute",
            ]
        ),
        .lifestyle: TopicVocabulary(
            core: [
                "recipe", "cooking", "baking", "cuisine", "restaurant",
                "chef", "ingredient", "gourmet", "vegan", "vegetarian",
                "fashion", "designer", "runway", "couture", "wardrobe",
                "travel", "tourism", "destination", "vacation", "resort",
                "hotel", "airbnb", "backpacking", "itinerary",
                "interior", "decor", "renovation", "architecture",
                "gardening", "landscaping", "diy", "crafts", "hobby",
                "parenting", "childcare", "pregnancy", "wedding",
                "dating", "relationship", "divorce", "marriage",
                "mindfulness", "meditation", "yoga", "selfcare",
            ],
            signal: [
                "lifestyle", "home", "family", "personal", "beauty",
                "style", "trend", "popular", "culture", "social",
                "food", "drink", "wine", "coffee", "tea",
            ]
        ),
        .world: TopicVocabulary(
            core: [
                "united", "nations", "international", "foreign", "affairs",
                "refugee", "migration", "asylum", "border", "immigration",
                "humanitarian", "peacekeeping", "ceasefire", "conflict",
                "war", "military", "troops", "invasion", "occupation",
                "terrorism", "extremism", "insurgency", "guerrilla",
                "genocide", "atrocity", "famine", "poverty",
                "aid", "relief", "unicef", "who", "imf",
            ],
            signal: [
                "global", "worldwide", "region", "country", "nation",
                "crisis", "disaster", "summit", "alliance", "cooperation",
                "security", "defense", "peace", "diplomatic",
            ]
        ),
    ]

    // MARK: - Classification

    /// Classify a story into one or more topics.
    ///
    /// Tokenizes the combined title + body text, matches against topic
    /// vocabularies with weighted scoring, and returns all topics above
    /// the confidence threshold.
    ///
    /// - Parameter story: The story to classify.
    /// - Returns: Classification result with primary topic and confidence.
    func classify(_ story: Story) -> TopicClassification {
        let text = "\(story.title) \(story.title) \(story.body)"
        return classifyText(text)
    }

    /// Classify arbitrary text (for testing or non-Story inputs).
    func classifyText(_ text: String) -> TopicClassification {
        let tokens = TextAnalyzer.shared.tokenize(text, minLength: 3)
        let tokenSet = Set(tokens)

        // Count weighted matches per topic
        var topicScores: [ArticleTopic: (weight: Double, matches: Int)] = [:]
        var totalWeight: Double = 0

        for (topic, vocab) in vocabularies {
            var weight: Double = 0
            var matches = 0

            for token in tokenSet {
                if vocab.core.contains(token) {
                    weight += 2.0
                    matches += 1
                } else if vocab.signal.contains(token) {
                    weight += 1.0
                    matches += 1
                }
            }

            // Boost for token frequency (repeated mentions)
            for token in tokens {
                if vocab.core.contains(token) {
                    weight += 0.5  // diminishing returns for repeats
                }
            }

            if matches > 0 {
                topicScores[topic] = (weight, matches)
                totalWeight += weight
            }
        }

        // Normalize scores
        guard totalWeight > 0 else {
            return TopicClassification(
                primary: .uncategorized,
                topics: [TopicScore(topic: .uncategorized, score: 1.0)],
                matchCount: 0,
                confidence: 0.0
            )
        }

        var scored: [TopicScore] = topicScores.map { (topic, data) in
            TopicScore(topic: topic, score: data.weight / totalWeight)
        }
        scored.sort { $0.score > $1.score }

        let totalMatches = topicScores.values.reduce(0) { $0 + $1.matches }

        // Apply minimum match threshold
        if totalMatches < minimumMatches {
            return TopicClassification(
                primary: .uncategorized,
                topics: [TopicScore(topic: .uncategorized, score: 1.0)],
                matchCount: totalMatches,
                confidence: 0.0
            )
        }

        // Filter by confidence threshold
        let significant = scored.filter { $0.score >= confidenceThreshold }
        let primary = significant.first?.topic ?? .uncategorized
        let confidence = significant.first?.score ?? 0.0

        return TopicClassification(
            primary: primary,
            topics: significant.isEmpty
                ? [TopicScore(topic: .uncategorized, score: 1.0)]
                : significant,
            matchCount: totalMatches,
            confidence: confidence
        )
    }

    // MARK: - Batch Classification

    /// Classify multiple stories at once.
    func classifyAll(_ stories: [Story]) -> [TopicClassification] {
        return stories.map { classify($0) }
    }

    /// Returns a topic distribution for a set of stories.
    /// Maps each topic to the fraction of stories where it appears as primary.
    func topicDistribution(_ stories: [Story]) -> [ArticleTopic: Double] {
        guard !stories.isEmpty else { return [:] }
        let results = classifyAll(stories)
        var counts: [ArticleTopic: Int] = [:]
        for result in results {
            counts[result.primary, default: 0] += 1
        }
        let total = Double(stories.count)
        return counts.mapValues { Double($0) / total }
    }

    // MARK: - Feed Topic Profile

    /// Build a topic profile for a feed based on its stories.
    ///
    /// - Parameters:
    ///   - feedName: The feed's display name.
    ///   - stories: Stories from that feed.
    /// - Returns: Profile with topic distribution, dominant topic, and diversity.
    func feedProfile(feedName: String, stories: [Story]) -> FeedTopicProfile {
        let dist = topicDistribution(stories)
        let dominant = dist.max { $0.value < $1.value }?.key ?? .uncategorized

        // Shannon entropy for diversity (normalized to 0–1)
        let topicCount = ArticleTopic.allCases.count - 1  // exclude uncategorized
        let maxEntropy = log(Double(topicCount))
        var entropy: Double = 0
        for (_, proportion) in dist where proportion > 0 {
            entropy -= proportion * log(proportion)
        }
        let diversity = maxEntropy > 0 ? entropy / maxEntropy : 0

        return FeedTopicProfile(
            feedName: feedName,
            articleCount: stories.count,
            distribution: dist,
            dominantTopic: dominant,
            diversity: min(1.0, diversity)
        )
    }

    // MARK: - Trending Topics

    /// Detect trending topics by comparing recent vs baseline article counts.
    ///
    /// - Parameters:
    ///   - recent: Stories from the recent window (e.g., last 24h).
    ///   - baseline: Stories from a longer reference period (e.g., last 7 days).
    ///   - minArticles: Minimum recent articles for a topic to be considered.
    /// - Returns: Topics sorted by trend strength (strongest first).
    func detectTrends(
        recent: [Story],
        baseline: [Story],
        minArticles: Int = 2
    ) -> [TrendingTopic] {
        let recentDist = topicCounts(stories: recent)
        let baselineDist = topicCounts(stories: baseline)

        // Normalize baseline to the same window length
        let recentTotal = max(1, recent.count)
        let baselineTotal = max(1, baseline.count)
        let scaleFactor = Double(recentTotal) / Double(baselineTotal)

        var trends: [TrendingTopic] = []

        for topic in ArticleTopic.allCases where topic != .uncategorized {
            let recentCount = recentDist[topic] ?? 0
            guard recentCount >= minArticles else { continue }

            let baselineCount = baselineDist[topic] ?? 0
            let scaledBaseline = Double(baselineCount) * scaleFactor

            let strength: Double
            let direction: TrendingTopic.TrendDirection

            if scaledBaseline < 0.5 {
                // New topic — no baseline presence
                strength = Double(recentCount) * 2.0
                direction = .rising
            } else {
                let ratio = Double(recentCount) / scaledBaseline
                strength = ratio
                if ratio > 1.3 {
                    direction = .rising
                } else if ratio < 0.7 {
                    direction = .falling
                } else {
                    direction = .stable
                }
            }

            trends.append(TrendingTopic(
                topic: topic,
                recentCount: recentCount,
                baselineCount: baselineCount,
                trendStrength: strength,
                direction: direction
            ))
        }

        return trends
            .filter { $0.direction != .stable }
            .sorted { $0.trendStrength > $1.trendStrength }
    }

    // MARK: - Summary Report

    /// Generate a human-readable classification report for a set of stories.
    func report(stories: [Story], feedName: String = "All Feeds") -> String {
        let profile = feedProfile(feedName: feedName, stories: stories)
        let sorted = profile.distribution.sorted { $0.value > $1.value }

        var lines: [String] = []
        lines.append("═══════════════════════════════════════")
        lines.append("📊 Topic Classification Report")
        lines.append("═══════════════════════════════════════")
        lines.append("")
        lines.append("Feed: \(feedName)")
        lines.append("Articles analyzed: \(stories.count)")
        lines.append("Dominant topic: \(profile.dominantTopic.emoji) \(profile.dominantTopic.rawValue)")
        lines.append(String(format: "Topic diversity: %.0f%%", profile.diversity * 100))
        lines.append("")
        lines.append("── Distribution ──")
        for (topic, pct) in sorted {
            let bar = String(repeating: "█", count: Int(pct * 30))
            let name = topic.rawValue.padding(toLength: 15, withPad: " ", startingAt: 0)
            lines.append("  \(topic.emoji) \(name) \(String(format: "%5.1f", pct * 100))% \(bar)")
        }
        lines.append("")
        lines.append("═══════════════════════════════════════")

        return lines.joined(separator: "\n")
    }

    // MARK: - Private Helpers

    private func topicCounts(stories: [Story]) -> [ArticleTopic: Int] {
        let results = classifyAll(stories)
        var counts: [ArticleTopic: Int] = [:]
        for result in results {
            counts[result.primary, default: 0] += 1
        }
        return counts
    }
}
