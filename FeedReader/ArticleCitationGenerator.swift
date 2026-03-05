//
//  ArticleCitationGenerator.swift
//  FeedReader
//
//  Generates formatted academic citations from article metadata.
//  Supports APA 7th, MLA 9th, Chicago 17th, IEEE, Harvard, and
//  BibTeX formats. Handles author name parsing, date formatting,
//  access date generation, and multi-author rules per style guide.
//

import Foundation

// MARK: - Citation Format

/// Supported citation formats.
enum CitationFormat: String, CaseIterable {
    case apa       // APA 7th Edition
    case mla       // MLA 9th Edition
    case chicago   // Chicago 17th Edition (Author-Date)
    case ieee      // IEEE
    case harvard   // Harvard
    case bibtex    // BibTeX @misc entry
}

// MARK: - Author Name

/// Represents a parsed author name.
struct AuthorName: Equatable {
    let firstName: String
    let lastName: String
    let middleInitials: [String]  // Optional middle initials

    /// Full display name (e.g., "John A. Smith")
    var fullName: String {
        var parts = [firstName]
        parts.append(contentsOf: middleInitials.map { $0.hasSuffix(".") ? $0 : "\($0)." })
        parts.append(lastName)
        return parts.joined(separator: " ")
    }

    /// APA format: "Smith, J. A."
    var apaFormat: String {
        var initials = [String(firstName.prefix(1)) + "."]
        initials.append(contentsOf: middleInitials.map {
            String($0.replacingOccurrences(of: ".", with: "").prefix(1)) + "."
        })
        return "\(lastName), \(initials.joined(separator: " "))"
    }

    /// MLA format: "Smith, John A." (first author) or "John A. Smith" (subsequent)
    func mlaFormat(isFirst: Bool) -> String {
        let middle = middleInitials.isEmpty ? "" :
            " " + middleInitials.map { $0.hasSuffix(".") ? $0 : "\($0)." }.joined(separator: " ")
        if isFirst {
            return "\(lastName), \(firstName)\(middle)"
        }
        return "\(firstName)\(middle) \(lastName)"
    }

    /// Chicago format: "Smith, John A." (first) or "John A. Smith" (subsequent)
    func chicagoFormat(isFirst: Bool) -> String {
        return mlaFormat(isFirst: isFirst) // Same inversion rule
    }

    /// IEEE format: "J. A. Smith"
    var ieeeFormat: String {
        var initials = [String(firstName.prefix(1)) + "."]
        initials.append(contentsOf: middleInitials.map {
            String($0.replacingOccurrences(of: ".", with: "").prefix(1)) + "."
        })
        return "\(initials.joined(separator: " ")) \(lastName)"
    }

    /// Harvard format: "Smith, J.A."
    var harvardFormat: String {
        var initials = String(firstName.prefix(1)) + "."
        for mi in middleInitials {
            initials += String(mi.replacingOccurrences(of: ".", with: "").prefix(1)) + "."
        }
        return "\(lastName), \(initials)"
    }

    /// BibTeX format: "Smith, John A."
    var bibtexFormat: String {
        let middle = middleInitials.isEmpty ? "" :
            " " + middleInitials.map { $0.hasSuffix(".") ? $0 : "\($0)." }.joined(separator: " ")
        return "\(lastName), \(firstName)\(middle)"
    }
}

// MARK: - Citation Metadata

/// Article metadata used for citation generation.
struct CitationMetadata: Equatable {
    /// Article title.
    let title: String
    /// Author name strings (will be parsed). Can be "First Last" or "Last, First".
    let authors: [String]
    /// Publication date.
    let publicationDate: Date?
    /// Name of the website or publication.
    let siteName: String?
    /// Article URL.
    let url: String?
    /// Date the article was accessed (defaults to now).
    let accessDate: Date
    /// Publisher or organization (if different from site name).
    let publisher: String?
    /// DOI if available.
    let doi: String?

