//
//  DigestGenerator.swift
//  FeedReader
//
//  Generates formatted reading digests (like personal newsletters)
//  from reading history. Supports configurable time windows,
//  grouping by feed, and multiple output formats (plain text,
//  Markdown, HTML). Integrates with ReadingHistoryManager for
//  source data and ReadingStatsManager for aggregate stats.
//

import Foundation

// MARK: - Shared Time Formatting

/// Format a duration in seconds into a human-readable label.
/// Shared by DigestArticle, FeedGroup, DigestResult, and formatters.
func formatReadingTimeLabel(_ seconds: Double) -> String {
    if seconds < 60 { return "<1 min" }
    let minutes = Int(seconds / 60)
    if minutes < 60 { return "\(minutes) min" }
    let hours = minutes / 60
    let remainingMin = minutes % 60
    if remainingMin == 0 { return "\(hours)h" }
    return "\(hours)h \(remainingMin)m"
}

// MARK: - DigestPeriod

/// Time window for digest generation.
enum DigestPeriod: Int, CaseIterable {
    case today = 0
    case yesterday = 1
    case thisWeek = 2
    case lastWeek = 3
    case thisMonth = 4
    case last7Days = 5
    case last30Days = 6
    case custom = 7
    
    var label: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .thisWeek: return "This Week"
        case .lastWeek: return "Last Week"
        case .thisMonth: return "This Month"
        case .last7Days: return "Last 7 Days"
        case .last30Days: return "Last 30 Days"
        case .custom: return "Custom"
        }
    }
    
    /// Computes the date range for this period relative to the given reference date.
    func dateRange(relativeTo now: Date = Date(), calendar: Calendar = .current) -> (start: Date, end: Date) {
        switch self {
        case .today:
            let start = calendar.startOfDay(for: now)
            return (start, now)
        case .yesterday:
            let todayStart = calendar.startOfDay(for: now)
            let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!
            return (yesterdayStart, todayStart)
        case .thisWeek:
            var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            let weekStart = calendar.date(from: components)!
            return (weekStart, now)
        case .lastWeek:
            var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            let thisWeekStart = calendar.date(from: components)!
            let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart)!
            return (lastWeekStart, thisWeekStart)
        case .thisMonth:
            var components = calendar.dateComponents([.year, .month], from: now)
            let monthStart = calendar.date(from: components)!
            return (monthStart, now)
        case .last7Days:
            let start = calendar.date(byAdding: .day, value: -7, to: now)!
            return (start, now)
        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -30, to: now)!
            return (start, now)
        case .custom:
            // Default to last 7 days for custom
            let start = calendar.date(byAdding: .day, value: -7, to: now)!
            return (start, now)
        }
    }
}

// MARK: - DigestFormat

/// Output format for the generated digest.
enum DigestFormat: Int, CaseIterable {
    case plainText = 0
    case markdown = 1
    case html = 2
    
    var label: String {
        switch self {
        case .plainText: return "Plain Text"
        case .markdown: return "Markdown"
        case .html: return "HTML"
        }
    }
    
    var fileExtension: String {
        switch self {
        case .plainText: return "txt"
        case .markdown: return "md"
        case .html: return "html"
        }
    }
}

// MARK: - DigestOptions

/// Configuration for digest generation.
struct DigestOptions {
    /// Time period for the digest.
    var period: DigestPeriod = .last7Days
    
    /// Custom date range (used when period == .custom).
    var customStart: Date?
    var customEnd: Date?
    
    /// Output format.
    var format: DigestFormat = .markdown
    
    /// Whether to group articles by feed source.
    var groupByFeed: Bool = true
    
    /// Whether to include reading time stats per article.
    var includeReadingTime: Bool = true
    
    /// Whether to include an overview stats section.
    var includeStats: Bool = true
    
    /// Maximum articles to include (0 = unlimited).
    var maxArticles: Int = 0
    
