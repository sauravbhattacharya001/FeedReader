//
//  ArticleLanguageDetector.swift
//  FeedReader
//
//  Language detection for articles using character trigram frequency analysis.
//  Identifies the language of article text, categorizes feeds by language
//  distribution, and provides multilingual reading statistics. Useful for
//  users who follow feeds in multiple languages.
//

import Foundation

// MARK: - Models

/// Supported languages for detection.
enum DetectedLanguage: String, Codable, CaseIterable, Comparable {
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case portuguese = "pt"
    case dutch = "nl"
    case swedish = "sv"
    case norwegian = "no"
    case danish = "da"
    case turkish = "tr"
    case polish = "pl"
    case czech = "cs"
    case romanian = "ro"
    case indonesian = "id"
    case unknown = "unknown"

    var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .german: return "German"
        case .italian: return "Italian"
        case .portuguese: return "Portuguese"
        case .dutch: return "Dutch"
        case .swedish: return "Swedish"
        case .norwegian: return "Norwegian"
        case .danish: return "Danish"
        case .turkish: return "Turkish"
        case .polish: return "Polish"
        case .czech: return "Czech"
        case .romanian: return "Romanian"
        case .indonesian: return "Indonesian"
        case .unknown: return "Unknown"
        }
    }

    static func < (lhs: DetectedLanguage, rhs: DetectedLanguage) -> Bool {
        lhs.displayName < rhs.displayName
    }
}

/// Result of language detection for a single text.
struct LanguageDetectionResult: Codable, Equatable {
    let language: DetectedLanguage
    let confidence: Double // 0.0–1.0
    let scores: [DetectedLanguage: Double]
    let textLength: Int

    var isConfident: Bool { confidence >= 0.6 }
}

/// Language statistics for a single article.
struct ArticleLanguageRecord: Codable, Equatable {
    let articleTitle: String
    let articleLink: String
    let feedName: String
    let detectedLanguage: DetectedLanguage
    let confidence: Double
    let date: Date
    let wordCount: Int
}

/// Language distribution for a feed.
struct FeedLanguageProfile: Codable, Equatable {
    let feedName: String
    let primaryLanguage: DetectedLanguage
    let languageCounts: [DetectedLanguage: Int]
    let totalArticles: Int

    var isMultilingual: Bool {
        languageCounts.filter { $0.value > 0 }.count > 1
    }

    var languagePercentages: [DetectedLanguage: Double] {
        guard totalArticles > 0 else { return [:] }
        return languageCounts.mapValues { Double($0) / Double(totalArticles) * 100.0 }
    }
}

/// Overall multilingual reading summary.
struct MultilingualReadingSummary: Codable, Equatable {
    let totalArticles: Int
    let languageCounts: [DetectedLanguage: Int]
    let feedProfiles: [FeedLanguageProfile]
    let multilingualFeedCount: Int
    let primaryLanguage: DetectedLanguage
    let diversityScore: Double // 0.0–1.0, higher = more diverse

    var languagePercentages: [DetectedLanguage: Double] {
        guard totalArticles > 0 else { return [:] }
        return languageCounts.mapValues { Double($0) / Double(totalArticles) * 100.0 }
    }
}

// MARK: - Language Profiles (Trigram Frequencies)

