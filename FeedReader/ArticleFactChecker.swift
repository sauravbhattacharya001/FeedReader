//
//  ArticleFactChecker.swift
//  FeedReader
//
//  Extracts factual claims from article text and scores them for
//  verifiability. Identifies statistical claims, quoted statements,
//  date assertions, named entity claims, and causal assertions.
//  Assigns confidence and verifiability scores to help readers
//  critically evaluate article content.
//
//  Features:
//  - Extract factual claims using pattern matching (statistics, quotes,
//    dates, named entities, causal language)
//  - Classify claims by type (statistical, quote, temporal, attribution,
//    causal, comparative, definitional)
//  - Score verifiability (how easy a claim is to fact-check)
//  - Flag hedging language vs definitive assertions
//  - Aggregate article-level credibility indicators
//  - Track fact-check history with user verdicts
//  - Export fact-check reports as Markdown/JSON
//
//  All analysis is local — no external API calls. Uses heuristic
//  NLP patterns optimised for news article text.
//
//  Persistence: UserDefaults via Codable.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when a fact-check report is created or updated.
    static let factCheckDidUpdate = Notification.Name("ArticleFactCheckDidUpdateNotification")
}

// MARK: - ClaimType

/// Category of a factual claim extracted from article text.
enum ClaimType: String, Codable, CaseIterable {
    /// Contains numbers, percentages, or statistical language.
    case statistical = "statistical"
    /// Direct or indirect quotation attributed to a source.
    case quote = "quote"
    /// References specific dates, times, or time periods.
    case temporal = "temporal"
    /// Attributes an action or statement to a named entity.
    case attribution = "attribution"
    /// Asserts a cause-and-effect relationship.
    case causal = "causal"
    /// Compares two or more entities.
    case comparative = "comparative"
    /// Defines or categorises something.
    case definitional = "definitional"

    var displayName: String {
        switch self {
        case .statistical: return "Statistical"
        case .quote: return "Quote"
        case .temporal: return "Temporal"
        case .attribution: return "Attribution"
        case .causal: return "Cause & Effect"
        case .comparative: return "Comparison"
        case .definitional: return "Definition"
        }
    }

    /// Base verifiability weight — some claim types are inherently
    /// easier to fact-check than others.
    var baseVerifiability: Double {
        switch self {
        case .statistical: return 0.9
        case .quote: return 0.8
        case .temporal: return 0.85
        case .attribution: return 0.7
        case .causal: return 0.4
        case .comparative: return 0.6
        case .definitional: return 0.5
        }
    }
}

// MARK: - UserVerdict

/// User's manual verdict on a claim after investigation.
enum UserVerdict: String, Codable, CaseIterable {
    case verified = "verified"
    case disputed = "disputed"
    case unverified = "unverified"
    case misleading = "misleading"
    case opinion = "opinion"

    var emoji: String {
        switch self {
        case .verified: return "✅"
        case .disputed: return "❌"
        case .unverified: return "❓"
        case .misleading: return "⚠️"
        case .opinion: return "💭"
        }
    }
}

// MARK: - FactualClaim

/// A single factual claim extracted from article text.
struct FactualClaim: Codable, Equatable {
    /// Unique identifier.
    let id: String
    /// The extracted claim text.
    let text: String
    /// Surrounding context (sentence before + after).
    let context: String
    /// Claim category.
    let type: ClaimType
    /// 0.0–1.0 confidence that this is actually a factual claim.
    let confidence: Double
    /// 0.0–1.0 how easy this claim is to verify.
    let verifiability: Double
    /// Whether hedging language was detected ("allegedly", "reportedly").
    let isHedged: Bool
    /// Named entities mentioned in the claim.
    let entities: [String]
    /// Character range in the original article text.
    let rangeStart: Int
    let rangeEnd: Int