    /// Sort order within groups.
    var sortOrder: SortOrder = .newestFirst
    
    enum SortOrder: Int {
        case newestFirst = 0
        case oldestFirst = 1
        case mostTimeSpent = 2
        case alphabetical = 3
    }
    
    /// Effective date range, resolving custom dates.
    func effectiveDateRange(relativeTo now: Date = Date()) -> (start: Date, end: Date) {
        if period == .custom, let start = customStart, let end = customEnd {
            return (start, end)
        }
        return period.dateRange(relativeTo: now)
    }
}

// MARK: - DigestArticle

/// A digest-ready representation of a read article.
struct DigestArticle {
    let title: String
    let link: String
    let feedName: String
    let readAt: Date
    let timeSpentSeconds: Double
    let visitCount: Int
    let scrollProgress: Double
    
    /// Formatted reading time string.
    var readingTimeLabel: String {
        return formatReadingTimeLabel(timeSpentSeconds)
    }
    
    /// Formatted scroll progress as percentage.
    var progressLabel: String {
        return "\(Int(scrollProgress * 100))%"
    }
}

// MARK: - FeedGroup

/// Articles grouped by their source feed.
struct FeedGroup {
    let feedName: String
    let articles: [DigestArticle]
    let totalTimeSeconds: Double
    
    var totalTimeLabel: String {
        return formatReadingTimeLabel(totalTimeSeconds)
    }
}

// MARK: - DigestResult

/// The result of digest generation.
struct DigestResult {
    let title: String
    let periodLabel: String
    let dateRangeLabel: String
    let generatedAt: Date
    let totalArticles: Int
    let totalFeeds: Int
    let totalReadingTimeSeconds: Double
    let feedGroups: [FeedGroup]
    let formattedOutput: String
    let format: DigestFormat
    
    var totalReadingTimeLabel: String {
        return formatReadingTimeLabel(totalReadingTimeSeconds)
    }
    
    var isEmpty: Bool { return totalArticles == 0 }
}


// MARK: - FormatContext

/// Collects all parameters needed by digest formatters into a single value type.
/// Eliminates the 8-parameter method signatures in formatPlainText/Markdown/HTML.
struct FormatContext {
    let feedGroups: [FeedGroup]
    let options: DigestOptions
    let totalArticles: Int
    let totalFeeds: Int
    let totalTime: Double
    let periodLabel: String
    let dateRangeLabel: String
    let generatedAt: Date
}

// MARK: - DigestGenerator

/// Generates formatted reading digests from history entries.
class DigestGenerator {
    
    // MARK: - Date Formatting
    
    private static let dateFormatter = DateFormatting.mediumDate
    
    private static let dateTimeFormatter = DateFormatting.mediumDateTime
    
    // MARK: - Generation
    
