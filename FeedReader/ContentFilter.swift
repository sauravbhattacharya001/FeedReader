//
//  ContentFilter.swift
//  FeedReader
//
//  Content filter model for muting unwanted stories by keyword/phrase.
//

import Foundation

/// A keyword-based content filter that can mute (hide) stories matching the keyword.
///
/// Supports three match scopes (title, body, or both) and three match modes
/// (substring contains, exact word boundary, and regular expression). Filters
/// are persisted via both `NSSecureCoding` and `Codable` conformance.
///
/// Usage:
/// ```swift
/// if let filter = ContentFilter(keyword: "spoiler", matchMode: .exactWord) {
///     // add to the active filter list
/// }
/// ```
class ContentFilter: NSObject, NSSecureCoding, Codable {
    
    // MARK: - NSSecureCoding
    
    /// Indicates that this class supports secure coding for safe deserialization.
    static var supportsSecureCoding: Bool { return true }
    
    // MARK: - Types
    
    /// Determines which parts of an article the filter keyword is matched against.
    enum MatchScope: String, Codable {
        /// Match against the article title only.
        case title
        /// Match against the article body only.
        case body
        /// Match against both the article title and body.
        case both
    }
    
    /// Determines how the filter keyword is compared to article content.
    enum MatchMode: String, Codable {
        /// Case-insensitive substring search.
        case contains
        /// Matches the keyword only at word boundaries.
        case exactWord
        /// Treats the keyword as a regular expression pattern.
        case regex
    }
    
    /// Constants used as keys for `NSCoder`-based archiving.
    struct PropertyKey {
        static let idKey = "contentFilterId"
        static let keywordKey = "contentFilterKeyword"
        static let isActiveKey = "contentFilterIsActive"
        static let matchScopeKey = "contentFilterMatchScope"
        static let matchModeKey = "contentFilterMatchMode"
        static let createdAtKey = "contentFilterCreatedAt"
        static let mutedCountKey = "contentFilterMutedCount"
    }
    
    // MARK: - Limits
    
    /// Maximum allowed length for a filter keyword (characters beyond this are truncated).
    static let maxKeywordLength = 200
    
    // MARK: - Properties
    
    /// Unique identifier for this filter (UUID string by default).
    var id: String
    /// The keyword or pattern to match against article content.
    var keyword: String
    /// Whether this filter is currently active and should be evaluated.
    var isActive: Bool
    /// Which parts of an article to match the keyword against.
    var matchScope: MatchScope
    /// How the keyword is compared to article content.
    var matchMode: MatchMode
    /// Timestamp when this filter was created.
    var createdAt: Date
    /// Running count of articles this filter has muted.
    var mutedCount: Int
    
    // MARK: - Initialization
    
    /// Creates a new content filter with the given parameters.
    ///
    /// The keyword is trimmed of whitespace and truncated to ``maxKeywordLength``.
    /// Returns `nil` if the keyword is empty after trimming, or if `matchMode`
    /// is `.regex` and the pattern fails to compile.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (defaults to a new UUID string).
    ///   - keyword: The keyword or regex pattern to filter on.
    ///   - isActive: Whether the filter starts active (default `true`).
    ///   - matchScope: Which article fields to match against (default `.both`).
    ///   - matchMode: How to compare the keyword (default `.contains`).
    ///   - createdAt: Creation timestamp (defaults to now).
    ///   - mutedCount: Initial muted article count (default `0`).
    init?(id: String = UUID().uuidString, keyword: String, isActive: Bool = true,
          matchScope: MatchScope = .both, matchMode: MatchMode = .contains,
          createdAt: Date = Date(), mutedCount: Int = 0) {
        
        let trimmed = String(keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(ContentFilter.maxKeywordLength))
        guard !trimmed.isEmpty else { return nil }
        
        // For regex mode, validate the pattern compiles
        if matchMode == .regex {
            do {
                _ = try NSRegularExpression(pattern: trimmed, options: [.caseInsensitive])
            } catch {
                return nil
            }
        }
        
        self.id = id
        self.keyword = trimmed
        self.isActive = isActive
        self.matchScope = matchScope
        self.matchMode = matchMode
        self.createdAt = createdAt
        self.mutedCount = mutedCount
        
        super.init()
    }
    
    // MARK: - NSCoding
    
    /// Encodes the filter's properties into the given coder for archiving.
    ///
    /// - Parameter coder: The coder to write properties into.
    func encode(with coder: NSCoder) {
        coder.encode(id, forKey: PropertyKey.idKey)
        coder.encode(keyword, forKey: PropertyKey.keywordKey)
        coder.encode(isActive, forKey: PropertyKey.isActiveKey)
        coder.encode(matchScope.rawValue, forKey: PropertyKey.matchScopeKey)
        coder.encode(matchMode.rawValue, forKey: PropertyKey.matchModeKey)
        coder.encode(createdAt as NSDate, forKey: PropertyKey.createdAtKey)
        coder.encode(mutedCount, forKey: PropertyKey.mutedCountKey)
    }
    
    /// Decodes a filter from the given coder.
    ///
    /// Returns `nil` if required keys (`id`, `keyword`, `matchScope`, `matchMode`)
    /// are missing or if the decoded keyword would produce an invalid filter.
    ///
    /// - Parameter decoder: The coder to read properties from.
    required convenience init?(coder decoder: NSCoder) {
        guard let id = decoder.decodeObject(of: NSString.self, forKey: PropertyKey.idKey) as String?,
              let keyword = decoder.decodeObject(of: NSString.self, forKey: PropertyKey.keywordKey) as String?,
              let scopeRaw = decoder.decodeObject(of: NSString.self, forKey: PropertyKey.matchScopeKey) as String?,
              let modeRaw = decoder.decodeObject(of: NSString.self, forKey: PropertyKey.matchModeKey) as String? else {
            return nil
        }
        
        let isActive = decoder.decodeBool(forKey: PropertyKey.isActiveKey)
        let createdAt = decoder.decodeObject(of: NSDate.self, forKey: PropertyKey.createdAtKey) as Date? ?? Date()
        let mutedCount = decoder.decodeInteger(forKey: PropertyKey.mutedCountKey)
        let matchScope = MatchScope(rawValue: scopeRaw) ?? .both
        let matchMode = MatchMode(rawValue: modeRaw) ?? .contains
        
        self.init(id: id, keyword: keyword, isActive: isActive,
                  matchScope: matchScope, matchMode: matchMode,
                  createdAt: createdAt, mutedCount: mutedCount)
    }
    
    // MARK: - Codable
    
    /// Coding keys for `Codable` conformance, mapping to JSON property names.
    enum CodingKeys: String, CodingKey {
        case id, keyword, isActive, matchScope, matchMode, createdAt, mutedCount
    }
}