/// Character trigram frequency profiles for supported languages.
/// These are the top ~30 trigrams by frequency for each language,
/// derived from standard language corpora.
private struct LanguageProfiles {
    static let profiles: [DetectedLanguage: [String: Double]] = [
        .english: [
            "the": 3.51, "and": 1.65, "ing": 1.53, "her": 1.02, "hat": 0.95,
            "his": 0.93, "tha": 0.92, "ere": 0.86, "for": 0.84, "ent": 0.83,
            "ion": 0.82, "ter": 0.76, "was": 0.74, "you": 0.72, "ith": 0.71,
            "ver": 0.69, "all": 0.68, "wit": 0.67, "thi": 0.65, "tio": 0.64,
            "ons": 0.58, "ess": 0.56, "not": 0.55, "ive": 0.54, "ght": 0.50,
            "est": 0.49, "rea": 0.48, "ave": 0.47, "ome": 0.46, "out": 0.44
        ],
        .spanish: [
            "que": 2.10, "ent": 1.55, "ión": 1.40, "con": 1.35, "aci": 1.25,
            "ado": 1.20, "est": 1.15, "las": 1.10, "los": 1.08, "nte": 1.05,
            "del": 1.00, "ien": 0.95, "par": 0.90, "una": 0.88, "ció": 0.85,
            "por": 0.83, "res": 0.80, "com": 0.78, "era": 0.75, "sta": 0.72,
            "mos": 0.70, "uer": 0.65, "aba": 0.62, "tra": 0.60, "nto": 0.58,
            "dos": 0.55, "ero": 0.53, "ido": 0.50, "tos": 0.48, "nos": 0.45
        ],
        .french: [
            "les": 2.20, "ent": 1.80, "que": 1.65, "des": 1.55, "ion": 1.40,
            "ait": 1.30, "ous": 1.25, "pas": 1.10, "est": 1.05, "par": 1.00,
            "our": 0.95, "eur": 0.90, "com": 0.85, "eme": 0.82, "ais": 0.80,
            "men": 0.78, "ans": 0.75, "res": 0.72, "ell": 0.70, "tio": 0.68,
            "pou": 0.65, "ons": 0.62, "con": 0.60, "son": 0.58, "ait": 0.55,
            "ble": 0.52, "uss": 0.50, "dan": 0.48, "ire": 0.45, "ter": 0.42
        ],
        .german: [
            "ein": 2.30, "ich": 2.10, "sch": 1.95, "die": 1.80, "der": 1.75,
            "und": 1.70, "den": 1.50, "cht": 1.45, "ber": 1.30, "ung": 1.25,
            "gen": 1.20, "ver": 1.15, "ter": 1.10, "eit": 1.05, "ine": 1.00,
            "auf": 0.95, "ges": 0.90, "ten": 0.88, "mit": 0.85, "nen": 0.82,
            "ste": 0.80, "ent": 0.78, "erd": 0.75, "lic": 0.72, "ier": 0.70,
            "ige": 0.65, "ell": 0.62, "hei": 0.60, "ach": 0.58, "ern": 0.55
        ],
        .italian: [
            "che": 2.40, "per": 1.80, "ell": 1.65, "ato": 1.50, "ent": 1.40,
            "lla": 1.35, "con": 1.30, "ion": 1.25, "non": 1.15, "gli": 1.10,
            "del": 1.05, "nte": 1.00, "tti": 0.95, "zio": 0.90, "una": 0.85,
            "ere": 0.82, "sta": 0.80, "ale": 0.78, "ono": 0.75, "ato": 0.72,
            "pre": 0.70, "ess": 0.68, "anz": 0.65, "olo": 0.62, "tto": 0.60,
            "men": 0.58, "amo": 0.55, "pro": 0.52, "rop": 0.50, "ita": 0.48
        ],
        .portuguese: [
            "que": 2.30, "ent": 1.70, "ção": 1.55, "con": 1.40, "ado": 1.30,
            "est": 1.20, "com": 1.15, "par": 1.10, "nte": 1.05, "dos": 1.00,
            "por": 0.95, "uma": 0.90, "sta": 0.85, "ões": 0.82, "men": 0.80,
            "res": 0.78, "mos": 0.75, "era": 0.72, "nto": 0.70, "ido": 0.68,
            "ais": 0.65, "ter": 0.62, "nos": 0.60, "sse": 0.58, "cia": 0.55,
            "tra": 0.52, "ame": 0.50, "pre": 0.48, "ria": 0.45, "ado": 0.42
        ],
        .dutch: [
            "een": 2.50, "het": 2.20, "van": 2.10, "aar": 1.80, "den": 1.60,
            "ver": 1.50, "oor": 1.40, "ijk": 1.30, "erd": 1.20, "nde": 1.15,
            "sch": 1.10, "ien": 1.05, "ter": 1.00, "gen": 0.95, "met": 0.90,
            "ren": 0.85, "oge": 0.80, "ers": 0.78, "ste": 0.75, "aat": 0.72,
            "ele": 0.70, "eld": 0.68, "eel": 0.65, "and": 0.62, "sta": 0.60,
            "ond": 0.58, "ink": 0.55, "eti": 0.52, "eni": 0.50, "ach": 0.48
        ],
        .swedish: [
            "och": 2.60, "för": 2.10, "att": 1.90, "det": 1.80, "som": 1.65,
            "den": 1.50, "var": 1.40, "med": 1.30, "kan": 1.20, "har": 1.15,
            "int": 1.10, "nte": 1.05, "ing": 1.00, "gen": 0.95, "lig": 0.90,
            "tta": 0.85, "ade": 0.80, "nde": 0.78, "lle": 0.75, "ter": 0.72,
            "era": 0.70, "ill": 0.68, "sta": 0.65, "isk": 0.62, "ens": 0.60,
            "rna": 0.58, "iga": 0.55, "kal": 0.52, "tig": 0.50, "der": 0.48
        ],
        .norwegian: [
            "det": 2.40, "for": 2.00, "som": 1.85, "med": 1.70, "den": 1.55,
            "har": 1.45, "ikke": 1.35, "var": 1.30, "ent": 1.20, "kan": 1.15,
            "men": 1.10, "ble": 1.05, "til": 1.00, "ing": 0.95, "ere": 0.90,
            "lig": 0.85, "nde": 0.80, "gen": 0.78, "tte": 0.75, "ter": 0.72,
            "der": 0.70, "ett": 0.68, "kke": 0.65, "ste": 0.62, "ene": 0.60,
            "ell": 0.58, "ver": 0.55, "kal": 0.52, "all": 0.50, "rik": 0.48
        ],
        .danish: [
            "det": 2.50, "den": 2.00, "for": 1.85, "med": 1.70, "som": 1.60,
            "har": 1.50, "var": 1.40, "kan": 1.30, "ent": 1.20, "ikke": 1.15,
            "men": 1.10, "til": 1.05, "lig": 1.00, "ere": 0.95, "nde": 0.90,
            "ing": 0.85, "gen": 0.80, "tte": 0.78, "ter": 0.75, "der": 0.72,
            "hed": 0.70, "ell": 0.68, "ige": 0.65, "ste": 0.62, "ene": 0.60,
            "kke": 0.58, "ver": 0.55, "kal": 0.52, "all": 0.50, "sig": 0.48
        ],
        .turkish: [
            "lar": 2.60, "bir": 2.30, "ler": 2.10, "eri": 1.80, "ını": 1.60,
            "ari": 1.50, "ile": 1.40, "yor": 1.30, "ası": 1.20, "nda": 1.15,
            "dan": 1.10, "dır": 1.05, "ini": 1.00, "ine": 0.95, "anl": 0.90,
            "unu": 0.85, "aya": 0.80, "rak": 0.78, "eni": 0.75, "esi": 0.72,
            "iri": 0.70, "nın": 0.68, "ınd": 0.65, "olm": 0.62, "mas": 0.60,
            "mak": 0.58, "dir": 0.55, "ken": 0.52, "ola": 0.50, "akl": 0.48
        ],
        .polish: [
            "nie": 2.50, "prz": 2.10, "icz": 1.80, "owa": 1.60, "eni": 1.50,
            "rze": 1.40, "ych": 1.30, "nia": 1.20, "sto": 1.15, "acz": 1.10,
            "wie": 1.05, "kie": 1.00, "ego": 0.95, "sta": 0.90, "owa": 0.85,
            "prz": 0.82, "emi": 0.80, "pro": 0.78, "ods": 0.75, "jes": 0.72,
            "ani": 0.70, "czn": 0.68, "rod": 0.65, "pow": 0.62, "nym": 0.60,
            "sze": 0.58, "lni": 0.55, "pod": 0.52, "dzi": 0.50, "tow": 0.48
        ],
        .czech: [
            "pro": 2.40, "ost": 1.90, "ení": 1.70, "ova": 1.55, "pře": 1.45,
            "sti": 1.35, "kte": 1.25, "ého": 1.20, "nic": 1.15, "val": 1.10,
            "ter": 1.05, "pod": 1.00, "sta": 0.95, "vat": 0.90, "nes": 0.85,
            "hou": 0.82, "ním": 0.80, "emi": 0.78, "oho": 0.75, "tov": 0.72,
            "rod": 0.70, "rav": 0.68, "sou": 0.65, "sti": 0.62, "ván": 0.60,
            "ych": 0.58, "chn": 0.55, "hra": 0.52, "ent": 0.50, "ani": 0.48
        ],
        .romanian: [
            "are": 2.30, "ent": 1.80, "ate": 1.65, "rea": 1.50, "pen": 1.40,
            "lui": 1.30, "tru": 1.25, "unt": 1.20, "lor": 1.15, "est": 1.10,
            "ulu": 1.05, "ile": 1.00, "car": 0.95, "con": 0.90, "ală": 0.85,
            "pre": 0.82, "ari": 0.80, "ele": 0.78, "rea": 0.75, "sta": 0.72,
            "poa": 0.70, "pro": 0.68, "int": 0.65, "pri": 0.62, "ste": 0.60,
            "tre": 0.58, "tea": 0.55, "tul": 0.52, "eri": 0.50, "mod": 0.48
        ],
        .indonesian: [
            "ang": 2.80, "kan": 2.30, "men": 2.00, "yan": 1.80, "ber": 1.60,
            "per": 1.50, "ada": 1.40, "ata": 1.30, "eng": 1.20, "dan": 1.15,
            "dar": 1.10, "aka": 1.05, "ter": 1.00, "ung": 0.95, "era": 0.90,
            "nya": 0.85, "mem": 0.80, "pen": 0.78, "ala": 0.75, "ela": 0.72,
            "end": 0.70, "gar": 0.68, "ran": 0.65, "san": 0.62, "ari": 0.60,
            "apa": 0.58, "han": 0.55, "kar": 0.52, "rak": 0.50, "emp": 0.48
        ]
    ]
}