    /// Generates a digest from the given history entries.
    ///
    /// - Parameters:
    ///   - entries: Reading history entries to process.
    ///   - options: Configuration for the digest.
    ///   - now: Reference date for period calculations (defaults to current date).
    /// - Returns: A `DigestResult` containing the formatted digest and metadata.
    func generate(from entries: [HistoryEntry], options: DigestOptions = DigestOptions(),
                  now: Date = Date()) -> DigestResult {
        let (rangeStart, rangeEnd) = options.effectiveDateRange(relativeTo: now)
        
        // Filter entries to the date range
        let filtered = entries.filter { entry in
            entry.readAt >= rangeStart && entry.readAt < rangeEnd
        }
        
        // Convert to digest articles
        var articles = filtered.map { entry in
            DigestArticle(
                title: entry.title,
                link: entry.link,
                feedName: entry.feedName,
                readAt: entry.readAt,
                timeSpentSeconds: entry.timeSpentSeconds,
                visitCount: entry.visitCount,
                scrollProgress: entry.scrollProgress
            )
        }
        
        // Sort
        articles = sortArticles(articles, order: options.sortOrder)
        
        // Limit
        if options.maxArticles > 0 && articles.count > options.maxArticles {
            articles = Array(articles.prefix(options.maxArticles))
        }
        
        // Group by feed
        let feedGroups = buildFeedGroups(articles: articles, groupByFeed: options.groupByFeed)
        
        // Compute stats
        let totalTime = articles.reduce(0.0) { $0 + $1.timeSpentSeconds }
        let uniqueFeeds = Set(articles.map { $0.feedName })
        
        // Format date range label
        let rangeLabel = "\(Self.dateFormatter.string(from: rangeStart)) – \(Self.dateFormatter.string(from: rangeEnd))"
        
        // Generate formatted output
        let ctx = FormatContext(
            feedGroups: feedGroups,
            options: options,
            totalArticles: articles.count,
            totalFeeds: uniqueFeeds.count,
            totalTime: totalTime,
            periodLabel: options.period.label,
            dateRangeLabel: rangeLabel,
            generatedAt: now
        )
        let output = formatDigest(ctx)
        
        return DigestResult(
            title: "Reading Digest — \(options.period.label)",
            periodLabel: options.period.label,
            dateRangeLabel: rangeLabel,
            generatedAt: now,
            totalArticles: articles.count,
            totalFeeds: uniqueFeeds.count,
            totalReadingTimeSeconds: totalTime,
            feedGroups: feedGroups,
            formattedOutput: output,
            format: options.format
        )
    }
    
    // MARK: - Sorting
    
