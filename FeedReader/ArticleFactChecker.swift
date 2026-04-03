//
//  ArticleFactChecker.swift
//  FeedReader
//
//  Extracts factual claims from article text and analyzes them for
//  verifiability. Detects numeric claims, date/time references,
//  superlatives, absolutes, and attribution patterns. Scores each
//  claim's checkability and flags potential red flags (vague sourcing,
//  weasel words, unverifiable absolutes).
//
//  All analysis is local and heuristic-based — no network calls.
//  Useful for critical reading and media literacy.
//

import Foundation

// MARK: - Models

/// Category of a factual claim.
enum ClaimCategory: String, CaseIterable {
    case numeric = "Numeric"
    case temporal = "Temporal"
    case attribution = "Attribution"
    case comparison = "Comparison"
    case absolute = "Absolute"
    case causal = "Causal"

    var emoji: String {
        switch self {
        case .numeric: return "🔢"
        case .temporal: return "📅"
        case .attribution: return "🗣️"
        case .comparison: return "⚖️"
        case .absolute: return "‼️"
        case .causal: return "🔗"
        }
    }

    var description: String {
        switch self {
        case .numeric: return "Contains numbers, statistics, or measurements"
        case .temporal: return "References specific dates, times, or durations"
        case .attribution: return "Attributes information to a source"
        case .comparison: return "Makes a comparative or superlative claim"
        case .absolute: return "Uses absolute language (always, never, every)"
        case .causal: return "Asserts a cause-effect relationship"
        }
    }
}

/// A red flag that reduces claim credibility.
enum RedFlag: String, CaseIterable {
    case weaselWords = "Weasel Words"
    case vagueSource = "Vague Source"
    case absoluteLanguage = "Absolute Language"
    case emotionalLanguage = "Emotional Language"
    case unverifiableSuperlative = "Unverifiable Superlative"
    case roundNumber = "Suspiciously Round Number"
    case missingContext = "Missing Context"

    var emoji: String {
        switch self {
        case .weaselWords: return "🦥"
        case .vagueSource: return "🌫️"
        case .absoluteLanguage: return "🚫"
        case .emotionalLanguage: return "🔥"
        case .unverifiableSuperlative: return "🏔️"
        case .roundNumber: return "🎯"
        case .missingContext: return "❓"
        }
    }

    var advice: String {
        switch self {
        case .weaselWords: return "Look for specific attribution — who said this?"
        case .vagueSource: return "Seek the original named source or study"
        case .absoluteLanguage: return "Absolute claims are rarely true — look for exceptions"
        case .emotionalLanguage: return "Emotional framing may obscure facts — check neutral sources"
        case .unverifiableSuperlative: return "Superlatives need clear criteria and data to verify"
        case .roundNumber: return "Round numbers may be estimates — check for precise figures"
        case .missingContext: return "This claim may need surrounding context to evaluate properly"
        }
    }
}

/// Verifiability rating for a claim.
enum Verifiability: String, Comparable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"
    case opinion = "Opinion"

    var emoji: String {
        switch self {
        case .high: return "✅"
        case .medium: return "🟡"
        case .low: return "🟠"
        case .opinion: return "💭"
        }
    }

    private var sortOrder: Int {
        switch self {
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        case .opinion: return 0
        }
    }

    static func < (lhs: Verifiability, rhs: Verifiability) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

/// A single extracted claim with analysis.
struct ExtractedClaim: Equatable {
    /// The original sentence text.
    let sentence: String
    /// Zero-based index of the sentence in the article.
    let sentenceIndex: Int
    /// Categories this claim falls into.
    let categories: [ClaimCategory]
    /// Red flags detected.
    let redFlags: [RedFlag]
    /// How verifiable this claim is.
    let verifiability: Verifiability
    /// Confidence score (0.0–1.0) that this is a factual claim vs opinion.
    let factualConfidence: Double
    /// Suggested search queries to verify this claim.
    let verificationQueries: [String]
}

