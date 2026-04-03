//
//  ArticleDigestComposer.swift
//  FeedReaderCore
//
//  Newsletter digest composer — generates formatted digests from articles.
//  See FeedReader/ArticleDigestComposer.swift for the full app implementation.
//  This core version provides the models and basic composition logic.
//

import Foundation

/// Digest period for newsletter frequency.
public enum DigestPeriodCore: String, Codable, CaseIterable {
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
    
    public var days: Int {
        switch self {
        case .daily: return 1
        case .weekly: return 7
        case .monthly: return 30
        }
    }
}

/// A single article entry in a digest.
public struct DigestEntry: Codable {
    public let title: String
    public let feedName: String
    public let url: String
    public let snippet: String
    public let readingMinutes: Int
    
    public init(title: String, feedName: String, url: String, snippet: String, readingMinutes: Int) {
        self.title = title
        self.feedName = feedName
        self.url = url
        self.snippet = snippet
        self.readingMinutes = readingMinutes
    }
}

/// Compose a simple markdown digest from entries.
public func composeDigestMarkdown(title: String, entries: [DigestEntry], period: DigestPeriodCore = .weekly) -> String {
    var md = "# \(title)\n\n"
    md += "*\(entries.count) articles · \(period.rawValue) digest*\n\n---\n\n"
    
    let grouped = Dictionary(grouping: entries) { $0.feedName }
    for feedName in grouped.keys.sorted() {
        md += "## \(feedName)\n\n"
        for entry in grouped[feedName] ?? [] {
            md += "- **[\(entry.title)](\(entry.url))** (\(entry.readingMinutes) min)\n"
            if !entry.snippet.isEmpty {
                md += "  \(entry.snippet)\n"
            }
            md += "\n"
        }
    }
    
    return md
}