    static func == (lhs: FactualClaim, rhs: FactualClaim) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - FactCheckReport

/// Complete fact-check analysis of an article.
struct FactCheckReport: Codable {
    /// Unique report identifier.
    let id: String
    /// Article link/identifier.
    let articleLink: String
    /// Article title.
    let articleTitle: String
    /// When the analysis was performed.
    let analysedDate: Date
    /// Extracted claims.
    let claims: [FactualClaim]
    /// Overall credibility indicators.
    let credibilityScore: Double
    /// Ratio of hedged to definitive claims.
    let hedgeRatio: Double
    /// Number of distinct named sources cited.
    let sourceCount: Int
    /// Claim type distribution.
    let typeBreakdown: [String: Int]
    /// User verdicts (claim ID → verdict), stored separately.
    var verdicts: [String: UserVerdict]

    /// Claims sorted by verifiability (easiest to check first).
    var claimsByVerifiability: [FactualClaim] {
        return claims.sorted { $0.verifiability > $1.verifiability }
    }

    /// Claims that are definitive (not hedged) and high-confidence.
    var definitiveHighConfidence: [FactualClaim] {
        return claims.filter { !$0.isHedged && $0.confidence >= 0.7 }
    }
}

// MARK: - ArticleFactChecker

/// Extracts and analyses factual claims from article text.
///
/// ## Usage
/// ```swift
/// let checker = ArticleFactChecker()
/// let report = checker.analyse(
///     articleTitle: "Tech Giant Reports Record Earnings",
///     articleLink: "https://example.com/article",
///     text: articleBody
/// )
/// print("Found \(report.claims.count) claims, credibility: \(report.credibilityScore)")
/// ```
class ArticleFactChecker {

    // MARK: - Persistence Key

    private static let storageKey = "ArticleFactChecker_Reports"
    private static let verdictsKey = "ArticleFactChecker_Verdicts"

    // MARK: - Pattern Definitions

    /// Patterns for detecting statistical claims.
    private static let statisticalPatterns: [(pattern: String, confidence: Double)] = [
        ("\\b\\d+\\.?\\d*\\s*%", 0.9),                          // percentages
        ("\\b\\d{1,3}(,\\d{3})+\\b", 0.8),                      // large numbers with commas
        ("\\$\\d+(\\.\\d{2})?\\s*(million|billion|trillion)?", 0.9), // dollar amounts
        ("\\b(doubled|tripled|quadrupled|halved)\\b", 0.7),      // multiplier language
        ("\\b\\d+(\\.\\d+)?x\\b", 0.75),                         // multipliers (3x, 2.5x)
        ("\\b(million|billion|trillion)\\b", 0.7),                // scale words
        ("\\b(average|median|mean)\\s+of\\s+\\d", 0.85),         // statistical measures
        ("\\b\\d+\\s+(out of|in every)\\s+\\d+", 0.85),          // ratios
        ("\\b(rose|fell|dropped|increased|decreased|grew|shrank)\\s+by\\s+\\d", 0.8), // changes
    ]

    /// Patterns for detecting quoted/attributed claims.
    private static let quotePatterns: [(pattern: String, confidence: Double)] = [
        ("\u{201C}[^\u{201D}]{10,}\u{201D}", 0.9),               // smart quotes
        ("\"[^\"]{10,}\"", 0.85),                                 // straight quotes
        ("\\bsaid\\s+that\\b", 0.8),                              // reported speech
        ("\\baccording\\s+to\\b", 0.85),                          // attribution
        ("\\btold\\s+(reporters|journalists|\\w+\\s+News)", 0.8), // told media
    ]

    /// Patterns for detecting temporal claims.
    private static let temporalPatterns: [(pattern: String, confidence: Double)] = [
        ("\\b(January|February|March|April|May|June|July|August|September|October|November|December)\\s+\\d{1,2},?\\s+\\d{4}", 0.9), // full dates
        ("\\b(19|20)\\d{2}\\b", 0.6),                             // years
        ("\\b(last|next|this)\\s+(week|month|year|quarter)", 0.7), // relative time
        ("\\b\\d+\\s+(days?|weeks?|months?|years?)\\s+(ago|later|earlier)", 0.8), // time offsets
        ("\\bsince\\s+(19|20)\\d{2}", 0.8),                       // since year
    ]

