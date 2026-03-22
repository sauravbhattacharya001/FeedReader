//
//  SourceCredibilityScorer.swift
//  FeedReader
//
//  Evaluates the credibility of article sources by analyzing domain
//  reputation signals, content quality indicators, and transparency
//  patterns. Produces a composite credibility score (0-100) with
//  per-dimension breakdowns and actionable insights.
//
//  All methods are pure and stateless — no external API calls.
//  Uses curated domain lists and heuristic text analysis.
//

import Foundation

// MARK: - Result Models

/// Overall credibility assessment for an article source.
struct CredibilityReport: Codable, Equatable {
    let domain: String
    let overallScore: Int               // 0-100
    let tier: CredibilityTier
    let dimensions: [CredibilityDimension]
    let flags: [CredibilityFlag]
    let summary: String
    let checkedAt: Date
}

/// Credibility tier derived from overall score.
enum CredibilityTier: String, Codable, CaseIterable {
    case high = "High Credibility"
    case moderate = "Moderate Credibility"
    case mixed = "Mixed Credibility"
    case low = "Low Credibility"
    case unknown = "Unknown"

    var emoji: String {
        switch self {
        case .high: return "🟢"
        case .moderate: return "🔵"
        case .mixed: return "🟡"
        case .low: return "🔴"
        case .unknown: return "⚪"
        }
    }

    static func from(score: Int) -> CredibilityTier {
        switch score {
        case 80...100: return .high
        case 60..<80: return .moderate
        case 40..<60: return .mixed
        case 0..<40: return .low
        default: return .unknown
        }
    }
}

/// A scored dimension of credibility.
struct CredibilityDimension: Codable, Equatable {
    let name: String
    let score: Int           // 0-100
    let weight: Double       // 0.0-1.0
    let details: String
}

/// A specific credibility concern or positive signal.
struct CredibilityFlag: Codable, Equatable {
    let indicator: String
    let impact: CredibilityImpact
    let explanation: String
}

enum CredibilityImpact: String, Codable {
    case positive = "Positive"
    case neutral = "Neutral"
    case negative = "Negative"
    case critical = "Critical"

    var emoji: String {
        switch self {
        case .positive: return "✅"
        case .neutral: return "ℹ️"
        case .negative: return "⚠️"
        case .critical: return "🚨"
        }
    }
}

// MARK: - Source Credibility Scorer

final class SourceCredibilityScorer {

    // MARK: - Public API

    /// Analyze the credibility of an article given its URL and body text.
    static func evaluate(url: String, title: String, body: String, feedName: String? = nil) -> CredibilityReport {
        let domain = extractDomain(from: url)
        var flags: [CredibilityFlag] = []

        // Dimension 1: Domain Reputation (weight 0.35)
        let domainResult = evaluateDomainReputation(domain: domain, flags: &flags)

        // Dimension 2: Content Transparency (weight 0.25)
        let transparencyResult = evaluateTransparency(body: body, flags: &flags)

        // Dimension 3: Writing Quality (weight 0.20)
        let qualityResult = evaluateWritingQuality(title: title, body: body, flags: &flags)

        // Dimension 4: Source Attribution (weight 0.20)
        let attributionResult = evaluateAttribution(body: body, flags: &flags)

        let dimensions = [domainResult, transparencyResult, qualityResult, attributionResult]

        let overallScore = dimensions.reduce(0.0) { $0 + Double($1.score) * $1.weight }
        let clampedScore = max(0, min(100, Int(overallScore.rounded())))
        let tier = CredibilityTier.from(score: clampedScore)

        let summary = buildSummary(domain: domain, tier: tier, score: clampedScore, flags: flags)

        return CredibilityReport(
            domain: domain,
            overallScore: clampedScore,
            tier: tier,
            dimensions: dimensions,
            flags: flags,
            summary: summary,
            checkedAt: Date()
        )
    }