/// Full fact-check report for an article.
struct FactCheckReport: Equatable {
    /// Article title (if provided).
    let title: String
    /// All extracted claims.
    let claims: [ExtractedClaim]
    /// Total sentences analyzed.
    let totalSentences: Int
    /// Number of sentences identified as claims.
    var claimCount: Int { claims.count }
    /// Ratio of claims to total sentences.
    var claimDensity: Double {
        totalSentences > 0 ? Double(claimCount) / Double(totalSentences) : 0
    }
    /// Overall credibility score (0.0–1.0) based on red flag density.
    let credibilityScore: Double
    /// Distribution of claim categories.
    var categoryBreakdown: [ClaimCategory: Int] {
        var counts: [ClaimCategory: Int] = [:]
        for claim in claims {
            for cat in claim.categories {
                counts[cat, default: 0] += 1
            }
        }
        return counts
    }
    /// Distribution of red flags.
    var redFlagBreakdown: [RedFlag: Int] {
        var counts: [RedFlag: Int] = [:]
        for claim in claims {
            for flag in claim.redFlags {
                counts[flag, default: 0] += 1
            }
        }
        return counts
    }
    /// Claims sorted by lowest verifiability first (most concerning).
    var claimsByRisk: [ExtractedClaim] {
        claims.sorted { $0.verifiability < $1.verifiability }
    }
    /// Human-readable overall assessment.
    var assessment: String {
        if credibilityScore >= 0.8 {
            return "Generally well-sourced with verifiable claims"
        } else if credibilityScore >= 0.6 {
            return "Mostly factual but some claims lack clear sourcing"
        } else if credibilityScore >= 0.4 {
            return "Several claims need verification — read critically"
        } else {
            return "Many unverifiable or red-flagged claims — verify independently"
        }
    }
}

// MARK: - ArticleFactChecker

/// Heuristic fact-checker that extracts and analyzes factual claims.
final class ArticleFactChecker {

    // MARK: - Pattern Lexicons

    private static let numericPatterns: [NSRegularExpression] = {
        let patterns = [
            "\\b\\d{1,3}(?:,\\d{3})*(?:\\.\\d+)?\\s*(?:%|percent|billion|million|thousand|trillion|kg|lb|km|mi|m|ft)",
            "\\b\\d+(?:\\.\\d+)?\\s*(?:times|x|fold)\\b",
            "\\$\\s*\\d+(?:[.,]\\d+)*(?:\\s*(?:billion|million|thousand|trillion))?",
            "\\b(?:one|two|three|four|five|six|seven|eight|nine|ten)\\s+(?:billion|million|thousand|trillion)",
            "\\b\\d+(?:\\.\\d+)?\\s*(?:per\\s*cent|percentage\\s*points?)\\b"
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }
    }()

    private static let temporalPatterns: [NSRegularExpression] = {
        let patterns = [
            "\\b(?:January|February|March|April|May|June|July|August|September|October|November|December)\\s+\\d{1,2}(?:,?\\s+\\d{4})?\\b",
            "\\b\\d{4}\\b",
            "\\b(?:yesterday|today|last\\s+(?:week|month|year)|next\\s+(?:week|month|year))\\b",
            "\\b(?:in|since|before|after|during)\\s+(?:the\\s+)?\\d{4}\\b",
            "\\b\\d+\\s+(?:years?|months?|weeks?|days?|hours?)\\s+(?:ago|later|earlier)\\b"
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }
    }()

    private static let attributionPatterns: [NSRegularExpression] = {
        let patterns = [
            "\\baccording\\s+to\\b",
            "\\b(?:said|says|stated|claimed|reported|announced|confirmed|denied|argued|suggested|noted|explained)\\b",
            "\\b(?:a\\s+)?(?:study|report|survey|analysis|investigation|research|paper)\\s+(?:by|from|published|conducted|found|showed|revealed)\\b",
            "\\b(?:experts?|scientists?|researchers?|officials?|analysts?|economists?|doctors?)\\s+(?:say|said|believe|warn|predict|estimate)\\b"
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }
    }()

    private static let comparisonWords = Set([
        "more", "less", "greater", "fewer", "better", "worse", "larger",
        "smaller", "higher", "lower", "fastest", "slowest", "biggest",
        "smallest", "most", "least", "best", "worst", "largest",
        "highest", "lowest", "longest", "shortest", "strongest",
        "weakest", "richest", "poorest", "oldest", "youngest",
        "compared to", "versus", "than", "outperform", "surpass",
        "exceed", "trail", "lag behind", "outpace"
    ])

    private static let absoluteWords = Set([
        "always", "never", "every", "all", "none", "no one",
        "everyone", "everything", "nothing", "nobody", "impossible",
        "guaranteed", "certainly", "definitely", "undeniably",
        "unquestionably", "without exception", "in every case",
        "without a doubt", "proven", "irrefutable"
    ])

