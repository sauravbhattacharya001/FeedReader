//
//  ArticlePaywallDetector.swift
//  FeedReader
//
//  Detects likely paywalled articles by analyzing content signals
//  (truncated body, paywall keywords, known paywall domains).
//  Helps users know before clicking whether full content is available.
//

import Foundation

/// Analyzes articles for paywall indicators and provides a confidence score.
class ArticlePaywallDetector {
    
    static let shared = ArticlePaywallDetector()
    
    // MARK: - Types
    
    enum PaywallLikelihood: String {
        case none = "Free"
        case low = "Possibly Paywalled"
        case medium = "Likely Paywalled"
        case high = "Paywalled"
        
        var emoji: String {
            switch self {
            case .none: return "🟢"
            case .low: return "🟡"
            case .medium: return "🟠"
            case .high: return "🔴"
            }
        }
    }
    
    struct PaywallResult {
        let likelihood: PaywallLikelihood
        let score: Int // 0-100
        let reasons: [String]
    }
    
    // MARK: - Known Paywall Domains
    
    private let paywallDomains: Set<String> = [
        "wsj.com", "ft.com", "nytimes.com", "washingtonpost.com",
        "economist.com", "bloomberg.com", "barrons.com",
        "thetimes.co.uk", "telegraph.co.uk", "theathletic.com",
        "hbr.org", "newyorker.com", "wired.com",
        "theatlantic.com", "foreignaffairs.com", "stratechery.com",
        "theinformation.com", "businessinsider.com", "seekingalpha.com",
        "medium.com", "substack.com"
    ]
    
    // MARK: - Paywall Indicator Phrases
    
    private let paywallPhrases: [String] = [
        "subscribe to read", "subscribe to continue",
        "subscribers only", "premium content",
        "sign in to read", "log in to read",
        "unlock this article", "become a member",
        "free trial", "subscribe now",
        "paywall", "premium access",
        "read the full article", "continue reading",
        "this content is for", "exclusive to subscribers",
        "membership required", "upgrade to access",
        "limited access", "register to read"
    ]
    
    // MARK: - Cache
    
    private var cache: [String: PaywallResult] = [:]
    
    private init() {}
    
    // MARK: - Analysis
    
    /// Analyzes a story for paywall indicators.
    func analyze(story: Story) -> PaywallResult {
        // Check cache first
        if let cached = cache[story.link] {
            return cached
        }
        
        var score = 0
        var reasons: [String] = []
        
        // 1. Check domain against known paywall sites
        if let host = URL(string: story.link)?.host?.lowercased() {
            for domain in paywallDomains {
                if host == domain || host.hasSuffix("." + domain) {
                    score += 40
                    reasons.append("Known paywall domain: \(domain)")
                    break
                }
            }
        }
        
        // 2. Check for paywall indicator phrases in body
        let bodyLower = story.body.lowercased()
        for phrase in paywallPhrases {
            if bodyLower.contains(phrase) {
                score += 15
                reasons.append("Contains: \"\(phrase)\"")
                break // Only count once for phrase matching
            }
        }
        
        // 3. Check for truncated content (very short body relative to title)
        let wordCount = story.body.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.count
        
        if wordCount < 30 {
            score += 25
            reasons.append("Very short excerpt (\(wordCount) words)")
        } else if wordCount < 60 {
            score += 10
            reasons.append("Short excerpt (\(wordCount) words)")
        }
        
        // 4. Check for ellipsis or "..." at end (truncation signal)
        let trimmed = story.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("...") || trimmed.hasSuffix("…") ||
           trimmed.hasSuffix("[…]") || trimmed.hasSuffix("[...]") {
            score += 15
            reasons.append("Content appears truncated")
        }
        
        // 5. Check for "Continue reading" type endings
        let lastSentence = String(trimmed.suffix(100)).lowercased()
        let continueIndicators = ["continue reading", "read more", "read the rest",
                                   "full story", "click here to read"]
        for indicator in continueIndicators {
            if lastSentence.contains(indicator) {
                score += 15
                reasons.append("Ends with '\(indicator)' prompt")
                break
            }
        }
        
        // Cap score at 100
        score = min(score, 100)
        
        let likelihood: PaywallLikelihood
        switch score {
        case 0..<15:  likelihood = .none
        case 15..<35: likelihood = .low
        case 35..<60: likelihood = .medium
        default:      likelihood = .high
        }
        
        let result = PaywallResult(likelihood: likelihood, score: score, reasons: reasons)
        cache[story.link] = result
        return result
    }
    
    /// Clears the analysis cache.
    func clearCache() {
        cache.removeAll()
    }
    
    /// Returns a compact label string for display in table cells.
    func badgeText(for story: Story) -> String? {
        let result = analyze(story: story)
        guard result.likelihood != .none else { return nil }
        return "\(result.likelihood.emoji) \(result.likelihood.rawValue)"
    }
}