    /// Quick credibility check — returns just the tier.
    static func quickCheck(url: String) -> CredibilityTier {
        let domain = extractDomain(from: url)
        var flags: [CredibilityFlag] = []
        let domainResult = evaluateDomainReputation(domain: domain, flags: &flags)
        return CredibilityTier.from(score: domainResult.score)
    }

    // MARK: - Domain Reputation

    private static func evaluateDomainReputation(domain: String, flags: inout [CredibilityFlag]) -> CredibilityDimension {
        var score = 50 // baseline for unknown domains

        let normalized = domain.lowercased()

        if highCredibilityDomains.contains(where: { normalized.hasSuffix($0) }) {
            score = 90
            flags.append(CredibilityFlag(
                indicator: "Established News Source",
                impact: .positive,
                explanation: "\(domain) is a well-known, established news organization."
            ))
        } else if moderateCredibilityDomains.contains(where: { normalized.hasSuffix($0) }) {
            score = 65
            flags.append(CredibilityFlag(
                indicator: "Known Source",
                impact: .neutral,
                explanation: "\(domain) is a recognized source with editorial perspective."
            ))
        } else if lowCredibilityDomains.contains(where: { normalized.hasSuffix($0) }) {
            score = 15
            flags.append(CredibilityFlag(
                indicator: "Unreliable Source",
                impact: .critical,
                explanation: "\(domain) has a history of publishing misleading content."
            ))
        }

        // Check for suspicious domain patterns
        if isSuspiciousDomain(normalized) {
            score = max(10, score - 30)
            flags.append(CredibilityFlag(
                indicator: "Suspicious Domain Pattern",
                impact: .negative,
                explanation: "Domain name mimics established sources or uses deceptive patterns."
            ))
        }

        // Bonus for .gov, .edu domains
        if normalized.hasSuffix(".gov") || normalized.hasSuffix(".edu") {
            score = min(100, score + 15)
            flags.append(CredibilityFlag(
                indicator: "Institutional Domain",
                impact: .positive,
                explanation: "Government or educational institution domain."
            ))
        }

        return CredibilityDimension(
            name: "Domain Reputation",
            score: score,
            weight: 0.35,
            details: "Based on domain recognition, history, and institutional affiliation."
        )
    }

    // MARK: - Content Transparency

    private static func evaluateTransparency(body: String, flags: inout [CredibilityFlag]) -> CredibilityDimension {
        var score = 50
        let lower = body.lowercased()

        // Check for author attribution
        let authorPatterns = ["by ", "written by", "reported by", "author:", "correspondent"]
        let hasAuthor = authorPatterns.contains { lower.contains($0) }
        if hasAuthor {
            score += 15
            flags.append(CredibilityFlag(
                indicator: "Author Attributed",
                impact: .positive,
                explanation: "Article credits a specific author or reporter."
            ))
        } else {
            score -= 10
            flags.append(CredibilityFlag(
                indicator: "No Author Attribution",
                impact: .negative,
                explanation: "No visible author credit — harder to verify accountability."
            ))
        }

        // Check for date references (indicates timeliness)
        let datePatterns = ["published", "updated", "modified", "posted on"]
        let hasDate = datePatterns.contains { lower.contains($0) }
        if hasDate {
            score += 10
        }

        // Check for correction notices (positive — shows accountability)
        let correctionPatterns = ["correction:", "editor's note:", "update:", "clarification:"]
        if correctionPatterns.contains(where: { lower.contains($0) }) {
            score += 10
            flags.append(CredibilityFlag(
                indicator: "Correction Notice Present",
                impact: .positive,
                explanation: "Article includes corrections or editor's notes, showing accountability."
            ))
        }

        // Check for disclosure language
        let disclosurePatterns = ["disclosure:", "conflict of interest", "sponsored", "paid content", "advertisement", "affiliate"]
        if disclosurePatterns.contains(where: { lower.contains($0) }) {
            flags.append(CredibilityFlag(
                indicator: "Disclosure Present",
                impact: .neutral,
                explanation: "Article contains sponsorship or conflict-of-interest disclosure."
            ))
        }

        return CredibilityDimension(
            name: "Content Transparency",
            score: max(0, min(100, score)),
            weight: 0.25,
            details: "Evaluates author attribution, dating, corrections, and disclosures."
        )
    }

