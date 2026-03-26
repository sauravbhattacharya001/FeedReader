import Foundation

/// SmartFeedSearch provides full-text search across saved articles with
/// relevance ranking, keyword highlighting, and search history tracking.
///
/// Usage:
///     let search = SmartFeedSearch()
///     let results = search.search("machine learning", in: articles)
///     // results are ranked by relevance (title matches weighted higher)
///     for result in results {
///         print(result.article.title, "score:", result.score)
///         print("Snippets:", result.highlightedSnippets)
///     }
///
///     // Search history
///     let recent = search.recentSearches(limit: 10)
///     search.clearSearchHistory()
///
class SmartFeedSearch {

    // MARK: - Types

    struct SearchResult: Comparable {
        let article: SearchableArticle
        let score: Double
        let highlightedSnippets: [String]
        let matchedTerms: Set<String>

        static func < (lhs: SearchResult, rhs: SearchResult) -> Bool {
            lhs.score < rhs.score
        }
    }

    struct SearchableArticle {
        let id: String
        let title: String
        let body: String
        let author: String
        let feedName: String
        let date: Date?
        let url: String?
    }

    struct SearchHistoryEntry: Codable {
        let query: String
        let timestamp: Date
        let resultCount: Int
    }

    struct SearchOptions {
        var caseSensitive: Bool = false
        var matchAllTerms: Bool = false
        var maxResults: Int = 50
        var snippetLength: Int = 120
        var dateRange: (start: Date, end: Date)? = nil
        var feedFilter: String? = nil

        static let `default` = SearchOptions()
    }

    // MARK: - Weights

    private let titleWeight: Double = 3.0
    private let authorWeight: Double = 2.0
    private let feedNameWeight: Double = 1.5
    private let bodyWeight: Double = 1.0

    // MARK: - History

    private let historyKey = "SmartFeedSearch.history"
    private let maxHistorySize = 100

    // MARK: - Search

    func search(_ query: String,
                in articles: [SearchableArticle],
                options: SearchOptions = .default) -> [SearchResult] {

        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        let terms = tokenize(query, caseSensitive: options.caseSensitive)
        guard !terms.isEmpty else { return [] }

        var results: [SearchResult] = []

        for article in articles {
            // Apply date filter
            if let range = options.dateRange, let date = article.date {
                guard date >= range.start && date <= range.end else { continue }
            }

            // Apply feed filter
            if let feedFilter = options.feedFilter {
                let filterLower = feedFilter.lowercased()
                guard article.feedName.lowercased().contains(filterLower) else { continue }
            }

            let result = scoreArticle(article, terms: terms, options: options)
            if result.score > 0 {
                results.append(result)
            }
        }

        // Sort by relevance (descending)
        results.sort { $0.score > $1.score }

        // Limit results
        let limited = Array(results.prefix(options.maxResults))

        // Save to history
        saveSearchHistory(query: query, resultCount: limited.count)

        return limited
    }

    // MARK: - Scoring