    init(title: String,
         authors: [String] = [],
         publicationDate: Date? = nil,
         siteName: String? = nil,
         url: String? = nil,
         accessDate: Date = Date(),
         publisher: String? = nil,
         doi: String? = nil) {
        self.title = title
        self.authors = authors
        self.publicationDate = publicationDate
        self.siteName = siteName
        self.url = url
        self.accessDate = accessDate
        self.publisher = publisher
        self.doi = doi
    }
}

// MARK: - Citation Result

/// A generated citation with metadata.
struct CitationResult {
    /// The formatted citation string.
    let citation: String
    /// The format used.
    let format: CitationFormat
    /// The metadata used to generate it.
    let metadata: CitationMetadata
    /// Warnings about missing or potentially incorrect data.
    let warnings: [String]
}

// MARK: - Citation Generator

/// Generates formatted academic citations from article metadata.
///
/// Usage:
/// ```swift
/// let gen = ArticleCitationGenerator()
/// let meta = CitationMetadata(
///     title: "AI Safety in 2026",
///     authors: ["John Smith", "Jane Doe"],
///     publicationDate: someDate,
///     siteName: "Tech Review",
///     url: "https://example.com/article"
/// )
/// let result = gen.generate(metadata: meta, format: .apa)
/// print(result.citation)
/// ```
class ArticleCitationGenerator {

    // MARK: - Date Formatters

    private let yearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private let apaDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy, MMMM d"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private let mlaDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM. yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private let chicagoDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private let accessDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private let bibtexDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - Public API

    /// Generate a citation in the specified format.
    func generate(metadata: CitationMetadata, format: CitationFormat) -> CitationResult {
        var warnings: [String] = []

        if metadata.title.trimmingCharacters(in: .whitespaces).isEmpty {
            warnings.append("Title is empty")
        }
        if metadata.authors.isEmpty {
            warnings.append("No authors specified")
        }
        if metadata.publicationDate == nil {
            warnings.append("No publication date")
        }
        if metadata.url == nil && metadata.doi == nil {
            warnings.append("No URL or DOI provided")
        }

        let citation: String
        switch format {
        case .apa:
            citation = generateAPA(metadata: metadata)
        case .mla:
            citation = generateMLA(metadata: metadata)
        case .chicago:
            citation = generateChicago(metadata: metadata)
        case .ieee:
            citation = generateIEEE(metadata: metadata)
        case .harvard:
            citation = generateHarvard(metadata: metadata)
        case .bibtex:
            citation = generateBibTeX(metadata: metadata)
        }

        return CitationResult(
            citation: citation,
            format: format,
            metadata: metadata,
            warnings: warnings
        )
    }

    /// Generate citations in all supported formats.
    func generateAll(metadata: CitationMetadata) -> [CitationResult] {
        return CitationFormat.allCases.map { generate(metadata: metadata, format: $0) }
    }

    /// Generate a citation from a Story object (convenience).
    func generateFromStory(_ story: Story, format: CitationFormat,
                           authors: [String] = [],
                           publicationDate: Date? = nil,
                           siteName: String? = nil,
                           accessDate: Date = Date()) -> CitationResult {
        let meta = CitationMetadata(
            title: story.title,
            authors: authors,
            publicationDate: publicationDate,
            siteName: siteName ?? story.sourceFeedName,
            url: story.link,
            accessDate: accessDate
        )
        return generate(metadata: meta, format: format)
    }

    /// Parse an author string into a structured AuthorName.
    func parseAuthor(_ name: String) -> AuthorName {
        return ArticleCitationGenerator.parseAuthorName(name)
    }

    /// Generate a BibTeX key from metadata.
    func bibtexKey(metadata: CitationMetadata) -> String {
        return makeBibtexKey(metadata: metadata)
    }

    // MARK: - Author Parsing