    // MARK: - Writing Quality

    private static func evaluateWritingQuality(title: String, body: String, flags: inout [CredibilityFlag]) -> CredibilityDimension {
        var score = 60

        // Clickbait detection in title
        let clickbaitPatterns = [
            "you won't believe", "shocking", "mind-blowing", "jaw-dropping",
            "what happens next", "this one trick", "doctors hate",
            "number \\d+ will", "is dead", "exposed", "bombshell",
            "destroyed", "goes viral", "breaks the internet"
        ]
        let titleLower = title.lowercased()
        let clickbaitHits = clickbaitPatterns.filter { titleLower.contains($0) }
        if !clickbaitHits.isEmpty {
            score -= 20
            flags.append(CredibilityFlag(
                indicator: "Clickbait Title",
                impact: .negative,
                explanation: "Title uses sensationalist language: \(clickbaitHits.joined(separator: ", "))"
            ))
        }

        // ALL CAPS detection
        let words = title.split(separator: " ")
        let capsWords = words.filter { $0.count > 3 && $0 == $0.uppercased() }
        if capsWords.count > 2 {
            score -= 10
            flags.append(CredibilityFlag(
                indicator: "Excessive Capitalization",
                impact: .negative,
                explanation: "Title uses excessive ALL CAPS, suggesting sensationalism."
            ))
        }

        // Excessive punctuation in title
        let exclamationCount = title.filter { $0 == "!" }.count
        let questionCount = title.filter { $0 == "?" }.count
        if exclamationCount > 1 || questionCount > 2 {
            score -= 10
            flags.append(CredibilityFlag(
                indicator: "Excessive Punctuation",
                impact: .negative,
                explanation: "Title uses excessive punctuation marks."
            ))
        }

        // Body length check — very short articles may lack substance
        let wordCount = body.split(separator: " ").count
        if wordCount > 300 {
            score += 10
        } else if wordCount < 100 {
            score -= 15
            flags.append(CredibilityFlag(
                indicator: "Very Short Article",
                impact: .negative,
                explanation: "Article is unusually short (\(wordCount) words), may lack depth."
            ))
        }

        return CredibilityDimension(
            name: "Writing Quality",
            score: max(0, min(100, score)),
            weight: 0.20,
            details: "Analyzes title sensationalism, capitalization, punctuation, and article depth."
        )
    }

    // MARK: - Source Attribution

    private static func evaluateAttribution(body: String, flags: inout [CredibilityFlag]) -> CredibilityDimension {
        var score = 50
        let lower = body.lowercased()

        // Check for sourcing language
        let sourcingPatterns = [
            "according to", "sources say", "a spokesperson",
            "the report states", "data shows", "research found",
            "study published", "cited by", "confirmed by",
            "official statement", "press release"
        ]
        let sourcingHits = sourcingPatterns.filter { lower.contains($0) }
        if sourcingHits.count >= 3 {
            score += 25
            flags.append(CredibilityFlag(
                indicator: "Well-Sourced",
                impact: .positive,
                explanation: "Article references multiple sources and attributions."
            ))
        } else if sourcingHits.count >= 1 {
            score += 10
        } else {
            score -= 15
            flags.append(CredibilityFlag(
                indicator: "Minimal Attribution",
                impact: .negative,
                explanation: "Article makes claims without citing sources."
            ))
        }

        // Check for hedging / qualifying language (good sign)
        let hedgingPatterns = ["allegedly", "reportedly", "it is unclear", "could not be verified", "claims"]
        let hedgingHits = hedgingPatterns.filter { lower.contains($0) }
        if hedgingHits.count >= 2 {
            score += 10
            flags.append(CredibilityFlag(
                indicator: "Appropriate Hedging",
                impact: .positive,
                explanation: "Article uses qualifying language for unverified claims."
            ))
        }

        // Check for links/references (indicates sourcing)
        let linkPattern = try? NSRegularExpression(pattern: "https?://", options: [])
        let linkCount = linkPattern?.numberOfMatches(in: body, options: [], range: NSRange(body.startIndex..., in: body)) ?? 0
        if linkCount >= 3 {
            score += 10
        }

        return CredibilityDimension(
            name: "Source Attribution",
            score: max(0, min(100, score)),
            weight: 0.20,
            details: "Evaluates citation practices, sourcing language, and reference links."
        )
    }