    /// Patterns for detecting causal claims.
    private static let causalPatterns: [(pattern: String, confidence: Double)] = [
        ("\\b(because|caused by|due to|as a result of|led to|resulted in)\\b", 0.7),
        ("\\b(therefore|consequently|thus|hence)\\b", 0.65),
        ("\\b(if .+ then)\\b", 0.6),
        ("\\b(contribut(ed|es|ing) to)\\b", 0.65),
        ("\\b(trigger(ed|s|ing))\\b", 0.6),
    ]

    /// Patterns for detecting comparative claims.
    private static let comparativePatterns: [(pattern: String, confidence: Double)] = [
        ("\\b(more|less|fewer|greater|larger|smaller|higher|lower)\\s+than\\b", 0.75),
        ("\\b(best|worst|largest|smallest|highest|lowest|most|least)\\b", 0.7),
        ("\\b(outperform(ed|s|ing)|surpass(ed|es|ing)|exceed(ed|s|ing))\\b", 0.75),
        ("\\bcompared\\s+(to|with)\\b", 0.8),
        ("\\bunlike\\b", 0.6),
    ]

    /// Hedging language that reduces claim definitiveness.
    private static let hedgeWords: Set<String> = [
        "allegedly", "reportedly", "apparently", "seemingly",
        "possibly", "perhaps", "might", "may", "could",
        "is believed to", "is thought to", "is said to",
        "sources say", "some experts", "it appears",
        "is expected to", "likely", "unlikely", "probably",
        "estimated", "approximately", "roughly", "about",
    ]

    // MARK: - Analysis

    /// Analyse article text and extract factual claims.
    /// - Parameters:
    ///   - articleTitle: Title of the article.
    ///   - articleLink: URL or identifier for the article.
    ///   - text: Full article body text.
    /// - Returns: A complete fact-check report.
    func analyse(articleTitle: String, articleLink: String, text: String) -> FactCheckReport {
        let sentences = splitSentences(text)
        var claims: [FactualClaim] = []
        var seenRanges = Set<String>()

        for (index, sentence) in sentences.enumerated() {
            let context = buildContext(sentences: sentences, index: index)
            let sentenceRange = findRange(of: sentence, in: text)

            // Check each claim type
            let detected = detectClaims(
                sentence: sentence,
                context: context,
                range: sentenceRange
            )

            for claim in detected {
                let rangeKey = "\(claim.rangeStart)-\(claim.rangeEnd)"
                if !seenRanges.contains(rangeKey) {
                    seenRanges.insert(rangeKey)
                    claims.append(claim)
                }
            }
        }

        // Compute aggregate metrics
        let hedgedCount = claims.filter { $0.isHedged }.count
        let hedgeRatio = claims.isEmpty ? 0.0 : Double(hedgedCount) / Double(claims.count)
        let sourceCount = countDistinctSources(text)
        let typeBreakdown = computeTypeBreakdown(claims)
        let credibility = computeCredibilityScore(
            claims: claims,
            hedgeRatio: hedgeRatio,
            sourceCount: sourceCount
        )

        let report = FactCheckReport(
            id: UUID().uuidString,
            articleLink: articleLink,
            articleTitle: articleTitle,
            analysedDate: Date(),
            claims: claims,
            credibilityScore: credibility,
            hedgeRatio: hedgeRatio,
            sourceCount: sourceCount,
            typeBreakdown: typeBreakdown,
            verdicts: [:]
        )

        saveReport(report)
        NotificationCenter.default.post(name: .factCheckDidUpdate, object: self)
        return report
    }

    // MARK: - Claim Detection