    /// Parse a name string into an AuthorName.
    /// Handles "First Last", "First Middle Last", "Last, First", "Last, First Middle".
    static func parseAuthorName(_ name: String) -> AuthorName {
        let trimmed = name.trimmingCharacters(in: .whitespaces)

        // "Last, First [Middle...]" format
        if trimmed.contains(",") {
            let parts = trimmed.split(separator: ",", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2 else {
                return AuthorName(firstName: trimmed, lastName: "", middleInitials: [])
            }
            let lastName = parts[0]
            let firstParts = parts[1].split(separator: " ").map(String.init)
            if firstParts.isEmpty {
                return AuthorName(firstName: "", lastName: lastName, middleInitials: [])
            }
            let firstName = firstParts[0]
            let middles = Array(firstParts.dropFirst())
            return AuthorName(firstName: firstName, lastName: lastName, middleInitials: middles)
        }

        // "First [Middle...] Last" format
        let words = trimmed.split(separator: " ").map(String.init)
        switch words.count {
        case 0:
            return AuthorName(firstName: "", lastName: "", middleInitials: [])
        case 1:
            return AuthorName(firstName: words[0], lastName: "", middleInitials: [])
        case 2:
            return AuthorName(firstName: words[0], lastName: words[1], middleInitials: [])
        default:
            let firstName = words[0]
            let lastName = words.last!
            let middles = Array(words[1..<(words.count - 1)])
            return AuthorName(firstName: firstName, lastName: lastName, middleInitials: middles)
        }
    }

    // MARK: - APA 7th Edition

    /// APA format:
    /// Author, A. A., & Author, B. B. (Year, Month Day). Title of article. *Site Name*. URL
    private func generateAPA(metadata: CitationMetadata) -> String {
        var parts: [String] = []

        // Authors
        let parsed = metadata.authors.map(ArticleCitationGenerator.parseAuthorName)
        if !parsed.isEmpty {
            parts.append(formatAPAAuthors(parsed))
        }

        // Date
        if let date = metadata.publicationDate {
            parts.append("(\(apaDateFormatter.string(from: date)))")
        } else {
            parts.append("(n.d.)")
        }

        // Title (no italics for web articles)
        let title = metadata.title.trimmingCharacters(in: .whitespaces)
        if !title.isEmpty {
            // APA: sentence case, but we preserve original since article titles vary
            parts.append(title + ".")
        }

        // Site name (italicized)
        if let site = metadata.siteName, !site.isEmpty {
            parts.append("*\(site)*.")
        }

        // DOI or URL
        if let doi = metadata.doi, !doi.isEmpty {
            parts.append("https://doi.org/\(doi)")
        } else if let url = metadata.url, !url.isEmpty {
            parts.append(url)
        }

        return parts.joined(separator: " ")
    }

    private func formatAPAAuthors(_ authors: [AuthorName]) -> String {
        switch authors.count {
        case 1:
            return authors[0].apaFormat
        case 2:
            return "\(authors[0].apaFormat), & \(authors[1].apaFormat)"
        default:
            // APA 7th: list up to 20 authors
            if authors.count <= 20 {
                let allButLast = authors.dropLast().map { $0.apaFormat }.joined(separator: ", ")
                return "\(allButLast), & \(authors.last!.apaFormat)"
            } else {
                let first19 = authors.prefix(19).map { $0.apaFormat }.joined(separator: ", ")
                return "\(first19), . . . \(authors.last!.apaFormat)"
            }
        }
    }

    // MARK: - MLA 9th Edition

    /// MLA format:
    /// Author. "Title of Article." *Site Name*, Publisher, Day Mon. Year, URL. Accessed Day Mon. Year.
    private func generateMLA(metadata: CitationMetadata) -> String {
        var parts: [String] = []

        // Authors
        let parsed = metadata.authors.map(ArticleCitationGenerator.parseAuthorName)
        if !parsed.isEmpty {
            parts.append(formatMLAAuthors(parsed) + ".")
        }

        // Title in quotes
        let title = metadata.title.trimmingCharacters(in: .whitespaces)
        if !title.isEmpty {
            parts.append("\"\(title).\"")
        }

        // Container (site name, italicized)
        var container: [String] = []
        if let site = metadata.siteName, !site.isEmpty {
            container.append("*\(site)*")
        }
        if let pub = metadata.publisher, !pub.isEmpty,
           pub != metadata.siteName {
            container.append(pub)
        }
        if let date = metadata.publicationDate {
            container.append(mlaDateFormatter.string(from: date))
        }
        if let url = metadata.url, !url.isEmpty {
            // MLA removes protocol
            let clean = url.replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
            container.append(clean)
        }
        if !container.isEmpty {
            parts.append(container.joined(separator: ", ") + ".")
        }

        // Access date
        parts.append("Accessed \(accessDateFormatter.string(from: metadata.accessDate)).")

        return parts.joined(separator: " ")
    }

    private func formatMLAAuthors(_ authors: [AuthorName]) -> String {
        switch authors.count {
        case 1:
            return authors[0].mlaFormat(isFirst: true)
        case 2:
            return "\(authors[0].mlaFormat(isFirst: true)), and \(authors[1].mlaFormat(isFirst: false))"
        default:
            // MLA: first author + et al. for 3+
            return "\(authors[0].mlaFormat(isFirst: true)), et al."
        }
    }

    // MARK: - Chicago 17th Edition (Author-Date)

    /// Chicago format:
    /// Author. Year. "Title." *Site Name*. Month Day, Year. URL.
    private func generateChicago(metadata: CitationMetadata) -> String {
        var parts: [String] = []

        // Authors
        let parsed = metadata.authors.map(ArticleCitationGenerator.parseAuthorName)
        if !parsed.isEmpty {
            parts.append(formatChicagoAuthors(parsed) + ".")
        }

        // Year
        if let date = metadata.publicationDate {
            parts.append(yearFormatter.string(from: date) + ".")
        }

        // Title in quotes
        let title = metadata.title.trimmingCharacters(in: .whitespaces)
        if !title.isEmpty {
            parts.append("\"\(title).\"")
        }

        // Site name
        if let site = metadata.siteName, !site.isEmpty {
            parts.append("*\(site)*.")
        }

        // Full date
        if let date = metadata.publicationDate {
            parts.append(chicagoDateFormatter.string(from: date) + ".")
        }

        // URL
        if let doi = metadata.doi, !doi.isEmpty {
            parts.append("https://doi.org/\(doi).")
        } else if let url = metadata.url, !url.isEmpty {
            parts.append("\(url).")
        }

        return parts.joined(separator: " ")
    }

    private func formatChicagoAuthors(_ authors: [AuthorName]) -> String {
        switch authors.count {
        case 1:
            return authors[0].chicagoFormat(isFirst: true)
        case 2:
            return "\(authors[0].chicagoFormat(isFirst: true)), and \(authors[1].chicagoFormat(isFirst: false))"
        case 3:
            return "\(authors[0].chicagoFormat(isFirst: true)), \(authors[1].chicagoFormat(isFirst: false)), and \(authors[2].chicagoFormat(isFirst: false))"
        default:
            // Chicago: first author + et al. for 4+
            return "\(authors[0].chicagoFormat(isFirst: true)), et al."
        }
    }

    // MARK: - IEEE

    /// IEEE format:
    /// [1] A. A. Author, "Title," *Site Name*, Mon. Day, Year. [Online]. Available: URL. [Accessed: Mon. Day, Year].
    private func generateIEEE(metadata: CitationMetadata) -> String {
        var parts: [String] = []

        // Authors
        let parsed = metadata.authors.map(ArticleCitationGenerator.parseAuthorName)
        if !parsed.isEmpty {
            let authorStr = formatIEEEAuthors(parsed)
            parts.append(authorStr + ",")
        }

        // Title in quotes
        let title = metadata.title.trimmingCharacters(in: .whitespaces)
        if !title.isEmpty {
            parts.append("\"\(title),\"")
        }

        // Site name (italicized)
        if let site = metadata.siteName, !site.isEmpty {
            parts.append("*\(site)*,")
        }

        // Date
        if let date = metadata.publicationDate {
            let ieeeDate = formatIEEEDate(date)
            parts.append(ieeeDate + ".")
        }

        // Online/Available
        if let doi = metadata.doi, !doi.isEmpty {
            parts.append("[Online]. Available: https://doi.org/\(doi).")
        } else if let url = metadata.url, !url.isEmpty {
            parts.append("[Online]. Available: \(url).")
        }

        // Accessed
        let accessStr = formatIEEEDate(metadata.accessDate)
        parts.append("[Accessed: \(accessStr)].")

        return parts.joined(separator: " ")
    }

    private func formatIEEEAuthors(_ authors: [AuthorName]) -> String {
        switch authors.count {
        case 1:
            return authors[0].ieeeFormat
        case 2:
            return "\(authors[0].ieeeFormat) and \(authors[1].ieeeFormat)"
        default:
            if authors.count <= 6 {
                let allButLast = authors.dropLast().map { $0.ieeeFormat }.joined(separator: ", ")
                return "\(allButLast), and \(authors.last!.ieeeFormat)"
            } else {
                return "\(authors[0].ieeeFormat) et al."
            }
        }
    }

    private func formatIEEEDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM. d, yyyy"
        return formatter.string(from: date)
    }