    private static let causalPatterns: [NSRegularExpression] = {
        let patterns = [
            "\\b(?:because|cause[sd]?|led\\s+to|result(?:s|ed)?\\s+in|due\\s+to|thanks\\s+to|owing\\s+to)\\b",
            "\\b(?:therefore|consequently|as\\s+a\\s+result|hence|thus|accordingly)\\b",
            "\\b(?:leads?\\s+to|contributes?\\s+to|triggers?|sparks?|drives?|fuels?)\\b"
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }
    }()

    private static let weaselWords = Set([
        "some say", "many people", "some experts", "it is believed",
        "it is said", "sources say", "reportedly", "allegedly",
        "it is thought", "some argue", "critics say", "observers note",
        "many believe", "it has been suggested", "questions have been raised",
        "concerns have been raised", "there are those who"
    ])

    private static let vagueSourcePhrases = Set([
        "sources say", "sources close to", "unnamed sources",
        "anonymous sources", "people familiar with", "insiders say",
        "a source said", "those in the know", "informed sources",
        "senior officials", "top officials", "industry sources"
    ])

    private static let emotionalWords = Set([
        "shocking", "horrifying", "devastating", "outrageous",
        "incredible", "unbelievable", "stunning", "alarming",
        "terrifying", "heartbreaking", "disgusting", "appalling",
        "explosive", "bombshell", "unprecedented", "catastrophic",
        "miraculous", "revolutionary", "groundbreaking", "sensational",
        "dramatic", "massive", "enormous", "staggering"
    ])

    private static let opinionIndicators = Set([
        "i think", "i believe", "in my opinion", "arguably",
        "perhaps", "maybe", "possibly", "likely", "probably",
        "it seems", "appears to", "might be", "could be",
        "should be", "ought to", "it is clear that",
        "obviously", "clearly", "of course", "needless to say"
    ])

    // MARK: - Public API

    /// Analyze article text and return a full fact-check report.
    static func analyze(text: String, title: String = "") -> FactCheckReport {
        let sentences = splitSentences(text)
        var claims: [ExtractedClaim] = []

        for (index, sentence) in sentences.enumerated() {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.split(separator: " ").count >= 5 else { continue }

            let categories = detectCategories(trimmed)
            guard !categories.isEmpty else { continue }

            let redFlags = detectRedFlags(trimmed)
            let isOpinion = detectOpinion(trimmed)
            let factualConfidence = computeFactualConfidence(
                categories: categories, redFlags: redFlags, isOpinion: isOpinion
            )
            let verifiability = computeVerifiability(
                categories: categories, redFlags: redFlags,
                isOpinion: isOpinion, factualConfidence: factualConfidence
            )
            let queries = generateVerificationQueries(
                sentence: trimmed, title: title, categories: categories
            )

            claims.append(ExtractedClaim(
                sentence: trimmed,
                sentenceIndex: index,
                categories: categories,
                redFlags: redFlags,
                verifiability: verifiability,
                factualConfidence: factualConfidence,
                verificationQueries: queries
            ))
        }

        let credibility = computeCredibility(claims: claims, totalSentences: sentences.count)

        return FactCheckReport(
            title: title,
            claims: claims,
            totalSentences: sentences.count,
            credibilityScore: credibility
        )
    }

    /// Quick check: returns just the credibility score (0.0–1.0).
    static func quickScore(text: String) -> Double {
        let report = analyze(text: text)
        return report.credibilityScore
    }

    /// Returns claims sorted by most concerning (lowest verifiability, most red flags).
    static func topConcerns(text: String, title: String = "", limit: Int = 5) -> [ExtractedClaim] {
        let report = analyze(text: text, title: title)
        return Array(report.claimsByRisk.prefix(limit))
    }

