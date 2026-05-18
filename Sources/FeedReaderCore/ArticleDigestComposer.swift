//
//  ArticleDigestComposer.swift
//  FeedReaderCore
//
//  Newsletter digest composer - generates formatted digests from articles.
//  See FeedReader/ArticleDigestComposer.swift for the full app implementation.
//  This core version provides the models and basic composition logic.
//

import Foundation

/// The cadence at which a newsletter-style digest is generated.
///
/// Each case maps to a fixed lookback window (see ``DigestPeriodCore/days``)
/// used when selecting which articles belong to the current digest. The raw
/// value is a human-readable label suitable for headlines and UI strings.
public enum DigestPeriodCore: String, Codable, CaseIterable {
    /// A digest covering the last 24 hours.
    case daily = "Daily"
    /// A digest covering the last 7 days.
    case weekly = "Weekly"
    /// A digest covering the last 30 days.
    case monthly = "Monthly"

    /// Lookback window for this period, expressed in days.
    ///
    /// Useful for filtering articles by `publishedAt` when assembling a
    /// digest:
    ///
    /// ```swift
    /// let cutoff = Calendar.current.date(
    ///     byAdding: .day, value: -period.days, to: Date()
    /// )!
    /// let recent = articles.filter { $0.publishedAt >= cutoff }
    /// ```
    public var days: Int {
        switch self {
        case .daily: return 1
        case .weekly: return 7
        case .monthly: return 30
        }
    }
}

/// A single article entry in a generated digest.
///
/// `DigestEntry` is intentionally a plain value type (it conforms to
/// `Codable` so it can be persisted, transmitted as JSON, or snapshot in
/// tests). It carries only the fields needed by ``composeDigestMarkdown(title:entries:period:)``
/// and similar renderers — full ``RSSStory`` objects are deliberately not
/// referenced so digests can be hydrated from cached/archived data without
/// the original feed objects in memory.
public struct DigestEntry: Codable {
    /// Article headline, rendered as the link text in the digest.
    public let title: String
    /// Display name of the originating feed.
    ///
    /// Entries with the same `feedName` are grouped together by
    /// ``composeDigestMarkdown(title:entries:period:)``.
    public let feedName: String
    /// Canonical article URL used as the link target.
    public let url: String
    /// Short preview text shown beneath the article link.
    ///
    /// May be empty; renderers omit the snippet line when so.
    public let snippet: String
    /// Estimated reading time in whole minutes (typically from
    /// ``TextUtilities/estimateReadTime(wordCount:)``).
    public let readingMinutes: Int

    /// Creates a digest entry.
    ///
    /// All fields are stored verbatim; no escaping or trimming is performed
    /// here. Callers that emit Markdown or HTML should pre-sanitize
    /// `snippet` (in particular, strip HTML tags via
    /// ``RSSStory/stripHTML(_:)``) before constructing the entry.
    ///
    /// - Parameters:
    ///   - title: Article headline.
    ///   - feedName: Source feed display name.
    ///   - url: Article URL (should be a valid http/https link).
    ///   - snippet: Short preview text; may be empty.
    ///   - readingMinutes: Estimated reading time in minutes.
    public init(title: String, feedName: String, url: String, snippet: String, readingMinutes: Int) {
        self.title = title
        self.feedName = feedName
        self.url = url
        self.snippet = snippet
        self.readingMinutes = readingMinutes
    }
}

/// Renders a list of digest entries as a Markdown document.
///
/// Entries are grouped by ``DigestEntry/feedName`` and emitted under per-feed
/// `##` headings in alphabetical order, so the output is deterministic and
/// suitable for diff-based snapshot tests. Within a feed section, entries
/// keep their incoming order — sort `entries` before calling if you want a
/// specific within-feed ordering (for example, by publication date).
///
/// The header line records the total entry count and the digest period
/// label. Each article is rendered as a bullet point of the form:
///
/// ```markdown
/// - **[Title](url)** (N min)
///   Snippet text (omitted when empty)
/// ```
///
/// - Parameters:
///   - title: Top-level `#` heading for the digest document.
///   - entries: Articles to include. Pass an empty array to produce a
///     header-only digest.
///   - period: Cadence label embedded in the digest subheader. Defaults
///     to ``DigestPeriodCore/weekly``.
/// - Returns: A Markdown string ready to be written to disk, emailed, or
///   piped through a Markdown-to-HTML converter.
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