    // MARK: - Harvard

    /// Harvard format:
    /// Author, A.A. (Year) 'Title', *Site Name*. Available at: URL (Accessed: Day Month Year).
    private func generateHarvard(metadata: CitationMetadata) -> String {
        var parts: [String] = []

        // Authors
        let parsed = metadata.authors.map(ArticleCitationGenerator.parseAuthorName)
        if !parsed.isEmpty {
            parts.append(formatHarvardAuthors(parsed))
        }

        // Year
        if let date = metadata.publicationDate {
            parts.append("(\(yearFormatter.string(from: date)))")
        } else {
            parts.append("(n.d.)")
        }

        // Title in single quotes
        let title = metadata.title.trimmingCharacters(in: .whitespaces)
        if !title.isEmpty {
            parts.append("'\(title)',")
        }

        // Site name
        if let site = metadata.siteName, !site.isEmpty {
            parts.append("*\(site)*.")
        }

        // URL with access date
        if let doi = metadata.doi, !doi.isEmpty {
            let accessStr = formatHarvardAccessDate(metadata.accessDate)
            parts.append("Available at: https://doi.org/\(doi) (Accessed: \(accessStr)).")
        } else if let url = metadata.url, !url.isEmpty {
            let accessStr = formatHarvardAccessDate(metadata.accessDate)
            parts.append("Available at: \(url) (Accessed: \(accessStr)).")
        }

        return parts.joined(separator: " ")
    }