    /// Format a report as a readable text summary.
    static func formatReport(_ report: FactCheckReport) -> String {
        var lines: [String] = []

        lines.append("═══════════════════════════════════════")
        lines.append("  📋 FACT-CHECK REPORT")
        if !report.title.isEmpty {
            lines.append("  \"\(report.title)\"")
        }
        lines.append("═══════════════════════════════════════")
        lines.append("")
        lines.append("📊 Overview")
        lines.append("  Sentences analyzed: \(report.totalSentences)")
        lines.append("  Claims extracted:   \(report.claimCount)")
        lines.append("  Claim density:      \(String(format: "%.0f%%", report.claimDensity * 100))")
        lines.append("  Credibility score:  \(String(format: "%.0f%%", report.credibilityScore * 100))")
        lines.append("  Assessment:         \(report.assessment)")
        lines.append("")

        // Category breakdown
        let breakdown = report.categoryBreakdown
        if !breakdown.isEmpty {
            lines.append("📂 Claim Categories")
            for cat in ClaimCategory.allCases {
                if let count = breakdown[cat] {
                    lines.append("  \(cat.emoji) \(cat.rawValue): \(count)")
                }
            }
            lines.append("")
        }

        // Red flag summary
        let flags = report.redFlagBreakdown
        if !flags.isEmpty {
            lines.append("🚩 Red Flags Found")
            for flag in RedFlag.allCases {
                if let count = flags[flag] {
                    lines.append("  \(flag.emoji) \(flag.rawValue): \(count)")
                }
            }
            lines.append("")
        }

        // Top concerns
        let concerns = report.claimsByRisk.prefix(5)
        if !concerns.isEmpty {
            lines.append("⚠️  Top Concerns")
            lines.append("───────────────────────────────────────")
            for (i, claim) in concerns.enumerated() {
                lines.append("\(i + 1). \(claim.verifiability.emoji) [\(claim.verifiability.rawValue)]")
                lines.append("   \"\(truncate(claim.sentence, maxLength: 120))\"")
                if !claim.redFlags.isEmpty {
                    let flagStr = claim.redFlags.map { "\($0.emoji) \($0.rawValue)" }.joined(separator: ", ")
                    lines.append("   Flags: \(flagStr)")
                }
                if let query = claim.verificationQueries.first {
                    lines.append("   Search: \"\(query)\"")
                }
                lines.append("")
            }
        }

        lines.append("═══════════════════════════════════════")
        return lines.joined(separator: "\n")
    }

    // MARK: - Internal Analysis