// MARK: - ArticleLanguageDetector

/// Detects article language using character trigram frequency analysis.
/// Categorizes feeds by language distribution and provides multilingual
/// reading statistics.
class ArticleLanguageDetector {

    // MARK: - Constants

    static let minTextLength = 50
    static let maxRecords = 5000
    static let defaultConfidenceThreshold = 0.3

    // MARK: - Storage

    private let store: UserDefaultsCodableStore<[ArticleLanguageRecord]>
    private var records: [ArticleLanguageRecord]

    // MARK: - Init

    init() {
        store = UserDefaultsCodableStore(key: "articleLanguageRecords")
        records = store.load() ?? []
    }

    // MARK: - Language Detection

    /// Detect the language of the given text.
    func detectLanguage(_ text: String) -> LanguageDetectionResult {
        let cleaned = normalizeText(text)
        guard cleaned.count >= Self.minTextLength else {
            return LanguageDetectionResult(
                language: .unknown,
                confidence: 0,
                scores: [:],
                textLength: cleaned.count
            )
        }

        let trigrams = extractTrigrams(cleaned)
        guard !trigrams.isEmpty else {
            return LanguageDetectionResult(
                language: .unknown,
                confidence: 0,
                scores: [:],
                textLength: cleaned.count
            )
        }

        var scores: [DetectedLanguage: Double] = [:]

        for (language, profile) in LanguageProfiles.profiles {
            scores[language] = calculateScore(trigrams: trigrams, profile: profile)
        }

        // Normalize scores
        let maxScore = scores.values.max() ?? 0
        guard maxScore > 0 else {
            return LanguageDetectionResult(
                language: .unknown,
                confidence: 0,
                scores: [:],
                textLength: cleaned.count
            )
        }

        let normalized = scores.mapValues { $0 / maxScore }

        // Find best match
        let sorted = normalized.sorted { $0.value > $1.value }
        let bestLanguage = sorted[0].key
        let bestScore = sorted[0].value
        let secondScore = sorted.count > 1 ? sorted[1].value : 0

        // Confidence based on gap between top two scores
        let confidence = min(1.0, bestScore * (bestScore - secondScore + 0.3))

        return LanguageDetectionResult(
            language: bestLanguage,
            confidence: confidence,
            scores: normalized,
            textLength: cleaned.count
        )
    }