    private func formatHarvardAuthors(_ authors: [AuthorName]) -> String {
        switch authors.count {
        case 1:
            return authors[0].harvardFormat
        case 2:
            return "\(authors[0].harvardFormat) and \(authors[1].harvardFormat)"
        case 3:
            return "\(authors[0].harvardFormat), \(authors[1].harvardFormat) and \(authors[2].harvardFormat)"
        default:
            return "\(authors[0].harvardFormat) et al."
        }
    }

    private func formatHarvardAccessDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }

    // MARK: - BibTeX

    /// Generates a BibTeX @misc entry.
    private func generateBibTeX(metadata: CitationMetadata) -> String {
        let key = makeBibtexKey(metadata: metadata)
        var fields: [(String, String)] = []

        // Authors
        if !metadata.authors.isEmpty {
            let parsed = metadata.authors.map(ArticleCitationGenerator.parseAuthorName)
            let authorStr = parsed.map { $0.bibtexFormat }.joined(separator: " and ")
            fields.append(("author", authorStr))
        }

        // Title
        let title = metadata.title.trimmingCharacters(in: .whitespaces)
        if !title.isEmpty {
            fields.append(("title", "{\(title)}"))
        }

        // Year
        if let date = metadata.publicationDate {
            fields.append(("year", yearFormatter.string(from: date)))
        }

        // Publisher/howpublished
        if let site = metadata.siteName, !site.isEmpty {
            fields.append(("howpublished", "\\url{\(site)}"))
        }

        // URL
        if let url = metadata.url, !url.isEmpty {
            fields.append(("url", url))
        }

        // DOI
        if let doi = metadata.doi, !doi.isEmpty {
            fields.append(("doi", doi))
        }

        // Access note
        let accessStr = bibtexDateFormatter.string(from: metadata.accessDate)
        fields.append(("note", "Accessed: \(accessStr)"))

        // Format
        var lines: [String] = ["@misc{\(key),"]
        for (i, field) in fields.enumerated() {
            let value = field.0 == "title" ? field.1 : "{\(field.1)}"
            let comma = i < fields.count - 1 ? "," : ""
            lines.append("  \(field.0) = \(value)\(comma)")
        }
        lines.append("}")

        return lines.joined(separator: "\n")
    }

    private func makeBibtexKey(metadata: CitationMetadata) -> String {
        // Key: firstAuthorLastName + year + first significant title word
        var keyParts: [String] = []

        if let firstAuthor = metadata.authors.first {
            let parsed = ArticleCitationGenerator.parseAuthorName(firstAuthor)
            let clean = parsed.lastName.lowercased()
                .filter { $0.isLetter }
            if !clean.isEmpty {
                keyParts.append(clean)
            }
        }

        if let date = metadata.publicationDate {
            keyParts.append(yearFormatter.string(from: date))
        }

        // First significant word from title (skip articles)
        let stopWords: Set<String> = ["a", "an", "the", "of", "in", "on", "for", "and", "to", "with"]
        let titleWords = metadata.title.lowercased()
            .split(separator: " ")
            .map { $0.filter { $0.isLetter } }
            .filter { !$0.isEmpty && !stopWords.contains(String($0)) }
        if let firstWord = titleWords.first {
            keyParts.append(String(firstWord))
        }

        return keyParts.isEmpty ? "unknown" : keyParts.joined(separator: "")
    }

    // MARK: - Batch Operations

    /// Generate citations for multiple articles in the same format.
    func batchGenerate(metadataList: [CitationMetadata], format: CitationFormat) -> [CitationResult] {
        return metadataList.map { generate(metadata: $0, format: format) }
    }

    /// Generate a formatted bibliography from multiple articles.
    func bibliography(metadataList: [CitationMetadata], format: CitationFormat,
                      numbered: Bool = false) -> String {
        let results = batchGenerate(metadataList: metadataList, format: format)
        if numbered {
            return results.enumerated().map { (i, r) in
                "[\(i + 1)] \(r.citation)"
            }.joined(separator: "\n\n")
        }
        return results.map { $0.citation }.joined(separator: "\n\n")
    }

    /// Generate a combined BibTeX file from multiple articles.
    func bibtexFile(metadataList: [CitationMetadata]) -> String {
        let results = metadataList.map { generate(metadata: $0, format: .bibtex) }
        return results.map { $0.citation }.joined(separator: "\n\n")
    }

    // MARK: - Citation Validation

    /// Check citation completeness and return a quality score (0-100).
    func qualityScore(metadata: CitationMetadata) -> Int {
        var score = 0

        // Title (required, 25 pts)
        if !metadata.title.trimmingCharacters(in: .whitespaces).isEmpty {
            score += 25
        }

        // Authors (important, 25 pts)
        if !metadata.authors.isEmpty {
            score += 20
            // Bonus for multiple authors
            if metadata.authors.count > 1 {
                score += 5
            }
        }

        // Date (important, 20 pts)
        if metadata.publicationDate != nil {
            score += 20
        }

        // Source (site name, 15 pts)
        if let site = metadata.siteName, !site.isEmpty {
            score += 15
        }

        // URL or DOI (15 pts, DOI preferred)
        if let doi = metadata.doi, !doi.isEmpty {
            score += 15
        } else if let url = metadata.url, !url.isEmpty {
            score += 10
        }

        return min(score, 100)
    }

    /// Generate a text report for citation quality.
    func qualityReport(metadata: CitationMetadata) -> String {
        let score = qualityScore(metadata: metadata)
        let result = generate(metadata: metadata, format: .apa)

        var lines: [String] = []
        lines.append("=== Citation Quality Report ===")
        lines.append("Title: \(metadata.title)")
        lines.append("Quality Score: \(score)/100")
        lines.append("")

        if metadata.authors.isEmpty {
            lines.append("⚠ Missing: Authors")
        } else {
            lines.append("✓ Authors: \(metadata.authors.count)")
        }

        if metadata.publicationDate == nil {
            lines.append("⚠ Missing: Publication date")
        } else {
            lines.append("✓ Publication date present")
        }

        if metadata.siteName == nil || metadata.siteName!.isEmpty {
            lines.append("⚠ Missing: Site/publication name")
        } else {
            lines.append("✓ Site name: \(metadata.siteName!)")
        }

        if metadata.doi != nil && !metadata.doi!.isEmpty {
            lines.append("✓ DOI: \(metadata.doi!)")
        } else if metadata.url != nil && !metadata.url!.isEmpty {
            lines.append("~ URL present (DOI preferred)")
        } else {
            lines.append("⚠ Missing: URL and DOI")
        }

        if !result.warnings.isEmpty {
            lines.append("")
            lines.append("Warnings:")
            for w in result.warnings {
                lines.append("  - \(w)")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - JSON Persistence

    /// Export citation metadata as a JSON-compatible dictionary.
    func exportToJSON(metadata: CitationMetadata) -> [String: Any] {
        var dict: [String: Any] = [
            "title": metadata.title,
            "authors": metadata.authors,
            "accessDate": bibtexDateFormatter.string(from: metadata.accessDate)
        ]
        if let date = metadata.publicationDate {
            dict["publicationDate"] = bibtexDateFormatter.string(from: date)
        }
        if let site = metadata.siteName { dict["siteName"] = site }
        if let url = metadata.url { dict["url"] = url }
        if let pub = metadata.publisher { dict["publisher"] = pub }
        if let doi = metadata.doi { dict["doi"] = doi }
        return dict
    }

    /// Import citation metadata from a JSON-compatible dictionary.
    func importFromJSON(_ dict: [String: Any]) -> CitationMetadata? {
        guard let title = dict["title"] as? String else { return nil }
        let authors = dict["authors"] as? [String] ?? []
        let siteName = dict["siteName"] as? String
        let url = dict["url"] as? String
        let publisher = dict["publisher"] as? String
        let doi = dict["doi"] as? String

        var pubDate: Date?
        if let dateStr = dict["publicationDate"] as? String {
            pubDate = bibtexDateFormatter.date(from: dateStr)
        }
        var accessDate = Date()
        if let accessStr = dict["accessDate"] as? String,
           let parsed = bibtexDateFormatter.date(from: accessStr) {
            accessDate = parsed
        }

        return CitationMetadata(
            title: title,
            authors: authors,
            publicationDate: pubDate,
            siteName: siteName,
            url: url,
            accessDate: accessDate,
            publisher: publisher,
            doi: doi
        )
    }
}