    private func sortArticles(_ articles: [DigestArticle], order: DigestOptions.SortOrder) -> [DigestArticle] {
        switch order {
        case .newestFirst:
            return articles.sorted { $0.readAt > $1.readAt }
        case .oldestFirst:
            return articles.sorted { $0.readAt < $1.readAt }
        case .mostTimeSpent:
            return articles.sorted { $0.timeSpentSeconds > $1.timeSpentSeconds }
        case .alphabetical:
            return articles.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }
    
    // MARK: - Grouping
    
    private func buildFeedGroups(articles: [DigestArticle], groupByFeed: Bool) -> [FeedGroup] {
        if !groupByFeed {
            let totalTime = articles.reduce(0.0) { $0 + $1.timeSpentSeconds }
            return [FeedGroup(feedName: "All Articles", articles: articles, totalTimeSeconds: totalTime)]
        }
        
        var grouped: [String: [DigestArticle]] = [:]
        for article in articles {
            grouped[article.feedName, default: []].append(article)
        }
        
        return grouped.map { (feedName, feedArticles) in
            let totalTime = feedArticles.reduce(0.0) { $0 + $1.timeSpentSeconds }
            return FeedGroup(feedName: feedName, articles: feedArticles, totalTimeSeconds: totalTime)
        }.sorted { $0.articles.count > $1.articles.count }
    }
    
    // MARK: - Formatting
    
    private func formatDigest(_ ctx: FormatContext) -> String {
        switch ctx.options.format {
        case .plainText: return formatPlainText(ctx)
        case .markdown:  return formatMarkdown(ctx)
        case .html:      return formatHTML(ctx)
        }
    }
    
    // MARK: - Plain Text Format
    
    private func formatPlainText(_ ctx: FormatContext) -> String {
        let feedGroups = ctx.feedGroups; let options = ctx.options
        let totalArticles = ctx.totalArticles; let totalFeeds = ctx.totalFeeds
        let totalTime = ctx.totalTime; let periodLabel = ctx.periodLabel
        let dateRangeLabel = ctx.dateRangeLabel; let generatedAt = ctx.generatedAt
        var lines: [String] = []
        let separator = String(repeating: "=", count: 50)
        
        lines.append(separator)
        lines.append("READING DIGEST — \(periodLabel.uppercased())")
        lines.append(dateRangeLabel)
        lines.append(separator)
        
        if options.includeStats {
            lines.append("")
            lines.append("OVERVIEW")
            lines.append("  Articles read: \(totalArticles)")
            lines.append("  Feeds: \(totalFeeds)")
            let timeLabel = formatTimeLabel(totalTime)
            lines.append("  Total reading time: \(timeLabel)")
            if totalArticles > 0 {
                let avgTime = totalTime / Double(totalArticles)
                lines.append("  Avg. per article: \(formatTimeLabel(avgTime))")
            }
            lines.append("")
        }
        
        if totalArticles == 0 {
            lines.append("No articles read during this period.")
            lines.append("")
            return lines.joined(separator: "\n")
        }
        
        for group in feedGroups {
            lines.append(String(repeating: "-", count: 40))
            if options.groupByFeed {
                lines.append("\(group.feedName) (\(group.articles.count) articles, \(group.totalTimeLabel))")
            }
            lines.append("")
            
            for (index, article) in group.articles.enumerated() {
                lines.append("  \(index + 1). \(article.title)")
                lines.append("     \(article.link)")
                if options.includeReadingTime {
                    lines.append("     Read: \(Self.dateTimeFormatter.string(from: article.readAt)) | Time: \(article.readingTimeLabel) | Progress: \(article.progressLabel)")
                }
                lines.append("")
            }
        }
        
        lines.append(separator)
        lines.append("Generated \(Self.dateTimeFormatter.string(from: generatedAt))")
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Markdown Format
    
    private func formatMarkdown(_ ctx: FormatContext) -> String {
        let feedGroups = ctx.feedGroups; let options = ctx.options
        let totalArticles = ctx.totalArticles; let totalFeeds = ctx.totalFeeds
        let totalTime = ctx.totalTime; let periodLabel = ctx.periodLabel
        let dateRangeLabel = ctx.dateRangeLabel; let generatedAt = ctx.generatedAt
        var lines: [String] = []
        
        lines.append("# 📖 Reading Digest — \(periodLabel)")
        lines.append("")
        lines.append("*\(dateRangeLabel)*")
        lines.append("")
        
        if options.includeStats {
            lines.append("## 📊 Overview")
            lines.append("")
            lines.append("| Metric | Value |")
            lines.append("|--------|-------|")
            lines.append("| Articles read | \(totalArticles) |")
            lines.append("| Feeds | \(totalFeeds) |")
            lines.append("| Total reading time | \(formatTimeLabel(totalTime)) |")
            if totalArticles > 0 {
                let avgTime = totalTime / Double(totalArticles)
                lines.append("| Avg. per article | \(formatTimeLabel(avgTime)) |")
            }
            lines.append("")
        }
        
        if totalArticles == 0 {
            lines.append("*No articles read during this period.*")
            lines.append("")
            return lines.joined(separator: "\n")
        }
        
        for group in feedGroups {
            if options.groupByFeed {
                lines.append("## \(group.feedName)")
                lines.append("")
                lines.append("*\(group.articles.count) article\(group.articles.count == 1 ? "" : "s") · \(group.totalTimeLabel)*")
                lines.append("")
            }
            
            for article in group.articles {
                lines.append("- **[\(article.title)](\(article.link))**")
                if options.includeReadingTime {
                    lines.append("  ⏱ \(article.readingTimeLabel) · \(article.progressLabel) read · \(Self.dateFormatter.string(from: article.readAt))")
                }
            }
            lines.append("")
        }
        
        lines.append("---")
        lines.append("*Generated \(Self.dateTimeFormatter.string(from: generatedAt))*")
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - HTML Format
    
    private func formatHTML(_ ctx: FormatContext) -> String {
        let feedGroups = ctx.feedGroups; let options = ctx.options
        let totalArticles = ctx.totalArticles; let totalFeeds = ctx.totalFeeds
        let totalTime = ctx.totalTime; let periodLabel = ctx.periodLabel
        let dateRangeLabel = ctx.dateRangeLabel; let generatedAt = ctx.generatedAt
        var html: [String] = []
        
        html.append("<!DOCTYPE html>")
        html.append("<html lang=\"en\"><head>")
        html.append("<meta charset=\"UTF-8\">")
        html.append("<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">")
        html.append("<title>Reading Digest — \(periodLabel.htmlEscaped)</title>")
        html.append("<style>")
        html.append("body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;max-width:700px;margin:2em auto;padding:0 1em;color:#333;line-height:1.6}")
        html.append("h1{color:#1a1a2e;border-bottom:2px solid #e8e8e8;padding-bottom:.3em}")
        html.append("h2{color:#16213e;margin-top:1.5em}")
        html.append(".stats{background:#f8f9fa;border-radius:8px;padding:1em;margin:1em 0}")
        html.append(".stats td{padding:4px 12px}.stats td:first-child{font-weight:600}")
        html.append(".article{margin:.8em 0;padding:.5em 0;border-bottom:1px solid #eee}")
        html.append(".article a{color:#0645ad;text-decoration:none;font-weight:600}")
        html.append(".article a:hover{text-decoration:underline}")
        html.append(".meta{color:#666;font-size:.85em;margin-top:.2em}")
        html.append(".badge{display:inline-block;background:#e8f4f8;color:#1a73e8;border-radius:4px;padding:1px 6px;font-size:.8em;margin-right:4px}")
        html.append(".footer{color:#999;font-size:.85em;margin-top:2em;border-top:1px solid #eee;padding-top:.5em}")
        html.append("</style></head><body>")
        
        html.append("<h1>📖 Reading Digest — \(periodLabel.htmlEscaped)</h1>")
        html.append("<p><em>\(dateRangeLabel.htmlEscaped)</em></p>")
        
        if options.includeStats {
            html.append("<div class=\"stats\"><table>")
            html.append("<tr><td>Articles read</td><td>\(totalArticles)</td></tr>")
            html.append("<tr><td>Feeds</td><td>\(totalFeeds)</td></tr>")
            html.append("<tr><td>Total reading time</td><td>\(formatTimeLabel(totalTime).htmlEscaped)</td></tr>")
            if totalArticles > 0 {
                let avgTime = totalTime / Double(totalArticles)
                html.append("<tr><td>Avg. per article</td><td>\(formatTimeLabel(avgTime).htmlEscaped)</td></tr>")
            }
            html.append("</table></div>")
        }
        
        if totalArticles == 0 {
            html.append("<p><em>No articles read during this period.</em></p>")
            html.append("</body></html>")
            return html.joined(separator: "\n")
        }
        
        for group in feedGroups {
            if options.groupByFeed {
                html.append("<h2>\(group.feedName.htmlEscaped)</h2>")
                html.append("<p><em>\(group.articles.count) article\(group.articles.count == 1 ? "" : "s") · \(group.totalTimeLabel.htmlEscaped)</em></p>")
            }
            
            for article in group.articles {
                html.append("<div class=\"article\">")
                html.append("<a href=\"\(article.link.htmlEscaped)\">\(article.title.htmlEscaped)</a>")
                if options.includeReadingTime {
                    html.append("<div class=\"meta\">")
                    html.append("<span class=\"badge\">⏱ \(article.readingTimeLabel.htmlEscaped)</span>")
                    html.append("<span class=\"badge\">\(article.progressLabel.htmlEscaped) read</span>")
                    html.append("\(Self.dateFormatter.string(from: article.readAt).htmlEscaped)")
                    html.append("</div>")
                }
                html.append("</div>")
            }
        }
        
        html.append("<div class=\"footer\">Generated \(Self.dateTimeFormatter.string(from: generatedAt).htmlEscaped)</div>")
        html.append("</body></html>")
        
        return html.joined(separator: "\n")
    }
    
    // MARK: - Helpers
    
    private func formatTimeLabel(_ seconds: Double) -> String {
        return formatReadingTimeLabel(seconds)
    }
    
    private func _ text: String.htmlEscaped -> String {
        return text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