    private func detectClaims(sentence: String, context: String, range: (Int, Int)) -> [FactualClaim] {
        var claims: [FactualClaim] = []
        let isHedged = containsHedging(sentence)
        let entities = extractEntities(sentence)

        // Statistical claims
        for pattern in Self.statisticalPatterns {
            if matchesPattern(sentence, pattern: pattern.pattern) {
                let verifiability = ClaimType.statistical.baseVerifiability * (isHedged ? 0.8 : 1.0)
                claims.append(FactualClaim(
                    id: UUID().uuidString,
                    text: sentence.trimmingCharacters(in: .whitespacesAndNewlines),
                    context: context,
                    type: .statistical,
                    confidence: pattern.confidence,
                    verifiability: min(1.0, verifiability),
                    isHedged: isHedged,
                    entities: entities,
                    rangeStart: range.0,
                    rangeEnd: range.1
                ))
                break // one claim type per sentence to avoid noise
            }
        }

        // Quote/attribution claims
        if claims.isEmpty {
            for pattern in Self.quotePatterns {
                if matchesPattern(sentence, pattern: pattern.pattern) {
                    let verifiability = ClaimType.quote.baseVerifiability * (isHedged ? 0.8 : 1.0)
                    claims.append(FactualClaim(
                        id: UUID().uuidString,
                        text: sentence.trimmingCharacters(in: .whitespacesAndNewlines),
                        context: context,
                        type: .quote,
                        confidence: pattern.confidence,
                        verifiability: min(1.0, verifiability),
                        isHedged: isHedged,
                        entities: entities,
                        rangeStart: range.0,
                        rangeEnd: range.1
                    ))
                    break
                }
            }
        }

        // Temporal claims
        if claims.isEmpty {
            for pattern in Self.temporalPatterns {
                if matchesPattern(sentence, pattern: pattern.pattern) {
                    let verifiability = ClaimType.temporal.baseVerifiability * (isHedged ? 0.8 : 1.0)
                    claims.append(FactualClaim(
                        id: UUID().uuidString,
                        text: sentence.trimmingCharacters(in: .whitespacesAndNewlines),
                        context: context,
                        type: .temporal,
                        confidence: pattern.confidence,
                        verifiability: min(1.0, verifiability),
                        isHedged: isHedged,
                        entities: entities,
                        rangeStart: range.0,
                        rangeEnd: range.1
                    ))
                    break
                }
            }
        }

        // Comparative claims
        if claims.isEmpty {
            for pattern in Self.comparativePatterns {
                if matchesPattern(sentence, pattern: pattern.pattern) {
                    let verifiability = ClaimType.comparative.baseVerifiability * (isHedged ? 0.8 : 1.0)
                    claims.append(FactualClaim(
                        id: UUID().uuidString,
                        text: sentence.trimmingCharacters(in: .whitespacesAndNewlines),
                        context: context,
                        type: .comparative,
                        confidence: pattern.confidence,
                        verifiability: min(1.0, verifiability),
                        isHedged: isHedged,
                        entities: entities,
                        rangeStart: range.0,
                        rangeEnd: range.1
                    ))
                    break
                }
            }
        }

        // Causal claims
        if claims.isEmpty {
            for pattern in Self.causalPatterns {
                if matchesPattern(sentence, pattern: pattern.pattern) {
                    let verifiability = ClaimType.causal.baseVerifiability * (isHedged ? 0.8 : 1.0)
                    claims.append(FactualClaim(
                        id: UUID().uuidString,
                        text: sentence.trimmingCharacters(in: .whitespacesAndNewlines),
                        context: context,
                        type: .causal,
                        confidence: pattern.confidence,
                        verifiability: min(1.0, verifiability),
                        isHedged: isHedged,
                        entities: entities,
                        rangeStart: range.0,
                        rangeEnd: range.1
                    ))
                    break
                }
            }
        }

        return claims
    }

    // MARK: - Text Processing