    private func scoreArticle(_ article: SearchableArticle,
                              terms: [String],
                              options: SearchOptions) -> SearchResult {
        var totalScore: Double = 0
        var matchedTerms: Set<String> = []
        var snippets: [String] = []

        let titleText = options.caseSensitive ? article.title : article.title.lowercased()
        let bodyText = options.caseSensitive ? article.body : article.body.lowercased()
        let authorText = options.caseSensitive ? article.author : article.author.lowercased()
        let feedText = options.caseSensitive ? article.feedName : article.feedName.lowercased()

        for term in terms {
            var termScore: Double = 0

            // Title matches
            let titleCount = countOccurrences(of: term, in: titleText)
            if titleCount > 0 {
                termScore += Double(titleCount) * titleWeight
                matchedTerms.insert(term)
            }

            // Author matches
            let authorCount = countOccurrences(of: term, in: authorText)
            if authorCount > 0 {
                termScore += Double(authorCount) * authorWeight
                matchedTerms.insert(term)
            }

            // Feed name matches
            let feedCount = countOccurrences(of: term, in: feedText)
            if feedCount > 0 {
                termScore += Double(feedCount) * feedNameWeight
                matchedTerms.insert(term)
            }

            // Body matches
            let bodyCount = countOccurrences(of: term, in: bodyText)
            if bodyCount > 0 {
                termScore += Double(min(bodyCount, 10)) * bodyWeight
                matchedTerms.insert(term)

                // Extract snippet around first match
                if let snippet = extractSnippet(from: article.body,
                                                 term: term,
                                                 length: options.snippetLength,
                                                 caseSensitive: options.caseSensitive) {
                    snippets.append(snippet)
                }
            }

            // Exact phrase bonus (whole word)
            if titleText.contains(" \(term) ") || titleText.hasPrefix("\(term) ") || titleText.hasSuffix(" \(term)") || titleText == term {
                termScore *= 1.5
            }

            totalScore += termScore
        }

        // If matchAllTerms is set, require all terms to match
        if options.matchAllTerms && matchedTerms.count < terms.count {
            totalScore = 0
        }

        // Boost recent articles slightly
        if let date = article.date {
            let daysSince = -date.timeIntervalSinceNow / 86400
            if daysSince < 7 {
                totalScore *= 1.2
            } else if daysSince < 30 {
                totalScore *= 1.1
            }
        }

        // Limit snippets to 3
        let finalSnippets = Array(snippets.prefix(3))

        return SearchResult(article: article,
                           score: totalScore,
                           highlightedSnippets: finalSnippets,
                           matchedTerms: matchedTerms)
    }

    // MARK: - Helpers

    private func tokenize(_ query: String, caseSensitive: Bool) -> [String] {
        let text = caseSensitive ? query : query.lowercased()
        return text.components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
    }

    private func countOccurrences(of term: String, in text: String) -> Int {
        var count = 0
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: term, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<text.endIndex
        }
        return count
    }

    private func extractSnippet(from text: String, term: String, length: Int, caseSensitive: Bool) -> String? {
        let searchText = caseSensitive ? text : text.lowercased()
        let searchTerm = caseSensitive ? term : term.lowercased()

        guard let range = searchText.range(of: searchTerm) else { return nil }

        let matchStart = searchText.distance(from: searchText.startIndex, to: range.lowerBound)
        let halfLen = length / 2

        let snippetStart = max(0, matchStart - halfLen)
        let snippetEnd = min(text.count, matchStart + searchTerm.count + halfLen)

        let startIdx = text.index(text.startIndex, offsetBy: snippetStart)
        let endIdx = text.index(text.startIndex, offsetBy: snippetEnd)

        var snippet = String(text[startIdx..<endIdx])

        if snippetStart > 0 { snippet = "…" + snippet }
        if snippetEnd < text.count { snippet = snippet + "…" }

        return snippet
    }

    // MARK: - Search History

    func recentSearches(limit: Int = 20) -> [SearchHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let history = try? JSONDecoder().decode([SearchHistoryEntry].self, from: data) else {
            return []
        }
        return Array(history.prefix(limit))
    }

    func clearSearchHistory() {
        UserDefaults.standard.removeObject(forKey: historyKey)
    }

    private func saveSearchHistory(query: String, resultCount: Int) {
        var history = recentSearches(limit: maxHistorySize)
        let entry = SearchHistoryEntry(query: query,
                                        timestamp: Date(),
                                        resultCount: resultCount)
        history.insert(entry, at: 0)
        if history.count > maxHistorySize {
            history = Array(history.prefix(maxHistorySize))
        }
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    // MARK: - Suggestions

    /// Returns popular/recent search terms for autocomplete
    func searchSuggestions(prefix: String, limit: Int = 5) -> [String] {
        let history = recentSearches(limit: 50)
        let lowerPrefix = prefix.lowercased()
        var seen: Set<String> = []
        var suggestions: [String] = []

        for entry in history {
            let lower = entry.query.lowercased()
            if lower.hasPrefix(lowerPrefix) && !seen.contains(lower) {
                seen.insert(lower)
                suggestions.append(entry.query)
                if suggestions.count >= limit { break }
            }
        }
        return suggestions
    }
}