    private static func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        let range = text.startIndex..<text.endIndex
        text.enumerateSubstrings(in: range, options: .bySentences) { substring, _, _, _ in
            if let s = substring {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    sentences.append(trimmed)
                }
            }
        }
        if sentences.isEmpty && !text.isEmpty {
            // Fallback: split on period
            sentences = text.components(separatedBy: ". ")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return sentences
    }

    private static func detectCategories(_ sentence: String) -> [ClaimCategory] {
        var cats: [ClaimCategory] = []
        let lower = sentence.lowercased()
        let nsRange = NSRange(lower.startIndex..., in: lower)

        // Numeric
        for pattern in numericPatterns {
            if pattern.firstMatch(in: lower, range: nsRange) != nil {
                cats.append(.numeric)
                break
            }
        }

        // Temporal
        for pattern in temporalPatterns {
            if pattern.firstMatch(in: lower, range: nsRange) != nil {
                cats.append(.temporal)
                break
            }
        }

        // Attribution
        for pattern in attributionPatterns {
            if pattern.firstMatch(in: lower, range: nsRange) != nil {
                cats.append(.attribution)
                break
            }
        }

        // Comparison
        for word in comparisonWords {
            if lower.contains(word) {
                cats.append(.comparison)
                break
            }
        }

        // Absolute
        for word in absoluteWords {
            if lower.contains(word) {
                cats.append(.absolute)
                break
            }
        }

        // Causal
        for pattern in causalPatterns {
            if pattern.firstMatch(in: lower, range: nsRange) != nil {
                cats.append(.causal)
                break
            }
        }

        return cats
    }

    private static func detectRedFlags(_ sentence: String) -> [RedFlag] {
        var flags: [RedFlag] = []
        let lower = sentence.lowercased()

        // Weasel words
        for phrase in weaselWords {
            if lower.contains(phrase) {
                flags.append(.weaselWords)
                break
            }
        }

        // Vague source
        for phrase in vagueSourcePhrases {
            if lower.contains(phrase) {
                flags.append(.vagueSource)
                break
            }
        }

        // Absolute language
        for word in absoluteWords {
            if lower.contains(word) {
                flags.append(.absoluteLanguage)
                break
            }
        }

        // Emotional language
        for word in emotionalWords {
            if lower.contains(word) {
                flags.append(.emotionalLanguage)
                break
            }
        }

        // Unverifiable superlative
        let superlatives = ["the most", "the best", "the worst", "the first",
                           "the only", "the biggest", "the largest", "the greatest"]
        for s in superlatives {
            if lower.contains(s) {
                // Check if there's a source/citation nearby
                var hasSource = false
                for pattern in attributionPatterns {
                    let nsRange = NSRange(lower.startIndex..., in: lower)
                    if pattern.firstMatch(in: lower, range: nsRange) != nil {
                        hasSource = true
                        break
                    }
                }
                if !hasSource {
                    flags.append(.unverifiableSuperlative)
                }
                break
            }
        }

        // Suspiciously round numbers
        if let regex = try? NSRegularExpression(pattern: "\\b(\\d+)(?:,000)+\\b|\\b\\d+0{3,}\\b", options: []) {
            let nsRange = NSRange(lower.startIndex..., in: lower)
            if regex.firstMatch(in: lower, range: nsRange) != nil {
                flags.append(.roundNumber)
            }
        }

        return flags
    }

    private static func detectOpinion(_ sentence: String) -> Bool {
        let lower = sentence.lowercased()
        for indicator in opinionIndicators {
            if lower.contains(indicator) {
                return true
            }
        }
        return false
    }

    private static func computeFactualConfidence(
        categories: [ClaimCategory], redFlags: [RedFlag], isOpinion: Bool
    ) -> Double {
        var score = 0.5

        // Categories boost factual confidence
        if categories.contains(.numeric) { score += 0.15 }
        if categories.contains(.temporal) { score += 0.10 }
        if categories.contains(.attribution) { score += 0.15 }

        // Red flags reduce it
        score -= Double(redFlags.count) * 0.08

        // Opinion is a strong signal
        if isOpinion { score -= 0.25 }

        return max(0.0, min(1.0, score))
    }

    private static func computeVerifiability(
        categories: [ClaimCategory], redFlags: [RedFlag],
        isOpinion: Bool, factualConfidence: Double
    ) -> Verifiability {
        if isOpinion { return .opinion }

        let hasConcreteData = categories.contains(.numeric) || categories.contains(.temporal)
        let hasAttribution = categories.contains(.attribution)
        let flagCount = redFlags.count

        if hasConcreteData && hasAttribution && flagCount == 0 {
            return .high
        } else if hasConcreteData || (hasAttribution && flagCount <= 1) {
            return .medium
        } else if flagCount >= 2 || categories.contains(.absolute) {
            return .low
        } else {
            return factualConfidence >= 0.5 ? .medium : .low
        }
    }

    private static func generateVerificationQueries(
        sentence: String, title: String, categories: [ClaimCategory]
    ) -> [String] {
        var queries: [String] = []
        let words = sentence.split(separator: " ").map(String.init)

        // Extract key noun phrases (capitalized words that aren't sentence starters)
        let properNouns = words.enumerated().compactMap { (i, word) -> String? in
            guard i > 0,
                  let first = word.first, first.isUppercase,
                  word.count > 2 else { return nil }
            return word.trimmingCharacters(in: .punctuationCharacters)
        }

        // Build a focused query from proper nouns + key numbers
        let numbers = words.filter { $0.rangeOfCharacter(from: .decimalDigits) != nil }
            .prefix(2).map { $0.trimmingCharacters(in: .punctuationCharacters) }

        if !properNouns.isEmpty {
            var q = properNouns.prefix(3).joined(separator: " ")
            if let num = numbers.first {
                q += " \(num)"
            }
            queries.append(q)
        }

        // Add a title-based query if available
        if !title.isEmpty && !properNouns.isEmpty {
            queries.append("\(title) \(properNouns.first ?? "") fact check")
        }

        // Category-specific query
        if categories.contains(.numeric) {
            let numContext = numbers.joined(separator: " ")
            if !numContext.isEmpty {
                queries.append("\(numContext) \(properNouns.prefix(2).joined(separator: " ")) statistics")
            }
        }

        return Array(Set(queries)).sorted()
    }

    private static func computeCredibility(claims: [ExtractedClaim], totalSentences: Int) -> Double {
        guard !claims.isEmpty else { return 1.0 } // No claims = nothing to flag

        let totalFlags = claims.reduce(0) { $0 + $1.redFlags.count }
        let avgConfidence = claims.reduce(0.0) { $0 + $1.factualConfidence } / Double(claims.count)
        let flagPenalty = min(0.5, Double(totalFlags) * 0.03)

        let lowVerifiabilityClaims = claims.filter { $0.verifiability == .low }.count
        let lowPenalty = min(0.3, Double(lowVerifiabilityClaims) * 0.05)

        return max(0.0, min(1.0, avgConfidence - flagPenalty - lowPenalty + 0.15))
    }

    private static func truncate(_ text: String, maxLength: Int) -> String {
        if text.count <= maxLength { return text }
        let end = text.index(text.startIndex, offsetBy: maxLength - 3)
        return String(text[..<end]) + "..."
    }
}