    // MARK: - Article Recording

    /// Detect language and record an article.
    @discardableResult
    func recordArticle(title: String, link: String, body: String,
                       feedName: String, date: Date = Date()) -> ArticleLanguageRecord {
        let result = detectLanguage(body)
        let wordCount = body.split(separator: " ").count
        let record = ArticleLanguageRecord(
            articleTitle: title,
            articleLink: link,
            feedName: feedName,
            detectedLanguage: result.language,
            confidence: result.confidence,
            date: date,
            wordCount: wordCount
        )
        records.append(record)
        if records.count > Self.maxRecords {
            records = Array(records.suffix(Self.maxRecords))
        }
        save()
        return record
    }

    /// All recorded articles.
    var allRecords: [ArticleLanguageRecord] { records }

    /// Records filtered by language.
    func records(for language: DetectedLanguage) -> [ArticleLanguageRecord] {
        records.filter { $0.detectedLanguage == language }
    }

    /// Records filtered by feed name.
    func records(forFeed feedName: String) -> [ArticleLanguageRecord] {
        records.filter { $0.feedName == feedName }
    }

    /// Records filtered by date range.
    func records(from start: Date, to end: Date) -> [ArticleLanguageRecord] {
        records.filter { $0.date >= start && $0.date <= end }
    }

