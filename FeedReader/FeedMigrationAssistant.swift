//
//  FeedMigrationAssistant.swift
//  FeedReader
//
//  Smart migration assistant for importing feeds from other RSS readers.
//  Detects source format (Feedly, Inoreader, NewsBlur, The Old Reader,
//  Miniflux, generic OPML), maps categories, deduplicates against existing
//  feeds, and produces a detailed migration report with recommendations.
//

import Foundation

/// Notification posted when a migration completes.
extension Notification.Name {
    static let feedMigrationDidComplete = Notification.Name("FeedMigrationDidCompleteNotification")
}

// MARK: - Source Reader Detection

/// Known RSS reader platforms that export OPML or JSON.
enum FeedReaderSource: String, CaseIterable, Codable {
    case feedly = "Feedly"
    case inoreader = "Inoreader"
    case newsblur = "NewsBlur"
    case theOldReader = "The Old Reader"
    case miniflux = "Miniflux"
    case netNewsWire = "NetNewsWire"
    case feedbin = "Feedbin"
    case genericOPML = "Generic OPML"
    case unknown = "Unknown"

    var iconEmoji: String {
        switch self {
        case .feedly: return "🌿"
        case .inoreader: return "📰"
        case .newsblur: return "📋"
        case .theOldReader: return "📖"
        case .miniflux: return "🔲"
        case .netNewsWire: return "🌐"
        case .feedbin: return "📬"
        case .genericOPML: return "📄"
        case .unknown: return "❓"
        }
    }
}

// MARK: - Migration Models

/// Represents a single feed parsed from an import source.
struct MigrationFeedEntry: Codable, Equatable {
    let title: String
    let xmlUrl: String
    let htmlUrl: String?
    let category: String?
    let source: FeedReaderSource

    /// Normalized URL for dedup comparison.
    var normalizedUrl: String {
        var url = xmlUrl.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if url.hasSuffix("/") { url = String(url.dropLast()) }
        // Strip protocol for comparison
        url = url.replacingOccurrences(of: "https://", with: "")
        url = url.replacingOccurrences(of: "http://", with: "")
        return url
    }
}

/// Status of a feed during migration.
enum MigrationFeedStatus: String, Codable {
    case imported = "Imported"
    case duplicate = "Duplicate"
    case invalid = "Invalid"
    case skipped = "Skipped"
    case categoryMapped = "Category Mapped"
}

/// Result for each feed in the migration.
struct MigrationFeedResult: Codable {
    let entry: MigrationFeedEntry
    let status: MigrationFeedStatus
    let note: String?
    let mappedCategory: String?
}

/// Category mapping rule.
struct CategoryMapping: Codable, Equatable {
    let sourceCategory: String
    let targetCategory: String
    let isAutomatic: Bool
}

/// Full migration report.
struct MigrationReport: Codable {
    let source: FeedReaderSource
    let timestamp: Date
    let totalFound: Int
    let imported: Int
    let duplicates: Int
    let invalid: Int
    let skipped: Int
    let categoryMappings: [CategoryMapping]
    let feedResults: [MigrationFeedResult]
    let recommendations: [String]
    let durationSeconds: TimeInterval

    var summary: String {
        var parts: [String] = []
        parts.append("Migration from \(source.rawValue): \(totalFound) feeds found")
        parts.append("\(imported) imported, \(duplicates) duplicates, \(invalid) invalid, \(skipped) skipped")
        if !categoryMappings.isEmpty {
            parts.append("\(categoryMappings.count) category mapping\(categoryMappings.count == 1 ? "" : "s") applied")
        }
        parts.append(String(format: "Completed in %.1fs", durationSeconds))
        return parts.joined(separator: ". ")
    }