    /// Split text into sentences using punctuation boundaries.
    private func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        let range = text.startIndex..<text.endIndex
        text.enumerateSubstrings(in: range, options: .bySentences) { substring, _, _, _ in
            if let s = substring?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                sentences.append(s)
            }
        }
        return sentences.isEmpty ? [text] : sentences
    }

    /// Build context string from surrounding sentences.
    private func buildContext(sentences: [String], index: Int) -> String {
        var parts: [String] = []
        if index > 0 { parts.append(sentences[index - 1]) }
        parts.append(sentences[index])
        if index < sentences.count - 1 { parts.append(sentences[index + 1]) }
        return parts.joined(separator: " ")
    }

    /// Find character range of a substring in the full text.
    private func findRange(of substring: String, in text: String) -> (Int, Int) {
        if let range = text.range(of: substring) {
            let start = text.distance(from: text.startIndex, to: range.lowerBound)
            let end = text.distance(from: text.startIndex, to: range.upperBound)
            return (start, end)
        }
        return (0, 0)
    }

    /// Check if text matches a regex pattern.
    private func matchesPattern(_ text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    /// Detect hedging language in a sentence.
    private func containsHedging(_ text: String) -> Bool {
        let lower = text.lowercased()
        return Self.hedgeWords.contains { lower.contains($0) }
    }

    /// Extract capitalised multi-word phrases as likely named entities.
    private func extractEntities(_ text: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: "\\b([A-Z][a-z]+(?:\\s+[A-Z][a-z]+)+)\\b",
            options: []
        ) else { return [] }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        var entities: [String] = []
        var seen = Set<String>()

        for match in matches {
            if let r = Range(match.range, in: text) {
                let entity = String(text[r])
                let key = entity.lowercased()
                if !seen.contains(key) {
                    seen.insert(key)
                    entities.append(entity)
                }
            }
        }
        return entities
    }

    /// Count distinct sources mentioned (names followed by attribution verbs).
    private func countDistinctSources(_ text: String) -> Int {
        guard let regex = try? NSRegularExpression(
            pattern: "([A-Z][a-z]+(?:\\s+[A-Z][a-z]+)*)\\s+(said|told|stated|reported|confirmed|denied|claimed|argued|explained|noted|added|warned)",
            options: []
        ) else { return 0 }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        var sources = Set<String>()

        for match in matches {
            if let r = Range(match.range(at: 1), in: text) {
                sources.insert(String(text[r]).lowercased())
            }
        }
        return sources.count
    }

    /// Compute claim type distribution.
    private func computeTypeBreakdown(_ claims: [FactualClaim]) -> [String: Int] {
        var breakdown: [String: Int] = [:]
        for claim in claims {
            breakdown[claim.type.rawValue, default: 0] += 1
        }
        return breakdown
    }

    /// Compute overall credibility score (0.0–1.0).
    /// Higher when: more sources, balanced hedge ratio, diverse claim types.
    private func computeCredibilityScore(claims: [FactualClaim], hedgeRatio: Double, sourceCount: Int) -> Double {
        guard !claims.isEmpty else { return 0.5 }

        // Source diversity (more named sources = more credible), capped at 5
        let sourceFactor = min(1.0, Double(sourceCount) / 5.0)

        // Hedging balance: too much hedging (>0.8) or none (0.0) are both flags
        let hedgeFactor: Double
        if hedgeRatio >= 0.1 && hedgeRatio <= 0.4 {
            hedgeFactor = 1.0  // healthy range
        } else if hedgeRatio < 0.1 {
            hedgeFactor = 0.7  // suspiciously definitive
        } else {
            hedgeFactor = max(0.4, 1.0 - hedgeRatio)
        }

        // Average confidence of claims
        let avgConfidence = claims.map { $0.confidence }.reduce(0, +) / Double(claims.count)

        // Claim type diversity (more types = more thorough reporting)
        let uniqueTypes = Set(claims.map { $0.type }).count
        let diversityFactor = min(1.0, Double(uniqueTypes) / 4.0)

        let score = (sourceFactor * 0.3) + (hedgeFactor * 0.25) + (avgConfidence * 0.25) + (diversityFactor * 0.2)
        return min(1.0, max(0.0, score))
    }

    // MARK: - User Verdicts

    /// Record user's verdict on a specific claim.
    func setVerdict(_ verdict: UserVerdict, forClaimId claimId: String, inReportId reportId: String) {
        var allVerdicts = loadVerdicts()
        var reportVerdicts = allVerdicts[reportId] ?? [:]
        reportVerdicts[claimId] = verdict.rawValue
        allVerdicts[reportId] = reportVerdicts
        saveVerdicts(allVerdicts)
        NotificationCenter.default.post(name: .factCheckDidUpdate, object: self)
    }

    /// Get verdicts for a report.
    func verdicts(forReportId reportId: String) -> [String: UserVerdict] {
        let allVerdicts = loadVerdicts()
        guard let reportVerdicts = allVerdicts[reportId] else { return [:] }
        var result: [String: UserVerdict] = [:]
        for (key, value) in reportVerdicts {
            if let v = UserVerdict(rawValue: value) {
                result[key] = v
            }
        }
        return result
    }

    // MARK: - Report History

    /// Get all saved fact-check reports, most recent first.
    func allReports() -> [FactCheckReport] {
        return loadReports().sorted { $0.analysedDate > $1.analysedDate }
    }

    /// Get report for a specific article.
    func report(forArticleLink link: String) -> FactCheckReport? {
        return loadReports().first { $0.articleLink == link }
    }

    /// Delete a report by ID.
    func deleteReport(id: String) {
        var reports = loadReports()
        reports.removeAll { $0.id == id }
        saveReports(reports)
    }

    /// Delete all reports.
    func clearAllReports() {
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
        UserDefaults.standard.removeObject(forKey: Self.verdictsKey)
    }

    // MARK: - Export

    /// Export a report as Markdown.
    func exportMarkdown(_ report: FactCheckReport) -> String {
        let verdicts = self.verdicts(forReportId: report.id)
        var md = "# Fact Check: \(report.articleTitle)\n\n"
        md += "**Article:** \(report.articleLink)\n"
        md += "**Analysed:** \(formatDate(report.analysedDate))\n"
        md += "**Credibility Score:** \(String(format: "%.0f", report.credibilityScore * 100))%\n"
        md += "**Claims Found:** \(report.claims.count)\n"
        md += "**Hedge Ratio:** \(String(format: "%.0f", report.hedgeRatio * 100))%\n"
        md += "**Named Sources:** \(report.sourceCount)\n\n"

        md += "## Claim Type Breakdown\n\n"
        for (type, count) in report.typeBreakdown.sorted(by: { $0.value > $1.value }) {
            md += "- **\(type)**: \(count)\n"
        }

        md += "\n## Claims (by verifiability)\n\n"
        for (i, claim) in report.claimsByVerifiability.enumerated() {
            let verdict = verdicts[claim.id]
            let verdictStr = verdict.map { " \($0.emoji) \($0.rawValue)" } ?? ""
            md += "### \(i + 1). [\(claim.type.displayName)] (confidence: \(String(format: "%.0f", claim.confidence * 100))%, verifiability: \(String(format: "%.0f", claim.verifiability * 100))%)\(verdictStr)\n\n"
            md += "> \(claim.text)\n\n"
            if claim.isHedged { md += "⚠️ Contains hedging language\n\n" }
            if !claim.entities.isEmpty { md += "**Entities:** \(claim.entities.joined(separator: ", "))\n\n" }
        }

        return md
    }

    /// Export a report as JSON.
    func exportJSON(_ report: FactCheckReport) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(report) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Persistence

    private func saveReport(_ report: FactCheckReport) {
        var reports = loadReports()
        // Replace existing report for same article
        reports.removeAll { $0.articleLink == report.articleLink }
        reports.append(report)
        saveReports(reports)
    }

    private func loadReports() -> [FactCheckReport] {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([FactCheckReport].self, from: data)) ?? []
    }

    private func saveReports(_ reports: [FactCheckReport]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(reports) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private func loadVerdicts() -> [String: [String: String]] {
        guard let data = UserDefaults.standard.data(forKey: Self.verdictsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: [String: String]].self, from: data)) ?? [:]
    }

    private func saveVerdicts(_ verdicts: [String: [String: String]]) {
        if let data = try? JSONEncoder().encode(verdicts) {
            UserDefaults.standard.set(data, forKey: Self.verdictsKey)
        }
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