    // MARK: - Feed Language Profiles

    /// Get the language profile for a specific feed.
    func feedProfile(for feedName: String) -> FeedLanguageProfile {
        let feedRecords = records(forFeed: feedName)
        var counts: [DetectedLanguage: Int] = [:]
        for record in feedRecords {
            counts[record.detectedLanguage, default: 0] += 1
        }
        let primary = counts.max(by: { $0.value < $1.value })?.key ?? .unknown
        return FeedLanguageProfile(
            feedName: feedName,
            primaryLanguage: primary,
            languageCounts: counts,
            totalArticles: feedRecords.count
        )
    }

    /// Get language profiles for all feeds.
    func allFeedProfiles() -> [FeedLanguageProfile] {
        let feedNames = Set(records.map { $0.feedName })
        return feedNames.map { feedProfile(for: $0) }.sorted { $0.totalArticles > $1.totalArticles }
    }

    /// Get feeds detected as multilingual.
    func multilingualFeeds() -> [FeedLanguageProfile] {
        allFeedProfiles().filter { $0.isMultilingual }
    }

    /// Get feeds by primary language.
    func feeds(byLanguage language: DetectedLanguage) -> [FeedLanguageProfile] {
        allFeedProfiles().filter { $0.primaryLanguage == language }
    }

    // MARK: - Multilingual Summary

    /// Generate an overall multilingual reading summary.
    func summary() -> MultilingualReadingSummary {
        var langCounts: [DetectedLanguage: Int] = [:]
        for record in records {
            langCounts[record.detectedLanguage, default: 0] += 1
        }

        let profiles = allFeedProfiles()
        let multilingualCount = profiles.filter { $0.isMultilingual }.count
        let primary = langCounts.max(by: { $0.value < $1.value })?.key ?? .unknown

        let diversity = calculateDiversityScore(langCounts)

        return MultilingualReadingSummary(
            totalArticles: records.count,
            languageCounts: langCounts,
            feedProfiles: profiles,
            multilingualFeedCount: multilingualCount,
            primaryLanguage: primary,
            diversityScore: diversity
        )
    }

    // MARK: - Filtering & Search

    /// Find articles with high confidence detection.
    func confidentDetections(minConfidence: Double = 0.7) -> [ArticleLanguageRecord] {
        records.filter { $0.confidence >= minConfidence }
    }

    /// Find articles with low confidence (may need manual review).
    func uncertainDetections(maxConfidence: Double = 0.4) -> [ArticleLanguageRecord] {
        records.filter { $0.confidence < maxConfidence }
    }

    /// Get unique languages detected across all articles.
    func detectedLanguages() -> [DetectedLanguage] {
        Array(Set(records.map { $0.detectedLanguage })).sorted()
    }

    /// Count articles per language.
    func articleCountByLanguage() -> [DetectedLanguage: Int] {
        var counts: [DetectedLanguage: Int] = [:]
        for record in records {
            counts[record.detectedLanguage, default: 0] += 1
        }
        return counts
    }

    /// Word count per language.
    func wordCountByLanguage() -> [DetectedLanguage: Int] {
        var counts: [DetectedLanguage: Int] = [:]
        for record in records {
            counts[record.detectedLanguage, default: 0] += record.wordCount
        }
        return counts
    }

    // MARK: - Text Report