    // MARK: - Summary Builder

    private static func buildSummary(domain: String, tier: CredibilityTier, score: Int, flags: [CredibilityFlag]) -> String {
        let criticalCount = flags.filter { $0.impact == .critical }.count
        let negativeCount = flags.filter { $0.impact == .negative }.count
        let positiveCount = flags.filter { $0.impact == .positive }.count

        var parts: [String] = []
        parts.append("\(tier.emoji) \(domain) — \(tier.rawValue) (Score: \(score)/100)")

        if criticalCount > 0 {
            parts.append("⚠️ \(criticalCount) critical concern(s) detected.")
        }
        if positiveCount > negativeCount {
            parts.append("Content shows good journalistic practices.")
        } else if negativeCount > positiveCount {
            parts.append("Content has several quality concerns — read critically.")
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Domain Utilities

    static func extractDomain(from urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host else {
            // Fallback: try to parse manually
            let cleaned = urlString
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
            return String(cleaned.split(separator: "/").first ?? Substring(urlString))
        }
        // Strip www. prefix
        if host.hasPrefix("www.") {
            return String(host.dropFirst(4))
        }
        return host
    }

    private static func isSuspiciousDomain(_ domain: String) -> Bool {
        // Domains that mimic real news with extra words
        let suspiciousPatterns = [
            "news24", "daily-", "-news.com", "-times.com", "-post.net",
            "truth", "patriot", "freedom", "liberty", "eagle"
        ]
        let mimicTargets = ["cnn", "bbc", "nyt", "fox", "abc", "nbc", "reuters"]

        // Check for typosquatting of known brands
        for target in mimicTargets {
            if domain.contains(target) && !highCredibilityDomains.contains(where: { domain.hasSuffix($0) }) {
                return true
            }
        }

        return suspiciousPatterns.filter { domain.contains($0) }.count >= 2
    }

    // MARK: - Domain Lists (curated)

    /// Well-established news organizations with editorial standards.
    private static let highCredibilityDomains: [String] = [
        "reuters.com", "apnews.com", "bbc.com", "bbc.co.uk",
        "nytimes.com", "washingtonpost.com", "theguardian.com",
        "npr.org", "pbs.org", "nature.com", "science.org",
        "economist.com", "ft.com", "wsj.com", "bloomberg.com",
        "propublica.org", "theatlantic.com", "newyorker.com",
        "scientificamerican.com", "nationalgeographic.com",
        "arstechnica.com", "techcrunch.com", "wired.com",
        "snopes.com", "factcheck.org", "politifact.com"
    ]

    /// Sources with known editorial slant but generally factual.
    private static let moderateCredibilityDomains: [String] = [
        "cnn.com", "foxnews.com", "msnbc.com", "nbcnews.com",
        "abcnews.go.com", "cbsnews.com", "usatoday.com",
        "huffpost.com", "dailymail.co.uk", "nypost.com",
        "vice.com", "vox.com", "buzzfeednews.com",
        "thehill.com", "politico.com", "axios.com"
    ]

    /// Sources known for misinformation or extremely poor editorial standards.
    private static let lowCredibilityDomains: [String] = [
        "infowars.com", "naturalnews.com", "beforeitsnews.com",
        "worldnewsdailyreport.com", "theonion.com", "babylonbee.com",
        "dailysquib.co.uk", "newsthump.com"
    ]
}