    /// Export report as JSON data.
    func toJSON() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(self)
    }

    /// Export report as human-readable text.
    func toText() -> String {
        var lines: [String] = []
        lines.append("═══════════════════════════════════════════")
        lines.append("  \(source.iconEmoji) Feed Migration Report")
        lines.append("═══════════════════════════════════════════")
        lines.append("")

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        lines.append("Date: \(formatter.string(from: timestamp))")
        lines.append("Source: \(source.rawValue)")
        lines.append(String(format: "Duration: %.1f seconds", durationSeconds))
        lines.append("")

        lines.append("── Summary ──────────────────────────────")
        lines.append("  Total feeds found:  \(totalFound)")
        lines.append("  ✅ Imported:        \(imported)")
        lines.append("  ⏭ Duplicates:      \(duplicates)")
        lines.append("  ❌ Invalid:         \(invalid)")
        lines.append("  ⚠️ Skipped:         \(skipped)")
        lines.append("")

        if !categoryMappings.isEmpty {
            lines.append("── Category Mappings ────────────────────")
            for mapping in categoryMappings {
                let auto = mapping.isAutomatic ? "(auto)" : "(manual)"
                lines.append("  \(mapping.sourceCategory) → \(mapping.targetCategory) \(auto)")
            }
            lines.append("")
        }

        if !recommendations.isEmpty {
            lines.append("── Recommendations ─────────────────────")
            for (i, rec) in recommendations.enumerated() {
                lines.append("  \(i + 1). \(rec)")
            }
            lines.append("")
        }

        lines.append("── Feed Details ────────────────────────")
        for result in feedResults {
            let statusIcon: String
            switch result.status {
            case .imported: statusIcon = "✅"
            case .duplicate: statusIcon = "⏭"
            case .invalid: statusIcon = "❌"
            case .skipped: statusIcon = "⚠️"
            case .categoryMapped: statusIcon = "📁"
            }
            var line = "  \(statusIcon) \(result.entry.title)"
            if let note = result.note {
                line += " — \(note)"
            }
            lines.append(line)
        }

        lines.append("")
        lines.append("═══════════════════════════════════════════")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Migration Configuration

/// Options controlling migration behavior.
struct MigrationOptions {
    /// Whether to auto-enable imported feeds. Default true.
    var autoEnable: Bool = true
    /// Whether to merge duplicate categories (case-insensitive). Default true.
    var mergeSimilarCategories: Bool = true
    /// Whether to validate feed URLs before importing. Default false.
    var validateUrls: Bool = false
    /// Custom category mappings to apply. Source → Target.
    var customCategoryMappings: [String: String] = [:]
    /// Maximum feeds to import (0 = unlimited).
    var maxFeeds: Int = 0
    /// Whether to perform a dry run (no actual import).
    var dryRun: Bool = false
}

// MARK: - Migration Assistant

class FeedMigrationAssistant {

    // MARK: - Singleton

    static let shared = FeedMigrationAssistant()

    // MARK: - Constants

    private static let migrationHistoryKey = "FeedMigrationAssistant.history"
    static let maxHistoryEntries = 50

    // MARK: - Properties

    /// History of migration reports.
    private(set) var migrationHistory: [MigrationReport] = []

    // MARK: - Well-known category synonyms for auto-mapping

    private static let categorySynonyms: [String: String] = [
        "tech": "Technology",
        "technology": "Technology",
        "computers": "Technology",
        "programming": "Technology",
        "software": "Technology",
        "dev": "Technology",
        "development": "Technology",
        "coding": "Technology",
        "news": "News",
        "world news": "News",
        "current events": "News",
        "headlines": "News",
        "breaking": "News",
        "sports": "Sports",
        "athletics": "Sports",
        "gaming": "Gaming",
        "games": "Gaming",
        "video games": "Gaming",
        "science": "Science",
        "research": "Science",
        "business": "Business",
        "finance": "Business",
        "economy": "Business",
        "money": "Business",
        "investing": "Business",
        "entertainment": "Entertainment",
        "movies": "Entertainment",
        "music": "Entertainment",
        "tv": "Entertainment",
        "media": "Entertainment",
        "health": "Health",
        "fitness": "Health",
        "wellness": "Health",
        "medicine": "Health",
        "food": "Food & Cooking",
        "cooking": "Food & Cooking",
        "recipes": "Food & Cooking",
        "travel": "Travel",
        "design": "Design",
        "art": "Design",
        "politics": "Politics",
        "government": "Politics",
        "education": "Education",
        "learning": "Education",
        "security": "Security",
        "cybersecurity": "Security",
        "infosec": "Security",
    ]

    // MARK: - Initialization

    private init() {
        loadHistory()
    }

    // MARK: - Source Detection

    /// Detect which RSS reader produced the OPML content.
    func detectSource(from opmlContent: String) -> FeedReaderSource {
        let lower = opmlContent.lowercased()

        // Check for Feedly markers
        if lower.contains("feedly.com") || lower.contains("feedly opml") ||
           lower.contains("\"feedly\"") {
            return .feedly
        }

        // Inoreader
        if lower.contains("inoreader") || lower.contains("innologica") {
            return .inoreader
        }

        // NewsBlur
        if lower.contains("newsblur") {
            return .newsblur
        }

        // The Old Reader
        if lower.contains("theoldreader") || lower.contains("the old reader") {
            return .theOldReader
        }

        // Miniflux
        if lower.contains("miniflux") {
            return .miniflux
        }

        // NetNewsWire
        if lower.contains("netnewswire") {
            return .netNewsWire
        }

        // Feedbin
        if lower.contains("feedbin") {
            return .feedbin
        }

        // Check if it's valid OPML at all
        if lower.contains("<opml") || lower.contains("<outline") {
            return .genericOPML
        }

        return .unknown
    }

    // MARK: - Parse OPML with Source Detection

    /// Parse OPML content into migration feed entries.
    func parseOPML(_ content: String) -> (source: FeedReaderSource, entries: [MigrationFeedEntry]) {
        let source = detectSource(from: content)
        var entries: [MigrationFeedEntry] = []

        // Use basic XML parsing for OPML outlines
        let outlines = parseOutlines(from: content)
        for outline in outlines {
            guard let xmlUrl = outline["xmlUrl"] ?? outline["xmlurl"],
                  !xmlUrl.isEmpty else {
                continue
            }
            let title = outline["title"] ?? outline["text"] ?? xmlUrl
            let htmlUrl = outline["htmlUrl"] ?? outline["htmlurl"]
            let category = outline["category"]

            entries.append(MigrationFeedEntry(
                title: title,
                xmlUrl: xmlUrl,
                htmlUrl: htmlUrl,
                category: category,
                source: source
            ))
        }

        return (source, entries)
    }

    /// Parse outline elements from OPML XML content.
    private func parseOutlines(from content: String) -> [[String: String]] {
        var outlines: [[String: String]] = []
        var currentCategory: String?

        // Simple line-based OPML parser
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("<outline") else {
                // Check for closing outline tag (end of category group)
                if trimmed == "</outline>" {
                    currentCategory = nil
                }
                continue
            }

            let attrs = parseAttributes(from: trimmed)

            // Category outline (has text but no xmlUrl)
            if attrs["xmlUrl"] == nil && attrs["xmlurl"] == nil {
                currentCategory = attrs["title"] ?? attrs["text"]
                continue
            }

            var outline = attrs
            if let cat = currentCategory, outline["category"] == nil {
                outline["category"] = cat
            }
            outlines.append(outline)
        }

        return outlines
    }

    /// Extract XML attributes from a tag string.
    private func parseAttributes(from tag: String) -> [String: String] {
        var attrs: [String: String] = [:]
        var remaining = tag

        while let eqRange = remaining.range(of: "=\"") {
            // Find attribute name (go backwards from =)
            let beforeEq = remaining[remaining.startIndex..<eqRange.lowerBound]
            let parts = beforeEq.split(separator: " ")
            guard let attrName = parts.last else { break }

            // Find closing quote
            let afterEq = remaining[eqRange.upperBound...]
            guard let closeQuote = afterEq.firstIndex(of: "\"") else { break }
            let value = String(afterEq[afterEq.startIndex..<closeQuote])

            attrs[String(attrName)] = decodeXMLEntities(value)
            remaining = String(afterEq[afterEq.index(after: closeQuote)...])
        }

        return attrs
    }

    /// Decode common XML entities.
    private func decodeXMLEntities(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
    }

    // MARK: - Category Mapping

    /// Normalize a category name to a canonical form.
    func normalizeCategory(_ category: String) -> String {
        let lower = category.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip common prefixes from Feedly/Inoreader
        var cleaned = lower
        let prefixes = ["user/", "label/", "tag/", "folder/"]
        for prefix in prefixes {
            if let range = cleaned.range(of: prefix) {
                cleaned = String(cleaned[range.upperBound...])
            }
        }

        // Check synonym map
        if let canonical = FeedMigrationAssistant.categorySynonyms[cleaned] {
            return canonical
        }

        // Title-case the cleaned category
        return cleaned.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    /// Build category mappings for a set of entries.
    func buildCategoryMappings(for entries: [MigrationFeedEntry],
                                customMappings: [String: String] = [:]) -> [CategoryMapping] {
        var mappings: [CategoryMapping] = []
        var seen = Set<String>()

        for entry in entries {
            guard let category = entry.category, !seen.contains(category) else { continue }
            seen.insert(category)

            if let custom = customMappings[category] {
                mappings.append(CategoryMapping(
                    sourceCategory: category,
                    targetCategory: custom,
                    isAutomatic: false
                ))
            } else {
                let normalized = normalizeCategory(category)
                if normalized.lowercased() != category.lowercased() {
                    mappings.append(CategoryMapping(
                        sourceCategory: category,
                        targetCategory: normalized,
                        isAutomatic: true
                    ))
                }
            }
        }

        return mappings.sorted { $0.sourceCategory < $1.sourceCategory }
    }

    // MARK: - Migration Execution

    /// Run a full migration from OPML content.
    /// - Parameters:
    ///   - opmlContent: The OPML XML string to import.
    ///   - options: Migration options controlling behavior.
    /// - Returns: A detailed migration report.
    func migrate(from opmlContent: String, options: MigrationOptions = MigrationOptions()) -> MigrationReport {
        let startTime = Date()

        // 1. Parse
        let (source, entries) = parseOPML(opmlContent)

        // 2. Limit if needed
        var processEntries = entries
        if options.maxFeeds > 0 && processEntries.count > options.maxFeeds {
            processEntries = Array(processEntries.prefix(options.maxFeeds))
        }

        // 3. Build category mappings
        let categoryMappings = buildCategoryMappings(
            for: processEntries,
            customMappings: options.customCategoryMappings
        )
        let categoryMap = Dictionary(uniqueKeysWithValues: categoryMappings.map { ($0.sourceCategory, $0.targetCategory) })

        // 4. Get existing feed URLs for dedup
        let existingUrls = Set(FeedManager.shared.feeds.map { $0.url.lowercased() })
        let existingNormalized = Set(FeedManager.shared.feeds.map { url -> String in
            var u = url.url.lowercased()
            if u.hasSuffix("/") { u = String(u.dropLast()) }
            u = u.replacingOccurrences(of: "https://", with: "")
            u = u.replacingOccurrences(of: "http://", with: "")
            return u
        })

        // 5. Process each entry
        var feedResults: [MigrationFeedResult] = []
        var importedCount = 0
        var duplicateCount = 0
        var invalidCount = 0
        var skippedCount = 0

        for entry in processEntries {
            // Validate URL
            guard let url = URL(string: entry.xmlUrl),
                  url.scheme == "http" || url.scheme == "https" else {
                feedResults.append(MigrationFeedResult(
                    entry: entry,
                    status: .invalid,
                    note: "Invalid URL format",
                    mappedCategory: nil
                ))
                invalidCount += 1
                continue
            }

            // Check for duplicates
            if existingUrls.contains(entry.xmlUrl.lowercased()) ||
               existingNormalized.contains(entry.normalizedUrl) {
                feedResults.append(MigrationFeedResult(
                    entry: entry,
                    status: .duplicate,
                    note: "Already subscribed",
                    mappedCategory: nil
                ))
                duplicateCount += 1
                continue
            }

            // Map category
            let mappedCategory: String?
            if let sourceCat = entry.category, let mapped = categoryMap[sourceCat] {
                mappedCategory = mapped
            } else if let sourceCat = entry.category, options.mergeSimilarCategories {
                mappedCategory = normalizeCategory(sourceCat)
            } else {
                mappedCategory = entry.category
            }

            // Import (or dry run)
            if !options.dryRun {
                let feed = Feed(
                    name: entry.title,
                    url: entry.xmlUrl,
                    isEnabled: options.autoEnable
                )
                feed.category = mappedCategory
                FeedManager.shared.addFeed(feed)
            }

            feedResults.append(MigrationFeedResult(
                entry: entry,
                status: .imported,
                note: options.dryRun ? "Dry run — not imported" : nil,
                mappedCategory: mappedCategory
            ))
            importedCount += 1
        }

        // 6. Generate recommendations
        let recommendations = generateRecommendations(
            source: source,
            totalFound: processEntries.count,
            imported: importedCount,
            duplicates: duplicateCount,
            categoryMappings: categoryMappings
        )

        // 7. Build report
        let duration = Date().timeIntervalSince(startTime)
        let report = MigrationReport(
            source: source,
            timestamp: startTime,
            totalFound: processEntries.count,
            imported: importedCount,
            duplicates: duplicateCount,
            invalid: invalidCount,
            skipped: skippedCount,
            categoryMappings: categoryMappings,
            feedResults: feedResults,
            recommendations: recommendations,
            durationSeconds: duration
        )

        // 8. Save to history
        if !options.dryRun {
            addToHistory(report)
            NotificationCenter.default.post(name: .feedMigrationDidComplete, object: report)
        }

        return report
    }

    // MARK: - Recommendations Engine

    private func generateRecommendations(source: FeedReaderSource,
                                          totalFound: Int,
                                          imported: Int,
                                          duplicates: Int,
                                          categoryMappings: [CategoryMapping]) -> [String] {
        var recs: [String] = []

        if duplicates > 0 {
            recs.append("Found \(duplicates) feeds you're already subscribed to — your collection is well-curated!")
        }

        if imported > 20 {
            recs.append("You imported \(imported) feeds — consider organizing them into categories for easier browsing.")
        }

        if imported > 50 {
            recs.append("With \(imported)+ feeds, consider disabling some and using the feed health monitor to find inactive ones.")
        }

        let autoMapped = categoryMappings.filter { $0.isAutomatic }
        if !autoMapped.isEmpty {
            recs.append("\(autoMapped.count) categories were automatically normalized. Review them in feed settings.")
        }

        if totalFound == 0 {
            recs.append("No feeds were found in the import file. Make sure you exported your subscriptions from \(source.rawValue).")
        }

        switch source {
        case .feedly:
            recs.append("Tip: Feedly exports may include 'Saved for Later' — those won't appear as feeds.")
        case .inoreader:
            recs.append("Tip: Check Inoreader rules/filters — those aren't included in OPML exports.")
        case .newsblur:
            recs.append("Tip: NewsBlur folder structure is preserved as categories.")
        default:
            break
        }

        if imported > 0 {
            recs.append("Run a feed health check to identify any imported feeds that may be dead or slow.")
        }

        return recs
    }

    // MARK: - Dry Run

    /// Preview a migration without actually importing anything.
    func preview(from opmlContent: String, options: MigrationOptions = MigrationOptions()) -> MigrationReport {
        var previewOptions = options
        previewOptions.dryRun = true
        return migrate(from: opmlContent, options: previewOptions)
    }

    // MARK: - History Management

    private func addToHistory(_ report: MigrationReport) {
        migrationHistory.insert(report, at: 0)
        if migrationHistory.count > FeedMigrationAssistant.maxHistoryEntries {
            migrationHistory = Array(migrationHistory.prefix(FeedMigrationAssistant.maxHistoryEntries))
        }
        saveHistory()
    }

    /// Clear migration history.
    func clearHistory() {
        migrationHistory.removeAll()
        saveHistory()
    }

    // MARK: - Persistence

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: FeedMigrationAssistant.migrationHistoryKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let history = try? decoder.decode([MigrationReport].self, from: data) {
            migrationHistory = history
        }
    }

    private func saveHistory() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(migrationHistory) {
            UserDefaults.standard.set(data, forKey: FeedMigrationAssistant.migrationHistoryKey)
        }
    }

    // MARK: - Convenience

    /// Get a user-friendly description of what the migration will do.
    func describeMigration(from opmlContent: String) -> String {
        let (source, entries) = parseOPML(opmlContent)
        let categories = Set(entries.compactMap { $0.category })

        var desc = "\(source.iconEmoji) Detected source: \(source.rawValue)\n"
        desc += "📊 Found \(entries.count) feed\(entries.count == 1 ? "" : "s")"
        if !categories.isEmpty {
            desc += " in \(categories.count) categor\(categories.count == 1 ? "y" : "ies")"
        }
        desc += "\n\nUse preview() to see a detailed breakdown before importing."
        return desc
    }
}