    /// Generate a text report of multilingual reading activity.
    func textReport() -> String {
        let s = summary()
        var lines: [String] = []
        lines.append("=== Multilingual Reading Report ===")
        lines.append("")
        lines.append("Total articles analyzed: \(s.totalArticles)")
        lines.append("Languages detected: \(s.languageCounts.count)")
        lines.append("Primary language: \(s.primaryLanguage.displayName)")
        lines.append("Diversity score: \(String(format: "%.1f%%", s.diversityScore * 100))")
        lines.append("Multilingual feeds: \(s.multilingualFeedCount)")
        lines.append("")

        if !s.languageCounts.isEmpty {
            lines.append("--- Articles by Language ---")
            let sorted = s.languageCounts.sorted { $0.value > $1.value }
            for (lang, count) in sorted {
                let pct = s.totalArticles > 0 ? Double(count) / Double(s.totalArticles) * 100 : 0
                lines.append("  \(lang.displayName): \(count) (\(String(format: "%.1f%%", pct)))")
            }
            lines.append("")
        }

        let wordCounts = wordCountByLanguage()
        if !wordCounts.isEmpty {
            lines.append("--- Words Read by Language ---")
            let sorted = wordCounts.sorted { $0.value > $1.value }
            for (lang, count) in sorted {
                lines.append("  \(lang.displayName): \(count.formatted()) words")
            }
            lines.append("")
        }

        let multilingual = multilingualFeeds()
        if !multilingual.isEmpty {
            lines.append("--- Multilingual Feeds ---")
            for profile in multilingual.prefix(10) {
                let langs = profile.languageCounts
                    .filter { $0.value > 0 }
                    .sorted { $0.value > $1.value }
                    .map { "\($0.key.displayName): \($0.value)" }
                    .joined(separator: ", ")
                lines.append("  \(profile.feedName): \(langs)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Data Management

    /// Remove all records.
    func clearAll() {
        records.removeAll()
        save()
    }

    /// Remove records for a specific feed.
    func clearFeed(_ feedName: String) {
        records.removeAll { $0.feedName == feedName }
        save()
    }

    /// Total number of recorded articles.
    var recordCount: Int { records.count }

    /// Export all records as JSON data.
    func exportJSON() -> Data? {
        try? JSONEncoder().encode(records)
    }

    /// Import records from JSON data (merges, deduplicates by link).
    func importJSON(_ data: Data) -> Int {
        guard let imported = try? JSONDecoder().decode([ArticleLanguageRecord].self, from: data) else {
            return 0
        }
        let existingLinks = Set(records.map { $0.articleLink })
        let newRecords = imported.filter { !existingLinks.contains($0.articleLink) }
        records.append(contentsOf: newRecords)
        if records.count > Self.maxRecords {
            records = Array(records.suffix(Self.maxRecords))
        }
        save()
        return newRecords.count
    }

    // MARK: - Private Helpers

    private func normalizeText(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined()
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func extractTrigrams(_ text: String) -> [String: Int] {
        var trigrams: [String: Int] = [:]
        let chars = Array(text)
        guard chars.count >= 3 else { return trigrams }
        for i in 0..<(chars.count - 2) {
            let trigram = String(chars[i...i+2])
            trigrams[trigram, default: 0] += 1
        }
        return trigrams
    }

    private func calculateScore(trigrams: [String: Int], profile: [String: Double]) -> Double {
        var score = 0.0
        let totalTrigrams = trigrams.values.reduce(0, +)
        guard totalTrigrams > 0 else { return 0 }

        for (trigram, weight) in profile {
            if let count = trigrams[trigram] {
                score += Double(count) / Double(totalTrigrams) * weight
            }
        }
        return score
    }

    private func calculateDiversityScore(_ counts: [DetectedLanguage: Int]) -> Double {
        let total = counts.values.reduce(0, +)
        guard total > 0 else { return 0 }

        // Shannon entropy normalized to 0-1
        var entropy = 0.0
        for (_, count) in counts {
            let p = Double(count) / Double(total)
            if p > 0 {
                entropy -= p * log2(p)
            }
        }
        let maxEntropy = log2(Double(max(counts.count, 1)))
        return maxEntropy > 0 ? entropy / maxEntropy : 0
    }

    private func save() {
        store.save(records)
    }
}
